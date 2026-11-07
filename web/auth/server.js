// Orthoverse auth service: wallet sign-in, player names, and who owns which land.
//
// Players sign in on the play page with an Ethereum wallet: the page asks for a
// sign-in message (Sign-In with Ethereum, EIP-4361), the wallet signs it, and
// this service checks the signature and gives the browser a session cookie.
// The first time, the player chooses a player name, which is bound to the
// wallet for good. The game password for that name is derived here from a
// secret (OV_AUTH_SECRET), so only this service can give it out: the player
// never sees or types one.
//
// The game server reads two files this service writes (OV_DATA_DIR, mounted
// into the luanti container at /world/orthoverse_auth):
//   registry.json  player names and their wallets (who may join, and as whom)
//   owners.json    which player's wallet holds each land's token, from the
//                  Orthoverse contract on Ethereum mainnet, refreshed every few
//                  minutes
//
// Guests need none of this: the play page makes up a Guest-XXXXXX name and
// password and keeps them in the browser.

'use strict';

import http from 'node:http';
import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { readFileSync, writeFileSync, renameSync, existsSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { verifyMessage, getAddress, isAddress, Interface } from 'ethers';
import { createMetadata } from './metadata.js';

// ---------------------------------------------------------------------------
// Settings

const env = process.env;
const HOST = env.OV_AUTH_HOST || '0.0.0.0';
const PORT = parseInt(env.OV_AUTH_PORT || '8090', 10);
const SECRET = env.OV_AUTH_SECRET || '';
const DATA_DIR = env.OV_DATA_DIR || '/data';
const AUTH_DB = env.OV_AUTH_DB || '/world/auth.sqlite';
const LANDS_FILE = env.OV_LANDS || '/app/lands.json';
const RPC_URL = env.OV_ETH_RPC || 'https://ethereum-rpc.publicnode.com';
// The endpoint's host only: keyed endpoints (Alchemy, Infura) carry the API
// key in the path, which must not reach logs or the public status page
const RPC_SHOWN = (() => { try { return new URL(RPC_URL).host; } catch (e) { return '(endpoint)'; } })();
const CONTRACT = (env.OV_CONTRACT || '0x118aeD2606D02C2545C6D7D2d1021e567cc08922').toLowerCase();
const CHAIN_TOKENS = env.OV_CHAIN_TOKENS || '/chain/tokens.json';
const CHAIN_NEW_LANDS = env.OV_CHAIN_NEW_LANDS || '/chain/new-lands.json';
// Where the site is, for the links in the token metadata
const PUBLIC_URL = env.OV_PUBLIC_URL || 'https://orthoverse.land';
// The crests (web/heraldry, /app/heraldry in the image)
const HERALDRY = env.OV_HERALDRY || fileURLToPath(new URL(
	existsSync(new URL('./heraldry', import.meta.url)) ? './heraldry/' : '../heraldry/', import.meta.url));
const OWNERS_EVERY_MS = parseFloat(env.OV_OWNERS_EVERY_MIN || '10') * 60 * 1000;
const CHAIN_ID = 1;

const SESSION_DAYS = 30;
const NONCE_TTL_MS = 10 * 60 * 1000;
const MAX_NONCES = 5000;
const PAIRS_PER_CALL = 400;     // wallet-and-land pairs per balanceOfBatch call
const CALLS_PER_BATCH = 1;      // eth_calls per JSON-RPC request (keyed endpoints limit calls a second)

if (SECRET.length < 32) {
	console.error('OV_AUTH_SECRET must be set to at least 32 characters (openssl rand -hex 32)');
	process.exit(1);
}

function log(...args) {
	console.log(new Date().toISOString(), ...args);
}

// ---------------------------------------------------------------------------
// Small helpers

function hmac(text) {
	return createHmac('sha256', SECRET).update(text).digest();
}

function b64url(buf) {
	return Buffer.from(buf).toString('base64url');
}

function writeJsonAtomic(path, value) {
	const tmp = path + '.tmp';
	writeFileSync(tmp, JSON.stringify(value, null, 1));
	renameSync(tmp, path);
}

function readJson(path, fallback) {
	try {
		return JSON.parse(readFileSync(path, 'utf8'));
	} catch (e) {
		return fallback;
	}
}

// The game password for a wallet player's name. Only this service knows the
// secret, so only it can hand out the password, and only to that wallet.
function gamePassword(name) {
	return hmac('orthoverse-player\n' + name.toLowerCase()).toString('hex').slice(0, 32);
}

// ---------------------------------------------------------------------------
// Player names (registry.json)

const NAME_RE = /^[A-Za-z0-9_-]{3,19}$/;
const GUEST_RE = /^guest/i;

mkdirSync(DATA_DIR, { recursive: true });
const REGISTRY_FILE = join(DATA_DIR, 'registry.json');
const OWNERS_FILE = join(DATA_DIR, 'owners.json');

const registry = readJson(REGISTRY_FILE, { version: 1, players: {} });
const nameOfAddress = new Map();   // lower-case address -> name
for (const p of Object.values(registry.players)) {
	nameOfAddress.set(p.address.toLowerCase(), p.name);
}

function saveRegistry() {
	writeJsonAtomic(REGISTRY_FILE, registry);
}

// Whether the game already has an account with this name (any capitals)
function accountExists(name) {
	if (!existsSync(AUTH_DB)) return false;
	let db;
	try {
		db = new DatabaseSync(AUTH_DB, { readOnly: true });
		const row = db.prepare('SELECT name FROM auth WHERE lower(name) = lower(?) LIMIT 1').get(name);
		return !!row;
	} catch (e) {
		log('auth.sqlite read failed:', e.message);
		return false;
	} finally {
		try { db && db.close(); } catch (e) { /* closed */ }
	}
}

function accountExistsExact(name) {
	if (!existsSync(AUTH_DB)) return false;
	let db;
	try {
		db = new DatabaseSync(AUTH_DB, { readOnly: true });
		return !!db.prepare('SELECT name FROM auth WHERE name = ? LIMIT 1').get(name);
	} catch (e) {
		log('auth.sqlite read failed:', e.message);
		return false;
	} finally {
		try { db && db.close(); } catch (e) { /* closed */ }
	}
}

// ---------------------------------------------------------------------------
// Lands and their owners (owners.json)

const lands = (() => {
	const data = readJson(LANDS_FILE, null);
	if (!data || !data.lands) {
		console.error('Cannot read the lands file ' + LANDS_FILE);
		process.exit(1);
	}
	const list = [];
	for (const [key, land] of Object.entries(data.lands)) {
		if (land.token && /^0x[0-9a-fA-F]{1,64}$/.test(land.token)) {
			const snap = /^0x[0-9a-fA-F]{40}$/.test(land.owner_snapshot || '') ? land.owner_snapshot.toLowerCase() : null;
			list.push({ key, name: land.name, token: land.token.toLowerCase(), snapshot: snap });
		}
	}
	return list;
})();

// Lands placed since for new tokens (the chain service's new-lands.json):
// added to the list, never removed or moved
const landKeys = new Set(lands.map(l => l.key));
function addNewLands() {
	const data = readJson(CHAIN_NEW_LANDS, null);
	if (!data || !data.lands) return 0;
	let n = 0;
	for (const [key, land] of Object.entries(data.lands)) {
		if (landKeys.has(key) || !land || !/^0x[0-9a-fA-F]{40,64}$/.test(land.token || '')) continue;
		const snap = /^0x[0-9a-fA-F]{40}$/.test(land.owner_snapshot || '') ? land.owner_snapshot.toLowerCase() : null;
		lands.push({ key, name: String(land.name || key), token: land.token.toLowerCase(), snapshot: snap });
		landKeys.add(key);
		n++;
	}
	if (n) log(`${n} new lands added`);
	return n;
}
addNewLands();

// Castle levels read from the contract just after a holder upgraded or flipped
// a land on the lands page (POST /api/levels/check), so the game remakes it
// within a minute rather than after the chain service's next daily run. The
// game takes these over land-levels.json when they were checked later.
const LEVELS_FILE = join(DATA_DIR, 'levels.json');
const freshLevels = readJson(LEVELS_FILE, { format: 1, levels: {} });
const levelChecked = new Map();   // key -> time of the last check (ms)

let owners = readJson(OWNERS_FILE, null);   // { updated, contract, owners: {token: holder|null} }
let ownersError = null;

// The Orthoverse contract is an ERC-1155 with one token per land, whose ID is
// the address that revealed it. ERC-1155 cannot say who holds a token, only
// whether a given wallet does (balanceOf, here always 0 or 1). So for every
// land we ask about the wallets that matter: every signed-up player's wallet,
// and the land's known holder: from the daily chain index (chain.js,
// tokens.json) when there is one, otherwise the owner in the April 2023
// snapshot. That also shows at a glance that the contract and token IDs are
// right. A land held by anyone else is recorded as null.
const erc1155 = new Interface([
	'function balanceOfBatch(address[] accounts, uint256[] ids) view returns (uint256[])',
	'function supportsInterface(bytes4 interfaceId) view returns (bool)',
	'function castleLevel(uint256 tokenId) view returns (uint256)',
]);

async function rpcBatch(calls) {
	const body = calls.map((c, i) => ({ jsonrpc: '2.0', id: i, method: 'eth_call', params: [c, 'latest'] }));
	const res = await fetch(RPC_URL, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body),
		signal: AbortSignal.timeout(30000),
	});
	if (!res.ok) {
		let why = '';
		try { why = (await res.text()).replace(/\s+/g, ' ').trim().slice(0, 200); } catch (e) { /* none */ }
		throw new Error('RPC HTTP ' + res.status + ' ' + why);
	}
	const out = await res.json();
	if (!Array.isArray(out)) throw new Error('RPC answered a batch with ' + JSON.stringify(out).slice(0, 200));
	const byId = new Map(out.map(r => [r.id, r]));
	return calls.map((c, i) => {
		const a = byId.get(i);
		if (!a || a.error || typeof a.result !== 'string') {
			throw new Error('RPC call failed: ' + JSON.stringify(a && (a.error || a)).slice(0, 200));
		}
		return a.result;
	});
}

