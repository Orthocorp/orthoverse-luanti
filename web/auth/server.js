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
// Players without a wallet can make a character with a name and password
// here instead (and link a wallet to it later, or add a password to a wallet
// character). The password is checked here, never by the game: the game
// password stays the derived one, so the game needs no change. A recovery
// code, shown once, lets a player who forgets their password set a new one.
//
// Guests need none of this: the play page makes up a Guest-XXXXXX name and
// password and keeps them in the browser.

'use strict';

import http from 'node:http';
import { createHmac, createHash, randomBytes, timingSafeEqual, scrypt } from 'node:crypto';
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

// Cloudflare Turnstile on the registration form (both empty: no check)
const TURNSTILE_SITEKEY = env.OV_TURNSTILE_SITEKEY || '';
const TURNSTILE_SECRET = env.OV_TURNSTILE_SECRET || '';
const TURNSTILE_URL = env.OV_TURNSTILE_URL || 'https://challenges.cloudflare.com/turnstile/v0/siteverify';
// New password characters per client address per day
const REGISTER_PER_DAY = parseInt(env.OV_REGISTER_PER_DAY || '3', 10);

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

// players: lower-case name -> { name, since, address (wallet characters, or a
// wallet linked later), pw: { s, h, v } (a password: salt, scrypt hash,
// version; the version is in the session, so changing the password ends
// other sessions), rc: { s, h } (the recovery code, the same way) }
const registry = readJson(REGISTRY_FILE, { version: 1, players: {} });
const nameOfAddress = new Map();   // lower-case address -> name
for (const p of Object.values(registry.players)) {
	if (p.address) nameOfAddress.set(p.address.toLowerCase(), p.name);
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
			list.push({ key, name: land.name, token: land.token.toLowerCase(), snapshot: snap, level: Number(land.level) || 0 });
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
		lands.push({ key, name: String(land.name || key), token: land.token.toLowerCase(), snapshot: snap, level: Number(land.level) || 0 });
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
let lastIndexRequest = 0;

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
	'function revealedTokenIds(uint256 tokenId) view returns (bool)',
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
const watched = new Set(Object.values(registry.players).filter(p => p.address).map(p => p.address.toLowerCase()));

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

// A session is either a wallet's (a: address) or a password character's (n:
// lower-case name, v: password version)
function makeSession(who) {
	const s = typeof who === 'string' ? { a: who.toLowerCase() } : who;
	const payload = b64url(JSON.stringify({ ...s, e: Date.now() + SESSION_DAYS * 86400 * 1000 }));
	return payload + '.' + b64url(hmac('session\n' + payload));
}

function passwordSession(entry) {
	return makeSession({ n: entry.name.toLowerCase(), v: entry.pw.v });
}

// Who is signed in: { address (lower case, or null), name (or null), entry
// (their registry entry, or null), wallet (signed in with the wallet) }, or null
function readSession(req) {
	const cookie = req.headers.cookie || '';
	const m = cookie.match(/(?:^|;\s*)ov_session=([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)/);
	if (!m) return null;
	const want = hmac('session\n' + m[1]);
	const got = Buffer.from(m[2], 'base64url');
	if (got.length !== want.length || !timingSafeEqual(got, want)) return null;
	let s;
	try {
		s = JSON.parse(Buffer.from(m[1], 'base64url').toString('utf8'));
	} catch (e) {
		return null;
	}
	if (!s.e || s.e < Date.now()) return null;
	if (s.a) {
		const name = nameOfAddress.get(s.a) || null;
		return { address: s.a, name, entry: name ? registry.players[name.toLowerCase()] : null, wallet: true };
	}
	if (s.n) {
		const entry = registry.players[s.n];
		if (!entry || !entry.pw || entry.pw.v !== s.v) return null;   // password changed since
		return { address: entry.address ? entry.address.toLowerCase() : null, name: entry.name, entry, wallet: false };
	}
	return null;
}

// The session view of a password character (as readSession would give it)
function readSessionOf(entry) {
	return { address: entry.address ? entry.address.toLowerCase() : null, name: entry.name, entry, wallet: false };
}

// ---------------------------------------------------------------------------
// Passwords and recovery codes

function scryptHash(secret, salt) {
	return new Promise((resolve, reject) =>
		scrypt(secret, salt, 32, { N: 16384, r: 8, p: 1 }, (e, key) => e ? reject(e) : resolve(key)));
}

async function makeHash(secret) {
	const salt = randomBytes(16);
	return { s: salt.toString('base64'), h: (await scryptHash(secret, salt)).toString('base64') };
}

async function hashMatches(secret, stored) {
	if (!stored || !stored.s || !stored.h) return false;
	const got = await scryptHash(secret, Buffer.from(stored.s, 'base64'));
	const want = Buffer.from(stored.h, 'base64');
	return got.length === want.length && timingSafeEqual(got, want);
}

// A recovery code: 16 letters and digits in groups of four (no 0/O, 1/I)
function makeRecoveryCode() {
	const abc = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
	const bytes = randomBytes(16);
	let code = '';
	for (let i = 0; i < 16; i++) code += abc[bytes[i] % abc.length] + (i % 4 === 3 && i < 15 ? '-' : '');
	return code;
}
const normalCode = c => String(c || '').toUpperCase().replace(/[^A-Z0-9]/g, '');

function passwordProblem(password, name) {
	if (typeof password !== 'string' || password.length < 8) return 'Passwords are at least 8 characters.';
	if (password.length > 128) return 'Passwords are at most 128 characters.';
	if (name && password.toLowerCase() === name.toLowerCase()) return 'The password cannot be the player name.';
	return null;
}

function nameProblem(name) {
	if (!NAME_RE.test(name)) return 'Names are 3 to 19 letters, digits, - and _, with no spaces.';
	if (GUEST_RE.test(name)) return 'Names starting with "Guest" are kept for guests.';
	if (registry.players[name.toLowerCase()] || accountExists(name)) {
		return 'That name is taken (perhaps with different capitals). Choose another.';
	}
	return null;
}

// Failed sign-ins per name: after 10 within 15 minutes, that name rests for 15
const failedLogins = new Map();   // lower-case name -> { n, until }
function loginBlocked(name) {
	const f = failedLogins.get(name);
	return f && f.n >= 10 && Date.now() < f.until;
}
function loginFailed(name) {
	const now = Date.now();
	const f = failedLogins.get(name);
	if (!f || now > f.until) failedLogins.set(name, { n: 1, until: now + 15 * 60000 });
	else f.n++;
}

// New characters per client address per day
const registrations = new Map();   // ip -> { n, reset }
function registrationAllowed(req) {
	const ip = clientIp(req);
	const now = Date.now();
	const r = registrations.get(ip);
	if (!r || now > r.reset) { registrations.set(ip, { n: 1, reset: now + 86400000 }); return true; }
	if (r.n >= REGISTER_PER_DAY) return false;
	r.n++;
	return true;
}

async function turnstileOk(req, token) {
	if (!TURNSTILE_SECRET) return true;
	if (!token) return false;
	try {
		const form = new URLSearchParams({ secret: TURNSTILE_SECRET, response: String(token), remoteip: clientIp(req) });
		const r = await fetch(TURNSTILE_URL, { method: 'POST', body: form, signal: AbortSignal.timeout(8000) });
		const j = await r.json();
		return j.success === true;
	} catch (e) {
		log('Turnstile check failed:', e.message);
		return false;
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
// Requests per minute from one address (OV_AUTH_RATE, for tests)
const RATE = parseInt(env.OV_AUTH_RATE || '30', 10);
function limited(req, max = RATE) {
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

// A land's castle level now: read from the contract after an upgrade on the
// lands page, else the chain index, else lands.json
function levelOf(land) {
	const fresh = freshLevels.levels[land.key];
	if (fresh) return fresh.level;
	const data = readJson(CHAIN_TOKENS, null);
	const t = data && data.tokens && data.tokens[land.token];
	return t && Number.isInteger(t.level) ? t.level : land.level;
}

// Who may arrive at any spot clicked on the map: the admin, and holders of a
// land at castle level 7 (either realm). The game checks again on arrival.
const ADMIN = String(env.OV_ADMIN || '');
function mayVisit(address, name) {
	if (ADMIN && name === ADMIN) return true;
	if (!owners || !address) return false;
	const a = address.toLowerCase();
	return lands.some(l => owners.owners[l.token] === a && levelOf(l) % 8 === 7);
}

// Where players asked to arrive (from the map), read by the game when they join
const VISITS_FILE = join(DATA_DIR, 'visits.json');
const visits = readJson(VISITS_FILE, { format: 1, visits: {} });

// What the pages are told about whoever is signed in (a wallet address, or a
// session from readSession)
function me(who) {
	const sess = typeof who === 'string'
		? { address: who, name: nameOfAddress.get(who) || null, wallet: true }
		: who;
	const name = sess.name || null;
	const entry = name ? registry.players[name.toLowerCase()] : null;
	const address = sess.address || null;
	return {
		signedIn: true,
		address: address ? getAddress(address) : null,
		name,
		password: name ? gamePassword(name) : null,
		exists: name ? accountExistsExact(name) : false,
		lands: address ? landsOf(address) : [],
		canVisit: name ? mayVisit(address, name) : false,
		hasPassword: !!(entry && entry.pw),
		hasWallet: !!address,
		signedInWith: sess.wallet ? 'wallet' : 'password',
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
		const sess = readSession(req);
		if (!sess) return send(res, 200, { signedIn: false });
		send(res, 200, me(sess));
	},

	// Settings the pages need (the Turnstile site key, if registration uses it)
	'GET /auth/config': async (req, res) => {
		send(res, 200, { turnstile: TURNSTILE_SITEKEY || null });
	},

	// A new character with a name and password (no wallet)
	'POST /auth/register': async (req, res) => {
		if (limited(req)) return send(res, 429, { error: 'Too many requests; wait a minute.' });
		const body = await readBody(req);
		const name = String(body.name || '').trim();
		const problem = nameProblem(name) || passwordProblem(body.password, name);
		if (problem) return send(res, 400, { error: problem });
		if (!await turnstileOk(req, body.turnstile)) {
			return send(res, 400, { error: 'The check that you are not a robot did not pass. Please try again.' });
		}
		if (!registrationAllowed(req)) {
			return send(res, 429, { error: 'Too many new characters from here today. Try again tomorrow.' });
		}
		const code = makeRecoveryCode();
		const entry = {
			name, since: new Date().toISOString(),
			pw: { ...(await makeHash(body.password)), v: 1 },
			rc: await makeHash(normalCode(code)),
		};
		registry.players[name.toLowerCase()] = entry;
		saveRegistry();
		log('new password character', name);
		send(res, 200, { ...me({ address: null, name, wallet: false }), recoveryCode: code },
			{ 'set-cookie': sessionCookie(req, passwordSession(entry), SESSION_DAYS * 86400) });
	},

	// Sign in with a name and password
	'POST /auth/login': async (req, res) => {
		if (limited(req)) return send(res, 429, { error: 'Too many requests; wait a minute.' });
		const body = await readBody(req);
		const key = String(body.name || '').trim().toLowerCase();
		if (loginBlocked(key)) {
			return send(res, 429, { error: 'Too many wrong passwords for this name. Wait 15 minutes, or use your recovery code.' });
		}
		const entry = registry.players[key];
		if (entry && !entry.pw) {
			return send(res, 400, { error: 'This character signs in with its wallet. Add a password on the Account page to use one.' });
		}
		if (!entry || !await hashMatches(String(body.password || ''), entry.pw)) {
			loginFailed(key);
			return send(res, 400, { error: 'That name and password do not match.' });
		}
		failedLogins.delete(key);
		log('signed in with a password', entry.name);
		send(res, 200, me(readSessionOf(entry)),
			{ 'set-cookie': sessionCookie(req, passwordSession(entry), SESSION_DAYS * 86400) });
	},

	// Set or change the password (any signed-in character with a name). With a
	// password already, the current one is needed, unless signed in with the
	// wallet (which proves the character as well). The first time, a recovery
	// code is made and shown once.
	'POST /auth/password': async (req, res) => {
		if (limited(req)) return send(res, 429, { error: 'Too many requests; wait a minute.' });
		const sess = readSession(req);
		if (!sess) return send(res, 401, { error: 'Sign in first.' });
		if (!sess.entry) return send(res, 400, { error: 'Choose a player name first.' });
		const body = await readBody(req);
		const entry = sess.entry;
		if (entry.pw && !sess.wallet && !await hashMatches(String(body.current || ''), entry.pw)) {
			return send(res, 400, { error: 'The current password is not right.' });
		}
		const problem = passwordProblem(body.password, entry.name);
		if (problem) return send(res, 400, { error: problem });
		entry.pw = { ...(await makeHash(body.password)), v: (entry.pw ? entry.pw.v : 0) + 1 };
		let code = null;
		if (!entry.rc) {
			code = makeRecoveryCode();
			entry.rc = await makeHash(normalCode(code));
		}
		saveRegistry();
		log('password set for', entry.name);
		// A wallet session stays as it is; a password session is renewed (the
		// old one ended with the old password)
		const headers = sess.wallet ? {} : { 'set-cookie': sessionCookie(req, passwordSession(entry), SESSION_DAYS * 86400) };
		send(res, 200, { ...me(sess), recoveryCode: code }, headers);
	},

	// Forgotten password: the recovery code sets a new one (and is replaced)
	'POST /auth/recover': async (req, res) => {
		if (limited(req)) return send(res, 429, { error: 'Too many requests; wait a minute.' });
		const body = await readBody(req);
		const key = String(body.name || '').trim().toLowerCase();
		if (loginBlocked(key)) return send(res, 429, { error: 'Too many tries for this name. Wait 15 minutes.' });
		const entry = registry.players[key];
		if (!entry || !entry.rc || !await hashMatches(normalCode(body.code), entry.rc)) {
			loginFailed(key);
			return send(res, 400, { error: 'That name and recovery code do not match.' });
		}
		const problem = passwordProblem(body.password, entry.name);
		if (problem) return send(res, 400, { error: problem });
		failedLogins.delete(key);
		const code = makeRecoveryCode();
		entry.pw = { ...(await makeHash(body.password)), v: (entry.pw ? entry.pw.v : 0) + 1 };
		entry.rc = await makeHash(normalCode(code));
		saveRegistry();
		log('password recovered for', entry.name);
		send(res, 200, { ...me(readSessionOf(entry)), recoveryCode: code },
			{ 'set-cookie': sessionCookie(req, passwordSession(entry), SESSION_DAYS * 86400) });
	},

	// Link a wallet to a password character: a signed sign-in message (from
	// /auth/nonce), as for signing in
	'POST /auth/link': async (req, res) => {
		if (limited(req)) return send(res, 429, { error: 'Too many requests; wait a minute.' });
		const sess = readSession(req);
		if (!sess || !sess.entry) return send(res, 401, { error: 'Sign in with your name and password first.' });
		if (sess.address) return send(res, 400, { error: 'This character already has a wallet.' });
		const body = await readBody(req);
		const entry = nonces.get(String(body.nonce || ''));
		if (!entry || entry.expires < Date.now()) {
			return send(res, 400, { error: 'The request has expired. Please try again.' });
		}
		nonces.delete(String(body.nonce));
		let signer;
		try {
			signer = verifyMessage(entry.message, String(body.signature || ''));
		} catch (e) {
			return send(res, 400, { error: 'The signature could not be read.' });
		}
		if (signer.toLowerCase() !== entry.address) {
			return send(res, 400, { error: 'The signature is not from the wallet that asked.' });
		}
		const address = entry.address;
		if (nameOfAddress.has(address)) {
			return send(res, 400, { error: 'That wallet already belongs to the character ' + nameOfAddress.get(address) + '.' });
		}
		sess.entry.address = address;
		nameOfAddress.set(address, sess.entry.name);
		saveRegistry();
		log('wallet', signer, 'linked to', sess.entry.name);
		if (!watched.has(address)) {
			watched.add(address);
			try {
				await serial(() => refreshWallet(address));
			} catch (e) {
				log('lands of', signer, 'not looked up yet:', e.message);
			}
		}
		send(res, 200, me(readSession(req)));
	},

	// Choose the player name for this wallet (once)
	'POST /auth/name': async (req, res) => {
		if (limited(req)) return send(res, 429, { error: 'Too many requests; wait a minute.' });
		const sess = readSession(req);
		if (!sess || !sess.address) return send(res, 401, { error: 'Sign in with your wallet first.' });
		const address = sess.address;
		if (nameOfAddress.has(address)) {
			return send(res, 400, { error: 'This wallet already has the player name ' + nameOfAddress.get(address) + '.' });
		}
		const body = await readBody(req);
		const name = String(body.name || '').trim();
		const problem = nameProblem(name);
		if (problem) return send(res, 400, { error: problem });
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
		if (limited(req)) return send(res, 429, { error: 'Too many requests; wait a minute.' });
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

	// Just after a reveal (or a gift) on the lands page: check on the contract
	// that the address's token is revealed, and ask the chain service to index
	// now, so its land is placed within a minute
	'POST /api/reveal/check': async (req, res) => {
		if (limited(req)) return send(res, 429, { error: 'Too many requests; wait a minute.' });
		let body;
		try { body = await readBody(req); } catch (e) { return send(res, 400, { error: 'Send JSON.' }); }
		const address = String(body && body.address || '');
		if (!isAddress(address)) return send(res, 400, { error: 'That is not an Ethereum address.' });
		const [r] = await rpcBatch([{ to: CONTRACT, data: erc1155.encodeFunctionData('revealedTokenIds', [BigInt(address)]) }]);
		const revealed = erc1155.decodeFunctionResult('revealedTokenIds', r)[0];
		if (revealed && Date.now() - lastIndexRequest > 30000) {
			lastIndexRequest = Date.now();
			writeFileSync(join(DATA_DIR, 'index-now'), new Date().toISOString() + ' ' + address.toLowerCase() + '\n');
			log(`token ${address.toLowerCase()} revealed: asked the chain service to index now`);
		}
		return send(res, 200, { revealed });
	},

	// Whether the land of the token with this ID (an address) has been placed
	'GET /api/reveal/status': async (req, res, url) => {
		if (limited(req, 60)) return send(res, 429, { error: 'Too many requests; wait a minute.' });
		const address = url.searchParams.get('address') || '';
		if (!isAddress(address)) return send(res, 400, { error: 'That is not an Ethereum address.' });
		const token = address.toLowerCase();
		addNewLands();
		const land = lands.find(l => l.token === token || l.token === '0x' + token.slice(2).padStart(40, '0'));
		if (!land) return send(res, 200, { placed: null });
		// A token just revealed is held by the address it was revealed for:
		// checked on the contract and noted at once, so the game lets them
		// build without waiting for the next full refresh
		if (owners && owners.owners[land.token] !== token) {
			const [held] = await balances([[address, land.token]]);
			if (held) {
				owners.owners[land.token] = token;
				writeJsonAtomic(OWNERS_FILE, owners);
			}
		}
		return send(res, 200, { placed: { key: land.key, name: land.name } });
	},

	// Arrive at a spot on the map when you next join the game (the admin and
	// level 7 holders). Kept for 10 minutes; the game checks who may.
	'POST /auth/visit': async (req, res) => {
		if (limited(req)) return send(res, 429, { error: 'Too many requests; wait a minute.' });
		const sess = readSession(req);
		if (!sess) return send(res, 401, { error: 'Sign in first.' });
		const { address, name } = sess;
		if (!name) return send(res, 400, { error: 'Choose a player name first.' });
		if (!mayVisit(address, name)) {
			return send(res, 403, { error: 'Arriving anywhere is for holders of a level 7 land.' });
		}
		let body;
		try { body = await readBody(req); } catch (e) { return send(res, 400, { error: 'Send JSON.' }); }
		const x = Math.round(Number(body && body.x)), z = Math.round(Number(body && body.z));
		const EDGE = 58 * 96 + 47;
		if (!Number.isFinite(x) || !Number.isFinite(z) || Math.abs(x) > EDGE || Math.abs(z) > EDGE) {
			return send(res, 400, { error: 'That is outside the world.' });
		}
		visits.visits[name.toLowerCase()] = { name, x, z, at: new Date().toISOString(), t: Math.floor(Date.now() / 1000) };
		writeJsonAtomic(VISITS_FILE, visits);
		return send(res, 200, { name, x, z });
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
