// Orthoverse web proxy: lets the in-browser Luanti client (luanti-wasm) reach
// the Orthoverse server.
//
// Browsers cannot send UDP, so the web client talks to this proxy over a
// WebSocket and the proxy relays its datagrams to the Luanti server. It speaks
// the protocol of paradust7/webshims (src/emsocket/proxy.js, revision 70653a9):
//
//   NEWADDR                       -> ADDR <address> <passcode> <joincode>
//   BIND <passcode> UDP <port>    -> BIND OK | BIND FAILED
//       then binary messages, each a 24 byte header and a datagram:
//       magic u32 0x778B4CF6, peer address 16 bytes (IPv6, IPv4-mapped),
//       peer port u16, length u16
//   PROXY IPV6 TCP fd00::1 53     -> PROXY OK, then one name lookup
//
// Unlike a general-purpose proxy it reaches exactly one place: the Orthoverse
// server. Datagrams to any other address are dropped, there is no TCP relaying,
// and the resolver only knows the Orthoverse's own names.

'use strict';

import dgram from 'node:dgram';
import { randomBytes } from 'node:crypto';
import { isIPv4, isIPv6 } from 'node:net';
import { WebSocketServer } from 'ws';

// ---------------------------------------------------------------------------
// Settings (environment variables, with defaults for the ProLiant)

const env = process.env;
const LISTEN_HOST = env.OV_PROXY_HOST || '127.0.0.1';
const LISTEN_PORT = parseInt(env.OV_PROXY_PORT || '8737', 10);
// Where the Luanti server really is: an address, or a name such as the
// Compose service "luanti" (looked up again for each player, so a restarted
// container with a new address is found)
const TARGET_HOST = env.OV_TARGET_HOST || '127.0.0.1';
const TARGET_PORT = parseInt(env.OV_TARGET_PORT || '30000', 10);
// The address web players dial. It only exists inside the proxy.
const VIRTUAL_IP = env.OV_VIRTUAL_IP || '10.58.0.1';
// Names the resolver answers with VIRTUAL_IP, comma separated
const NAMES = (env.OV_NAMES || 'orthoverse.land,play.orthoverse.land,orthoverse')
    .split(',').map(s => s.trim().toLowerCase()).filter(Boolean);
// Limits
const MAX_SOCKETS = parseInt(env.OV_MAX_SOCKETS || '100', 10);
const MAX_PER_IP = parseInt(env.OV_MAX_PER_IP || '6', 10);
const IDLE_MS = parseInt(env.OV_IDLE_SECONDS || '120', 10) * 1000;
const ADDR_TTL_MS = 24 * 3600 * 1000;
const MAX_ASSIGNMENTS = 20000;
const MAX_DATAGRAM = 1500;

// ---------------------------------------------------------------------------
// Address helpers

const EP_MAGIC = 0x778B4CF6;
const EP_HEADER_LEN = 24;
const LUANTI_MAGIC = 0x4f457403;
const SERVICE_ADDRESS = 'fd00::1';   // the proxy's own services (resolver)
const DNS_PORT = 53;

// IPv4 literal -> 16 byte IPv4-mapped IPv6 address
function mapped(ip4) {
    const b = Buffer.alloc(16);
    b[10] = 0xff;
    b[11] = 0xff;
    ip4.split('.').forEach((p, i) => { b[12 + i] = parseInt(p, 10); });
    return b;
}

const VIRTUAL_BYTES = mapped(VIRTUAL_IP);

function log(...args) {
    console.log(new Date().toISOString(), ...args);
}

function token(n) {
    return randomBytes(n).toString('hex');
}

// Client IP as Cloudflare and nginx report it; the socket address is the
// local nginx, so it is only a fallback.
function clientIp(request) {
    const h = request.headers;
    const cf = h['cf-connecting-ip'];
    if (cf) return String(cf).trim();
    const xff = h['x-forwarded-for'];
    if (xff) return String(xff).split(',')[0].trim();
    return request.socket.remoteAddress || '?';
}

// ---------------------------------------------------------------------------
// Address assignments: what NEWADDR hands out and BIND checks

const assignments = new Map(); // passcode -> { address, expires }
let nextHost = 1;

function newAssignment() {
    const n = nextHost++;
    const address = `fd58::${(n >>> 16).toString(16)}:${(n & 0xffff).toString(16)}`;
    const passcode = token(16);
    const joincode = 'none';
    assignments.set(passcode, { address, expires: Date.now() + ADDR_TTL_MS });
    // Bounded, so that asking for addresses over and over cannot eat memory:
    // the oldest go first (a Map keeps insertion order).
    while (assignments.size > MAX_ASSIGNMENTS) {
        assignments.delete(assignments.keys().next().value);
    }
    return { address, passcode, joincode };
}