// Balances for a list of [wallet, token] pairs, in order
async function balances(pairs) {
	const calls = [];
	for (let i = 0; i < pairs.length; i += PAIRS_PER_CALL) {
		const chunk = pairs.slice(i, i + PAIRS_PER_CALL);
		calls.push({
			to: CONTRACT,
			data: erc1155.encodeFunctionData('balanceOfBatch', [chunk.map(p => p[0]), chunk.map(p => BigInt(p[1]))]),
		});
	}
	const out = [];
	for (let i = 0; i < calls.length; i += CALLS_PER_BATCH) {
		const results = await rpcBatch(calls.slice(i, i + CALLS_PER_BATCH));
		for (const r of results) {
			for (const b of erc1155.decodeFunctionResult('balanceOfBatch', r)[0]) out.push(b > 0n);
		}
		await new Promise(r => setTimeout(r, 250));
	}
	return out;
}

// Wallets whose lands we look up: players, and anyone signed in since start-up
// who has not chosen a name yet
const watched = new Set(Object.values(registry.players).map(p => p.address.toLowerCase()));

// The holder of each token according to the daily chain index, if it has run
function indexedHolders() {
	const data = readJson(CHAIN_TOKENS, null);
	if (!data || !data.tokens) return { holders: null, block: null };
	const holders = new Map();
	for (const [id, t] of Object.entries(data.tokens)) {
		if (t && typeof t.holder === 'string') holders.set(id.toLowerCase(), t.holder.toLowerCase());
	}
	return { holders, block: data.block };
}

