// End-to-end test of the web proxy against a running Luanti server.
//
//   OV_PROXY_URL=ws://127.0.0.1:8737 node test/handshake.js
//
// Plays the browser side of the webshims protocol exactly as luanti-wasm does
// (NEWADDR, BIND, encapsulated datagrams, resolver lookup) and checks that a
// Luanti TOSERVER_INIT sent through the proxy gets the server's TOCLIENT_HELLO
// back. Also checks that the proxy refuses what it should refuse.

'use strict';

import WebSocket from 'ws';
import assert from 'node:assert/strict';

const URL_ = process.env.OV_PROXY_URL || 'ws://127.0.0.1:8737';
const VIRTUAL_IP = process.env.OV_VIRTUAL_IP || '10.58.0.1';
const PORT = parseInt(process.env.OV_TARGET_PORT || '30000', 10);

const EP_MAGIC = 0x778B4CF6;

function mapped(ip4) {
    const b = Buffer.alloc(16);
    b[10] = 0xff; b[11] = 0xff;
    ip4.split('.').forEach((p, i) => { b[12 + i] = parseInt(p, 10); });
    return b;
}

function encapsulate(ip4, port, payload) {
    const out = Buffer.alloc(24 + payload.length);
    out.writeUInt32BE(EP_MAGIC, 0);
    mapped(ip4).copy(out, 4);
    out.writeUInt16BE(port, 20);
    out.writeUInt16BE(payload.length, 22);
    payload.copy(out, 24);
    return out;
}

// Luanti low-level packet: base header, reliable header, original packet
function initPacket(name) {
    const nameBuf = Buffer.from(name, 'latin1');
    const body = Buffer.alloc(2 + 1 + 2 + 2 + 2 + 2 + nameBuf.length);
    let o = 0;
    body.writeUInt16BE(0x02, o); o += 2;      // TOSERVER_INIT
    body.writeUInt8(29, o); o += 1;            // serialization version
    body.writeUInt16BE(0, o); o += 2;          // unused
    body.writeUInt16BE(37, o); o += 2;         // min protocol
    body.writeUInt16BE(53, o); o += 2;         // max protocol (luanti-wasm 5.18-dev)
    body.writeUInt16BE(nameBuf.length, o); o += 2;
    nameBuf.copy(body, o);
    const hdr = Buffer.alloc(4 + 2 + 1 + 1 + 2 + 1);
    hdr.writeUInt32BE(0x4f457403, 0);          // PROTOCOL_ID
    hdr.writeUInt16BE(0, 4);                   // PEER_ID_INEXISTENT
    hdr.writeUInt8(1, 6);                      // channel
    hdr.writeUInt8(3, 7);                      // PACKET_TYPE_RELIABLE
    hdr.writeUInt16BE(65500, 8);               // SEQNUM_INITIAL
    hdr.writeUInt8(1, 10);                     // PACKET_TYPE_ORIGINAL
    return Buffer.concat([hdr, body]);
}

function open() {
    return new Promise((resolve, reject) => {
        const ws = new WebSocket(URL_);
        ws.binaryType = 'nodebuffer';
        // Every message is queued, so none is lost when several arrive together
        ws.inbox = [];
        ws.waiter = null;
        ws.closed = false;
        ws.on('message', (data, isBinary) => {
            ws.inbox.push(isBinary ? data : data.toString());
            if (ws.waiter) ws.waiter();
        });
        ws.on('close', () => { ws.closed = true; if (ws.waiter) ws.waiter(); });
        ws.once('open', () => resolve(ws));
        ws.once('error', reject);
    });
}

function nextMessage(ws, ms = 3000) {
    return new Promise((resolve, reject) => {
        const take = () => {
            if (ws.inbox.length) {
                clearTimeout(t);
                ws.waiter = null;
                resolve(ws.inbox.shift());
            } else if (ws.closed) {
                clearTimeout(t);
                ws.waiter = null;
                reject(new Error('closed'));
            }
        };
        const t = setTimeout(() => { ws.waiter = null; reject(new Error('timeout')); }, ms);
        ws.waiter = take;
        take();
    });
}