setInterval(() => {
    const now = Date.now();
    for (const [code, a] of assignments) {
        if (a.expires < now) assignments.delete(code);
    }
}, 3600 * 1000).unref();

// ---------------------------------------------------------------------------
// Connections

let openSockets = 0;
const perIp = new Map();
// Connections from one address that have not yet bound (or looked up a name):
// a few at a time, and only for a few seconds, so nobody can hold open
// thousands of idle sockets
const waitingPerIp = new Map();
const MAX_WAITING_PER_IP = 20;
const COMMAND_MS = 15000;
let connId = 0;

function countIp(ip, delta) {
    const n = (perIp.get(ip) || 0) + delta;
    if (n <= 0) perIp.delete(ip); else perIp.set(ip, n);
    return n;
}

class Connection {
    constructor(ws, request) {
        this.id = ++connId;
        this.ws = ws;
        this.ip = clientIp(request);
        this.udp = null;       // UDP socket to the Luanti server, once bound
        this.mode = 'command'; // command | udp | dns | closed
        this.counted = false;
        this.lastActivity = Date.now();
        this.idleTimer = setInterval(() => {
            if (Date.now() - this.lastActivity > IDLE_MS) {
                this.close('idle');
            }
        }, 15000);
        ws.on('message', (data, isBinary) => this.onMessage(data, isBinary));
        ws.on('close', () => this.close());
        ws.on('error', () => this.close('websocket error'));
        this.waiting = true;
        const w = (waitingPerIp.get(this.ip) || 0) + 1;
        waitingPerIp.set(this.ip, w);
        if (w > MAX_WAITING_PER_IP) {
            log(`[${this.id}] ${this.ip} refused: too many new connections from this address`);
            this.close();
            return;
        }
        this.commandTimer = setTimeout(() => {
            if (this.mode !== 'udp') this.close();
        }, COMMAND_MS);
    }

    // No longer waiting (bound to the game, or closed)
    doneWaiting() {
        if (!this.waiting) return;
        this.waiting = false;
        clearTimeout(this.commandTimer);
        const w = (waitingPerIp.get(this.ip) || 0) - 1;
        if (w <= 0) waitingPerIp.delete(this.ip); else waitingPerIp.set(this.ip, w);
    }

    send(data) {
        if (this.ws && this.ws.readyState === 1) {
            this.ws.send(data, { binary: typeof data !== 'string' });
        }
    }

    close(reason) {
        if (this.mode === 'closed') return;
        if (reason && this.mode === 'udp') log(`[${this.id}] ${this.ip} closed: ${reason}`);
        this.mode = 'closed';
        this.doneWaiting();
        clearInterval(this.idleTimer);
        if (this.udp) {
            try { this.udp.close(); } catch (e) { /* already closed */ }
            this.udp = null;
        }
        if (this.counted) {
            openSockets--;
            countIp(this.ip, -1);
            this.counted = false;
        }
        if (this.ws) {
            const ws = this.ws;
            this.ws = null;
            try { ws.close(); } catch (e) { /* already closed */ }
        }
    }

    onMessage(data, isBinary) {
        this.lastActivity = Date.now();
        try {
            if (this.mode === 'command') {
                if (isBinary) throw new Error('binary before a command');
                this.onCommand(data.toString('latin1'));
            } else if (this.mode === 'udp') {
                this.onDatagram(data);
            } else if (this.mode === 'dns') {
                this.onLookup(data.toString('latin1'));
            }
        } catch (e) {
            log(`[${this.id}] ${this.ip} protocol error: ${e.message}`);
            this.close();
        }
    }

    onCommand(line) {
        const t = line.replace(/[^\x20-\x7e]/g, '').split(' ');
        if (t[0] === 'NEWADDR') {
            const a = newAssignment();
            this.send(`ADDR ${a.address} ${a.passcode} ${a.joincode}`);
            this.close();
        } else if (t[0] === 'BIND' && t.length === 4 && t[2] === 'UDP') {
            this.bind(t[1]);
        } else if (t[0] === 'PROXY' && t[2] === 'TCP' && t[3] === SERVICE_ADDRESS &&
                   parseInt(t[4], 10) === DNS_PORT) {
            this.mode = 'dns';
            this.send('PROXY OK');
        } else {
            // TCP to anywhere else (server list, HTTP) is not offered.
            if (t[0] === 'PROXY') this.send('PROXY FAIL');
            this.close();
        }
    }