async function refreshOwners() {
	addNewLands();
	const wallets = [...watched];
	const index = indexedHolders();
	const known = l => (index.holders ? index.holders.get(l.token) : l.snapshot) || null;
	const pairs = [];
	for (const l of lands) {
		if (known(l)) pairs.push([known(l), l.token]);
		for (const w of wallets) pairs.push([w, l.token]);
	}
	const held = await balances(pairs);
	const result = {};
	let k = 0, byPlayers = 0, byKnown = 0;
	for (const l of lands) {
		let holder = null;
		if (known(l) && held[k++]) { holder = known(l); byKnown++; }
		for (const w of wallets) if (held[k++]) holder = w;
		if (holder && watched.has(holder)) byPlayers++;
		result[l.token] = holder;
	}
	owners = { updated: new Date().toISOString(), contract: CONTRACT, owners: result };
	writeJsonAtomic(OWNERS_FILE, owners);
	ownersError = null;
	const source = index.holders ? `the chain index (block ${index.block})` : 'the 2023 snapshot';
	log(`owners updated: ${byPlayers} lands held by ${wallets.length} player wallets; ` +
		`${byKnown} of ${lands.length} held as ${source} says, from ${RPC_SHOWN}`);
	if (byKnown === 0 && lands.length > 100) {
		log('warning: no land is held by its known holder: is OV_CONTRACT the Orthoverse contract?');
	}
}