async function newAddr() {
    const ws = await open();
    ws.send('NEWADDR');
    const reply = await nextMessage(ws);
    const p = reply.split(' ');
    assert.equal(p.length, 4);
    assert.equal(p[0], 'ADDR');
    return { address: p[1], passcode: p[2] };
}

// Walk a Luanti packet down to the command id it carries, if any
function commandOf(pkt) {
    if (pkt.length < 7 || pkt.readUInt32BE(0) !== 0x4f457403) return null;
    let o = 7;
    let type = pkt.readUInt8(o);
    if (type === 3) { o += 3; type = pkt.readUInt8(o); }   // reliable
    if (type === 1 && pkt.length >= o + 3) return pkt.readUInt16BE(o + 1);
    return null;
}

const results = [];
async function check(name, fn) {
    try {
        await fn();
        results.push(['ok', name]);
    } catch (e) {
        results.push(['FAIL', name + ': ' + e.message]);
    }
}

await check('NEWADDR hands out an address', async () => {
    const a = await newAddr();
    assert.match(a.passcode, /^[0-9a-f]{32}$/);
});

await check('BIND with an unknown passcode is refused', async () => {
    const ws = await open();
    ws.send('BIND 00000000000000000000000000000000 UDP 40000');
    assert.equal(await nextMessage(ws), 'BIND FAILED');
    ws.close();
});

await check('TCP to anywhere but the resolver is refused', async () => {
    const ws = await open();
    ws.send('PROXY IPV4 TCP 1.1.1.1 80');
    assert.equal(await nextMessage(ws), 'PROXY FAIL');
});

await check('resolver knows orthoverse.land', async () => {
    const ws = await open();
    ws.send('PROXY IPV6 TCP fd00::1 53');
    assert.equal(await nextMessage(ws), 'PROXY OK');
    ws.send(Buffer.from('orthoverse.land A'));
    const r = await nextMessage(ws);
    assert.deepEqual([...r], [1, 4, ...VIRTUAL_IP.split('.').map(Number)]);
});

await check('resolver knows nothing else', async () => {
    const ws = await open();
    ws.send('PROXY IPV6 TCP fd00::1 53');
    await nextMessage(ws);
    ws.send(Buffer.from('example.com A'));
    assert.deepEqual([...(await nextMessage(ws))], [0]);
});

await check('datagrams to other addresses are dropped', async () => {
    const a = await newAddr();
    const ws = await open();
    ws.send(`BIND ${a.passcode} UDP 40001`);
    assert.equal(await nextMessage(ws), 'BIND OK');
    ws.send(encapsulate('192.168.68.1', PORT, initPacket('dropme')));
    await assert.rejects(nextMessage(ws, 1500), /timeout/);
    ws.close();
});

await check('TOSERVER_INIT through the proxy gets TOCLIENT_HELLO', async () => {
    const a = await newAddr();
    const ws = await open();
    ws.send(`BIND ${a.passcode} UDP 40002`);
    assert.equal(await nextMessage(ws), 'BIND OK');
    ws.send(encapsulate(VIRTUAL_IP, PORT, initPacket('Guest-' + (0x100000 + process.pid % 0xefffff).toString(16).toUpperCase())));
    const deadline = Date.now() + 5000;
    let hello = false;
    const seen = [];
    while (!hello && Date.now() < deadline) {
        const m = await nextMessage(ws, deadline - Date.now());
        assert.equal(m.readUInt32BE(0), EP_MAGIC);
        assert.ok(m.subarray(4, 20).equals(mapped(VIRTUAL_IP)), 'reply comes from the server address');
        assert.equal(m.readUInt16BE(20), PORT);
        const cmd = commandOf(m.subarray(24));
        seen.push(cmd);
        if (cmd === 0x02) hello = true;
    }
    assert.ok(hello, 'no TOCLIENT_HELLO; saw commands ' + JSON.stringify(seen));
    ws.close();
});

for (const [status, name] of results) console.log(`${status.padEnd(4)} ${name}`);
const failed = results.filter(r => r[0] !== 'ok').length;
console.log(failed ? `${failed} failed` : 'all passed');
process.exit(failed ? 1 : 0);