    bind(passcode) {
        const a = assignments.get(passcode);
        if (!a) {
            // The client asks for a new address and binds again on this connection.
            this.send('BIND FAILED');
            return;
        }
        if (openSockets >= MAX_SOCKETS) {
            log(`[${this.id}] ${this.ip} refused: server full (${openSockets})`);
            this.close();
            return;
        }
        if ((perIp.get(this.ip) || 0) >= MAX_PER_IP) {
            log(`[${this.id}] ${this.ip} refused: too many connections from this address`);
            this.close();
            return;
        }
        openSockets++;
        countIp(this.ip, 1);
        this.counted = true;
        a.expires = Date.now() + ADDR_TTL_MS;

        const udp = dgram.createSocket(isIPv6(TARGET_HOST) ? 'udp6' : 'udp4');
        this.udp = udp;
        udp.on('message', (msg, rinfo) => {
            if (rinfo.port !== TARGET_PORT) return;
            const out = Buffer.alloc(EP_HEADER_LEN + msg.length);
            out.writeUInt32BE(EP_MAGIC, 0);
            VIRTUAL_BYTES.copy(out, 4);
            out.writeUInt16BE(TARGET_PORT, 20);
            out.writeUInt16BE(msg.length, 22);
            msg.copy(out, EP_HEADER_LEN);
            this.lastActivity = Date.now();
            this.send(out);
        });
        udp.on('error', (e) => this.close('udp error ' + e.message));
        udp.connect(TARGET_PORT, TARGET_HOST, () => {
            this.mode = 'udp';
            this.doneWaiting();
            log(`[${this.id}] ${this.ip} bound (${openSockets} open)`);
            this.send('BIND OK');
        });
    }

    onDatagram(data) {
        if (!Buffer.isBuffer(data) || data.length < EP_HEADER_LEN) {
            throw new Error('short datagram');
        }
        if (data.readUInt32BE(0) !== EP_MAGIC) throw new Error('bad header');
        const len = data.readUInt16BE(22);
        if (data.length !== EP_HEADER_LEN + len || len > MAX_DATAGRAM) {
            throw new Error('bad length');
        }
        const port = data.readUInt16BE(20);
        if (port !== TARGET_PORT || !data.subarray(4, 20).equals(VIRTUAL_BYTES)) {
            return; // anywhere but the Orthoverse: dropped
        }
        const payload = data.subarray(EP_HEADER_LEN);
        if (payload.length < 4 || payload.readUInt32BE(0) !== LUANTI_MAGIC) {
            throw new Error('not a Luanti datagram');
        }
        if (this.udp) this.udp.send(payload);
    }

    // One lookup: "<name> A|AAAA|ANY". Reply: count byte, then for each
    // record a family tag (4 or 6) and the address bytes.
    onLookup(req) {
        const [name, kind] = req.trim().toLowerCase().split(/\s+/);
        let reply;
        if (NAMES.includes(name) && kind !== 'aaaa') {
            const ip = VIRTUAL_IP.split('.').map(n => parseInt(n, 10));
            reply = Buffer.from([1, 4, ...ip]);
        } else {
            reply = Buffer.from([0]);
        }
        this.send(reply);
        this.close();
    }
}

// ---------------------------------------------------------------------------

if (!isIPv4(VIRTUAL_IP)) {
    console.error('OV_VIRTUAL_IP must be an IPv4 address');
    process.exit(1);
}
if (!isIPv4(TARGET_HOST) && !isIPv6(TARGET_HOST) && !/^[A-Za-z0-9.-]+$/.test(TARGET_HOST)) {
    console.error('OV_TARGET_HOST must be an IP address or a host name');
    process.exit(1);
}

const wss = new WebSocketServer({
    host: LISTEN_HOST,
    port: LISTEN_PORT,
    maxPayload: 64 * 1024,
});
wss.on('connection', (ws, request) => new Connection(ws, request));
wss.on('listening', () => {
    log(`Orthoverse web proxy on ws://${LISTEN_HOST}:${LISTEN_PORT}, ` +
        `relaying ${VIRTUAL_IP}:${TARGET_PORT} to ${TARGET_HOST}:${TARGET_PORT}, ` +
        `names: ${NAMES.join(' ')}`);
});

for (const sig of ['SIGINT', 'SIGTERM']) {
    process.on(sig, () => {
        log('shutting down');
        wss.close();
        process.exit(0);
    });
}