// One wallet's lands, looked up at once (on signing in), so a new player need
// not wait for the next full refresh
async function refreshWallet(address) {
	if (!owners) return;
	const held = await balances(lands.map(l => [address, l.token]));
	lands.forEach((l, i) => {
		if (held[i]) owners.owners[l.token] = address;
		else if (owners.owners[l.token] === address) owners.owners[l.token] = null;
	});
	writeJsonAtomic(OWNERS_FILE, owners);
}

// One lookup at a time
let queue = Promise.resolve();
function serial(fn) {
	const p = queue.then(fn);
	queue = p.catch(() => {});
	return p;
}

async function ownersLoop() {
	try {
		await serial(refreshOwners);
		setTimeout(ownersLoop, OWNERS_EVERY_MS);
	} catch (e) {
		ownersError = e.message;
		log('owners refresh failed (keeping the last good list):', e.message);
		setTimeout(ownersLoop, Math.min(OWNERS_EVERY_MS, 60 * 1000));
	}
}

async function checkContract() {
	try {
		const [r] = await rpcBatch([{ to: CONTRACT, data: erc1155.encodeFunctionData('supportsInterface', ['0xd9b67a26']) }]);
		const yes = erc1155.decodeFunctionResult('supportsInterface', r)[0];
		log(`contract ${CONTRACT} ${yes ? 'is' : 'says it is NOT'} an ERC-1155`);
	} catch (e) {
		log('could not ask the contract what it is:', e.message);
	}
}

function landsOf(address) {
	if (!owners) return [];
	const a = address.toLowerCase();
	return lands.filter(l => owners.owners[l.token] === a).map(l => ({ key: l.key, name: l.name, token: l.token }));
}

// ---------------------------------------------------------------------------
// Sign-in messages and sessions

const nonces = new Map();   // nonce -> { message, address, expires }

setInterval(() => {
	const now = Date.now();
	for (const [n, v] of nonces) if (v.expires < now) nonces.delete(n);
}, 60 * 1000).unref();

function siweMessage(domain, origin, address, nonce, issued, expires) {
	return `${domain} wants you to sign in with your Ethereum account:
${address}

Sign in to the Orthoverse. This only proves that you control this wallet: it costs nothing and allows nothing else.

URI: ${origin}
Version: 1
Chain ID: ${CHAIN_ID}
Nonce: ${nonce}
Issued At: ${issued}
Expiration Time: ${expires}`;
}

function makeSession(address) {
	const payload = b64url(JSON.stringify({ a: address.toLowerCase(), e: Date.now() + SESSION_DAYS * 86400 * 1000 }));
	return payload + '.' + b64url(hmac('session\n' + payload));
}

function readSession(req) {
	const cookie = req.headers.cookie || '';
	const m = cookie.match(/(?:^|;\s*)ov_session=([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)/);
	if (!m) return null;
	const want = hmac('session\n' + m[1]);
	const got = Buffer.from(m[2], 'base64url');
	if (got.length !== want.length || !timingSafeEqual(got, want)) return null;
	try {
		const s = JSON.parse(Buffer.from(m[1], 'base64url').toString('utf8'));
		if (!s.a || !s.e || s.e < Date.now()) return null;
		return s.a;
	} catch (e) {
		return null;
	}
}

function sessionCookie(req, value, maxAgeSeconds) {
	const https = (req.headers['x-forwarded-proto'] || '').split(',')[0].trim() === 'https';
	return `ov_session=${value}; Path=/auth; HttpOnly; SameSite=Strict; Max-Age=${maxAgeSeconds}` +
		(https ? '; Secure' : '');
}

// ---------------------------------------------------------------------------
// Rate limiting, per client address

const hits = new Map();
function clientIp(req) {
	return String(req.headers['cf-connecting-ip'] ||
		(req.headers['x-forwarded-for'] || '').split(',')[0] || req.socket.remoteAddress || '?').trim();
}
function limited(req, max = 30) {
	const ip = clientIp(req);
	const now = Date.now();
	const h = hits.get(ip) || { n: 0, reset: now + 60000 };
	if (now > h.reset) { h.n = 0; h.reset = now + 60000; }
	h.n++;
	hits.set(ip, h);
	return h.n > max;
}
setInterval(() => {
	const now = Date.now();
	for (const [ip, h] of hits) if (now > h.reset) hits.delete(ip);
}, 60 * 1000).unref();

// ---------------------------------------------------------------------------
// HTTP

function send(res, status, body, headers = {}) {
	res.writeHead(status, {
		'content-type': 'application/json; charset=utf-8',
		'cache-control': 'no-store',
		...headers,
	});
	res.end(JSON.stringify(body));
}

function readBody(req) {
	return new Promise((resolve, reject) => {
		if (!(req.headers['content-type'] || '').startsWith('application/json')) {
			return reject(new Error('expected JSON'));
		}
		let size = 0;
		const parts = [];
		req.on('data', c => {
			size += c.length;
			if (size > 8192) { reject(new Error('too large')); req.destroy(); return; }
			parts.push(c);
		});
		req.on('end', () => {
			try { resolve(JSON.parse(Buffer.concat(parts).toString('utf8') || '{}')); }
			catch (e) { reject(new Error('bad JSON')); }
		});
		req.on('error', reject);
	});
}

function me(address) {
	const name = nameOfAddress.get(address) || null;
	return {
		signedIn: true,
		address: getAddress(address),
		name,
		password: name ? gamePassword(name) : null,
		exists: name ? accountExistsExact(name) : false,
		lands: landsOf(address),
		ownersUpdated: owners ? owners.updated : null,
	};
}

const routes = {
	// A sign-in message for this address, to be signed by the wallet
	'GET /auth/nonce': async (req, res, url) => {
		if (limited(req)) return send(res, 429, { error: 'Too many requests; wait a minute.' });
		const address = url.searchParams.get('address') || '';
		if (!isAddress(address)) return send(res, 400, { error: 'That is not an Ethereum address.' });
		const host = String(req.headers.host || '').toLowerCase();
		if (!/^[a-z0-9.-]+(:\d+)?$/.test(host)) return send(res, 400, { error: 'Unexpected host.' });
		const proto = (req.headers['x-forwarded-proto'] || 'http').split(',')[0].trim() === 'https' ? 'https' : 'http';
		const nonce = randomBytes(12).toString('hex');
		const now = Date.now();
		const message = siweMessage(host, `${proto}://${host}`, getAddress(address), nonce,
			new Date(now).toISOString(), new Date(now + NONCE_TTL_MS).toISOString());
		if (nonces.size >= MAX_NONCES) nonces.delete(nonces.keys().next().value);
		nonces.set(nonce, { message, address: address.toLowerCase(), expires: now + NONCE_TTL_MS });
		send(res, 200, { nonce, message });
	},

	// The signed message: check it and start a session
	'POST /auth/verify': async (req, res) => {
		if (limited(req)) return send(res, 429, { error: 'Too many requests; wait a minute.' });
		const body = await readBody(req);
		const entry = nonces.get(String(body.nonce || ''));
		if (!entry || entry.expires < Date.now()) {
			return send(res, 400, { error: 'The sign-in request has expired. Please try again.' });
		}
		nonces.delete(String(body.nonce));
		let signer;
		try {
			signer = verifyMessage(entry.message, String(body.signature || ''));
		} catch (e) {
			return send(res, 400, { error: 'The signature could not be read.' });
		}
		if (signer.toLowerCase() !== entry.address) {
			return send(res, 400, { error: 'The signature is not from the wallet that asked to sign in.' });
		}
		log('signed in', signer, nameOfAddress.get(entry.address) || '(no name yet)');
		if (!watched.has(entry.address)) {
			watched.add(entry.address);
			try {
				await serial(() => refreshWallet(entry.address));
			} catch (e) {
				log('lands of', signer, 'not looked up yet:', e.message);
			}
		}
		send(res, 200, me(entry.address), {
			'set-cookie': sessionCookie(req, makeSession(entry.address), SESSION_DAYS * 86400),
		});
	},

	'GET /auth/me': async (req, res) => {
		const address = readSession(req);
		if (!address) return send(res, 200, { signedIn: false });
		send(res, 200, me(address));
	},

	// Choose the player name for this wallet (once)
	'POST /auth/name': async (req, res) => {
		if (limited(req)) return send(res, 429, { error: 'Too many requests; wait a minute.' });
		const address = readSession(req);
		if (!address) return send(res, 401, { error: 'Sign in with your wallet first.' });
		if (nameOfAddress.has(address)) {
			return send(res, 400, { error: 'This wallet already has the player name ' + nameOfAddress.get(address) + '.' });
		}
		const body = await readBody(req);
		const name = String(body.name || '').trim();
		if (!NAME_RE.test(name)) {
			return send(res, 400, { error: 'Names are 3 to 19 letters, digits, - and _, with no spaces.' });
		}
		if (GUEST_RE.test(name)) {
			return send(res, 400, { error: 'Names starting with "Guest" are kept for guests.' });
		}
		if (registry.players[name.toLowerCase()] || accountExists(name)) {
			return send(res, 400, { error: 'That name is taken (perhaps with different capitals). Choose another.' });
		}
		registry.players[name.toLowerCase()] = { name, address, since: new Date().toISOString() };
		nameOfAddress.set(address, name);
		saveRegistry();
		log('name', name, 'for', address);
		send(res, 200, me(address));
	},

	'POST /auth/logout': async (req, res) => {
		send(res, 200, { signedIn: false }, { 'set-cookie': sessionCookie(req, '', 0) });
	},

	// Whether a game account exists (the page uses it for guests: log in or register)
	// Read one land's castle level from the contract now (after an upgrade or
	// a flip) and hand it to the game. Anyone may ask; one look per land every
	// 15 seconds.
	'POST /api/levels/check': async (req, res) => {
		if (limited(req, 20)) return send(res, 429, { error: 'Too many requests; wait a minute.' });
		let body;
		try { body = await readBody(req); } catch (e) { return send(res, 400, { error: 'Send JSON.' }); }
		const land = lands.find(l => l.key === String(body && body.key));
		if (!land) return send(res, 404, { error: 'No such land.' });
		const last = levelChecked.get(land.key) || 0;
		if (Date.now() - last < 15000 && freshLevels.levels[land.key]) {
			return send(res, 200, { key: land.key, level: freshLevels.levels[land.key].level, cached: true });
		}
		levelChecked.set(land.key, Date.now());
		const [r] = await rpcBatch([{ to: CONTRACT, data: erc1155.encodeFunctionData('castleLevel', [BigInt(land.token)]) }]);
		const level = Number(erc1155.decodeFunctionResult('castleLevel', r)[0]);
		if (!(level >= 0 && level < 16)) return send(res, 502, { error: 'The contract gave an unexpected level.' });
		freshLevels.levels[land.key] = { level, checked: new Date().toISOString() };
		writeJsonAtomic(LEVELS_FILE, freshLevels);
		log(`level of ${land.name} (${land.key}) read from the contract: ${level}`);
		return send(res, 200, { key: land.key, level });
	},

	'GET /auth/exists': async (req, res, url) => {
		if (limited(req, 60)) return send(res, 429, { error: 'Too many requests; wait a minute.' });
		const name = url.searchParams.get('name') || '';
		if (!/^[A-Za-z0-9_-]{1,19}$/.test(name)) return send(res, 400, { error: 'Not a player name.' });
		send(res, 200, { exists: accountExistsExact(name) });
	},

	// For the operator: is ownership data current?
	'GET /auth/status': async (req, res) => {
		send(res, 200, {
			players: Object.keys(registry.players).length,
			lands: lands.length,
			ownersUpdated: owners ? owners.updated : null,
			ownersError,
			rpc: RPC_SHOWN,
			contract: CONTRACT,
		});
	},
};

// ---------------------------------------------------------------------------
// Token metadata (/api/metadata/), and the contract's owner, who receives the
// royalties (royaltyInfo: owner(), 2.5%)

let contractOwner = null;
async function readContractOwner() {
	try {
		const [r] = await rpcBatch([{ to: CONTRACT, data: '0x8da5cb5b' }]);   // owner()
		contractOwner = getAddress('0x' + r.slice(26));
	} catch (e) {
		log('could not read the contract owner:', e.message);
	}
}

const metadata = createMetadata({
	landsFile: LANDS_FILE,
	newLandsFile: CHAIN_NEW_LANDS,
	tokensFile: CHAIN_TOKENS,
	cardsIndex: join(env.OV_MAP_DIR || '/map', 'cards', 'index.json'),
	heraldryDir: HERALDRY,
	publicUrl: PUBLIC_URL,
	royaltyRecipient: () => contractOwner,
});

const server = http.createServer(async (req, res) => {
	const url = new URL(req.url, 'http://x');
	try {
		if (metadata(req, res, url)) return;
	} catch (e) {
		log('error', req.method, url.pathname, e.message);
		if (!res.headersSent) send(res, 500, { error: 'The request could not be handled.' });
		return;
	}
	const route = routes[`${req.method} ${url.pathname}`];
	if (!route) return send(res, 404, { error: 'Not found' });
	try {
		await route(req, res, url);
	} catch (e) {
		log('error', req.method, url.pathname, e.message);
		if (!res.headersSent) send(res, 400, { error: 'The request could not be handled.' });
	}
});

server.listen(PORT, HOST, () => {
	log(`Orthoverse auth on http://${HOST}:${PORT}: ${lands.length} lands, ` +
		`${Object.keys(registry.players).length} players, contract ${CONTRACT} via ${RPC_SHOWN}`);
	checkContract().then(ownersLoop);
	readContractOwner();
	setInterval(readContractOwner, 6 * 3600 * 1000).unref();
});

for (const sig of ['SIGINT', 'SIGTERM']) {
	process.on(sig, () => { server.close(); process.exit(0); });
}
