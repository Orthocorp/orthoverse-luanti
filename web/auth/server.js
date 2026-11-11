// Orthoverse auth service: wallet sign-in, player names, and who owns which land.
//
// Players sign in on the play page with an Ethereum wallet: the page asks for a
// sign-in message (Sign-In with Ethereum, EIP-4361), the wallet signs it, and
// this service checks the signature and gives the browser a session cookie.
// The first time, the player chooses a player name, which is bound to the
// wallet for good. Each time the player enters the game, this service makes
// a fresh game password for that one entry (POST /auth/play), so only a
// signed-in player can get one, and the player never sees or types it.
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
import net from 'node:net';
import { createHmac, createHash, randomBytes, timingSafeEqual, scrypt } from 'node:crypto';
import { readFileSync, writeFileSync, renameSync, existsSync, mkdirSync, unlinkSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { verifyMessage, getAddress, isAddress, Interface } from 'ethers';
import { createMetadata } from './metadata.js';
import { createOpenSea } from './opensea.js';
import { srpVerifier } from './srp.js';
import { PNG } from 'pngjs';

// Skins: the designer's parts and painting, shared with the Account page
// (web/skin; /app/skin in the image)
const SKIN_DIR = fileURLToPath(new URL(
	existsSync(new URL('./skin', import.meta.url)) ? './skin/' : '../skin/', import.meta.url));
const skin = await import(join(SKIN_DIR, 'skin.js'));

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

// The adventures and their records, written by the game (orthoverse_adventure)
const ADVENTURES_FILE = env.OV_ADVENTURES || '/world/orthoverse_adventures/adventures.json';

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

function writeFileAtomic(path, data) {
	const tmp = path + '.tmp';
	writeFileSync(tmp, data);
	renameSync(tmp, path);
}

function readJson(path, fallback) {
	try {
		return JSON.parse(readFileSync(path, 'utf8'));
	} catch (e) {
		return fallback;
	}
}

// Game passwords: the game server checks a name and password of its own (the
// engine knows nothing of this site's sign-in). Each time a signed-in player
// enters the game (POST /auth/play), the character gets a fresh random game
// password, for that one entry: this service keeps only its record (srp) and
// when it was made (issued), and the game sets the account to it as the player
// joins, refuses it once used or ten minutes old, and nobody ever needs to know
// or keep it. A password that leaks is useless after the next entry.
function newGamePassword() {
	return randomBytes(16).toString('hex');
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

// A character by lower-case name (never an inherited property such as
// "__proto__" or "constructor")
function entryOf(key) {
	return Object.hasOwn(registry.players, key) ? registry.players[key] : undefined;
}

// Each character carries its game account's password record (srp), so the game
// makes the account with the right password before anyone else can join under
// the name (see srp.js). A new character's record is of a password nobody
// knows, until its first entry. Characters made before this get one now.
function withSrp(entry) {
	entry.srp = srpVerifier(entry.name, newGamePassword());
	delete entry.issued;
	return entry;
}
{
	let added = 0;
	for (const p of Object.values(registry.players)) {
		if (p && p.name && !p.srp) { withSrp(p); added++; }
	}
	if (added) { saveRegistry(); log(`game password records added for ${added} characters`); }
}

// The game's accounts, read only. The game keeps its databases in WAL mode
// (docker/luanti/entrypoint.sh), which a reader without write access can open
// only while the game has it open; when the game is stopped, nothing writes
// it, and it is opened as unchanging.
function openAuthDb() {
	let db;
	try {
		db = new DatabaseSync(AUTH_DB, { readOnly: true });
		db.prepare('SELECT 1 FROM sqlite_master LIMIT 1').all();   // (the opening happens here)
		return db;
	} catch (e) {
		try { db && db.close(); } catch (e2) { /* closed */ }
		if (existsSync(AUTH_DB + '-shm')) throw e;
		const url = pathToFileURL(AUTH_DB);
		url.searchParams.set('immutable', '1');
		return new DatabaseSync(url, { readOnly: true });
	}
}

// Whether the game already has an account with this name (any capitals)
function accountExists(name) {
	if (!existsSync(AUTH_DB)) return false;
	let db;
	try {
		db = openAuthDb();
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
		db = openAuthDb();
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
// within a minute rather than after the chain service's next hourly run. The
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
// and the land's known holder: from the hourly chain index (chain.js,
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

// The holder of each token according to the chain index (the chain service,
// hourly), if it has run, and when it was written
function indexedHolders() {
	const data = readJson(CHAIN_TOKENS, null);
	if (!data || !data.tokens) return { holders: null, block: null, at: 0 };
	const holders = new Map();
	for (const [id, t] of Object.entries(data.tokens)) {
		if (t && typeof t.holder === 'string') holders.set(id.toLowerCase(), t.holder.toLowerCase());
	}
	const at = Date.parse(data.updated || '') || 0;
	return { holders, block: data.block, at };
}

// Lands a player's wallet was found holding on signing in (refreshWallet),
// newer than the chain index: token -> { address, at }
const freshHolds = new Map();

// Who holds each land. The chain index (replaying every transfer, hourly)
// says who holds every land as of its block. Building rights rest only on the
// lands it says players' wallets hold, so only those are checked against the
// contract now, every OWNERS_EVERY_MS, and the lands a player was found
// holding on signing in since the index was written: usually a single
// request, however many players there are. Before the index's first run,
// every land is checked against its 2023 holder and every player's wallet
// (refreshOwnersByAsking), as before.
async function refreshOwners() {
	addNewLands();
	const index = indexedHolders();
	if (!index.holders) return refreshOwnersByAsking();
	for (const [t, f] of freshHolds) if (f.at <= index.at) freshHolds.delete(t);
	const result = {};
	const pairs = [];
	for (const l of lands) {
		const fresh = freshHolds.get(l.token);
		const h = fresh ? fresh.address : (index.holders.get(l.token) || null);
		result[l.token] = h;
		if (h && watched.has(h)) pairs.push([h, l.token]);
	}
	const held = pairs.length ? await balances(pairs) : [];
	let gone = 0;
	pairs.forEach(([, token], i) => {
		if (!held[i]) { result[token] = null; freshHolds.delete(token); gone++; }
	})
	owners = { updated: new Date().toISOString(), contract: CONTRACT, owners: result };
	writeJsonAtomic(OWNERS_FILE, owners);
	ownersError = null;
	log(`owners updated: ${pairs.length - gone} lands held by player wallets (checked with ${Math.ceil(pairs.length / PAIRS_PER_CALL)} ` +
		`request${Math.ceil(pairs.length / PAIRS_PER_CALL) === 1 ? '' : 's'}${gone ? `; ${gone} no longer held` : ''}), ` +
		`the rest as the chain index says (block ${index.block})`);
}

async function refreshOwnersByAsking() {
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
	const now = Date.now();
	lands.forEach((l, i) => {
		if (held[i]) { owners.owners[l.token] = address; freshHolds.set(l.token, { address, at: now }); }
		else if (owners.owners[l.token] === address) { owners.owners[l.token] = null; freshHolds.delete(l.token); }
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
		const entry = name ? entryOf(name.toLowerCase()) : null;
		if (entry && entry.locked) return null;   // locked by the admin (characters.sh)
		return { address: s.a, name, entry, wallet: true };
	}
	if (s.n) {
		const entry = entryOf(s.n);
		if (!entry || !entry.pw || entry.pw.v !== s.v) return null;   // password changed since
		if (entry.locked) return null;
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
	// The admin's name gets every privilege in the game: nobody else may take
	// it (OV_ADMIN_OPEN=1 for the auth service lets the admin make it, once)
	if (env.OV_ADMIN && name.toLowerCase() === String(env.OV_ADMIN).toLowerCase() && env.OV_ADMIN_OPEN !== '1') {
		return 'That name is kept for the admin.';
	}
	if (entryOf(name.toLowerCase()) || accountExists(name)) {
		return 'That name is taken (perhaps with different capitals). Choose another.';
	}
	return null;
}

const LOCKED = 'This character is locked. Ask at orthoverse.land if you think that is a mistake.';

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

// The highest castle level (0 to 7, either realm) of the lands a wallet holds
// now; the admin counts as 7 (for the skin designer's crowns)
function highestLevel(address, name) {
	if (ADMIN && name === ADMIN) return 7;
	if (!owners || !address) return 0;
	const a = address.toLowerCase();
	let best = 0;
	for (const l of lands) if (owners.owners[l.token] === a) best = Math.max(best, levelOf(l) % 8);
	return best;
}

// ---------------------------------------------------------------------------
// Skins: each character's design (registry.json, skin: { d: the design, h: its
// picture's hash }) and the picture the game wears (skins/<name>.png, 64 x 32)

const SKINS_DIR = join(DATA_DIR, 'skins');
const SKIN_EVERY_MS = parseInt(env.OV_SKIN_EVERY_MS || '60000', 10);
const skinSaved = new Map();   // lower-case name -> when its look last changed
mkdirSync(SKINS_DIR, { recursive: true });
const skinParts = new Map();
for (const f of skin.allParts()) {
	const png = PNG.sync.read(readFileSync(join(SKIN_DIR, 'parts', f + '.png')));
	if (png.width !== 64 || png.height !== 64) throw new Error('skin part ' + f + ' is not 64 x 64');
	skinParts.set(f, png.data);
}

function paintSkin(design) {
	const png = new PNG({ width: 64, height: 32 });
	png.data = Buffer.from(skin.toGame(skin.paint(design, f => skinParts.get(f))));
	return PNG.sync.write(png);
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
	const entry = name ? entryOf(name.toLowerCase()) : null;
	const address = sess.address || null;
	return {
		signedIn: true,
		address: address ? getAddress(address) : null,
		name,
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
		const named = nameOfAddress.get(entry.address);
		if (named && entryOf(named.toLowerCase()).locked) return send(res, 403, { error: LOCKED });
		log('signed in', signer, named || '(no name yet)');
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
		const entry = withSrp({
			name, since: new Date().toISOString(),
			pw: { ...(await makeHash(body.password)), v: 1 },
			rc: await makeHash(normalCode(code)),
		});
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
		const entry = entryOf(key);
		if (entry && !entry.pw) {
			return send(res, 400, { error: 'This character signs in with its wallet. Add a password on the Account page to use one.' });
		}
		if (!entry || !await hashMatches(String(body.password || ''), entry.pw)) {
			loginFailed(key);
			return send(res, 400, { error: 'That name and password do not match.' });
		}
		failedLogins.delete(key);
		if (entry.locked) return send(res, 403, { error: LOCKED });
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
		const entry = entryOf(key);
		if (!entry || !entry.rc || !await hashMatches(normalCode(body.code), entry.rc)) {
			loginFailed(key);
			return send(res, 400, { error: 'That name and recovery code do not match.' });
		}
		if (entry.locked) return send(res, 403, { error: LOCKED });
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
		registry.players[name.toLowerCase()] = withSrp({ name, address, since: new Date().toISOString() });
		nameOfAddress.set(address, name);
		saveRegistry();
		log('name', name, 'for', address);
		send(res, 200, me(address));
	},

	// The character's skin design, and the castle level its accessories may need
	'GET /auth/skin': async (req, res) => {
		const sess = readSession(req);
		if (!sess) return send(res, 401, { error: 'Sign in first.' });
		if (!sess.entry) return send(res, 400, { error: 'Choose a player name first.' });
		send(res, 200, {
			name: sess.entry.name,
			design: sess.entry.skin ? sess.entry.skin.d : null,
			level: highestLevel(sess.address, sess.entry.name),
		});
	},

	// Save the character's skin: the design only. This service paints the
	// picture from the designer's parts (nobody uploads one), writes it where
	// the game reads it, and notes its hash in registry.json, so the game
	// puts it on the player within seconds.
	'POST /auth/skin': async (req, res) => {
		if (limited(req)) return send(res, 429, { error: 'Too many requests; wait a minute.' });
		const sess = readSession(req);
		if (!sess) return send(res, 401, { error: 'Sign in first.' });
		if (!sess.entry) return send(res, 400, { error: 'Choose a player name first.' });
		let body;
		try { body = await readBody(req); } catch (e) { return send(res, 400, { error: 'Send JSON.' }); }
		let design;
		try {
			design = skin.checkDesign(body && body.design, highestLevel(sess.address, sess.entry.name));
		} catch (e) {
			return send(res, 400, { error: e.message });
		}
		const png = paintSkin(design);
		const hash = createHash('sha256').update(png).digest('hex').slice(0, 16);
		// Once a minute at most: each new look is sent to every client in the
		// game, and kept for every client that joins while the server runs
		const key = sess.entry.name.toLowerCase();
		const last = skinSaved.get(key) || 0;
		if (sess.entry.skin && sess.entry.skin.h === hash) return send(res, 200, { design, hash });
		if (Date.now() - last < SKIN_EVERY_MS) {
			return send(res, 429, { error: `You can change your look once a minute: try again in ${Math.ceil((SKIN_EVERY_MS - (Date.now() - last)) / 1000)} seconds.` });
		}
		skinSaved.set(key, Date.now());
		writeFileAtomic(join(SKINS_DIR, sess.entry.name.toLowerCase() + '.png'), png);
		sess.entry.skin = { d: design, h: hash };
		saveRegistry();
		log('skin saved for', sess.entry.name);
		send(res, 200, { design, hash });
	},

	// Entering the game: a fresh game password for this character, for this
	// one entry (see newGamePassword)
	'POST /auth/play': async (req, res) => {
		if (limited(req)) return send(res, 429, { error: 'Too many requests; wait a minute.' });
		const sess = readSession(req);
		if (!sess) return send(res, 401, { error: 'Sign in first.' });
		if (!sess.entry) return send(res, 400, { error: 'Choose a player name first.' });
		const entry = sess.entry;
		const password = newGamePassword();
		entry.srp = srpVerifier(entry.name, password);
		entry.issued = Math.floor(Date.now() / 1000);
		saveRegistry();
		send(res, 200, { name: entry.name, password, exists: accountExistsExact(entry.name) });
	},

	'POST /auth/logout': async (req, res) => {
		send(res, 200, { signedIn: false }, { 'set-cookie': sessionCookie(req, '', 0) });
	},

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
	// The adventures and their records, as the game writes them
	'GET /api/adventures': async (req, res) => {
		let data;
		try {
			data = JSON.parse(readFileSync(ADVENTURES_FILE, 'utf8'));
		} catch (e) {
			data = { updated: null, adventures: [] };
		}
		// Each with its land's token and picture, for the Adventures page
		if (Array.isArray(data.adventures)) {
			for (const a of data.adventures) {
				if (a && typeof a.key === 'string') {
					try {
						a.image = metadata.landImage(a.key);
						a.token = metadata.landToken(a.key);
					} catch (e) { a.image = a.token = null; }
				}
			}
		}
		send(res, 200, data, { 'cache-control': 'public, max-age=30' });
	},

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
	// level 7 holders), or at the entrance of an open adventure chosen on the
	// Adventures page (any character: { adventure: "x:z" }, its land's key).
	// Kept for 10 minutes; the game checks again.
	'POST /auth/visit': async (req, res) => {
		if (limited(req)) return send(res, 429, { error: 'Too many requests; wait a minute.' });
		const sess = readSession(req);
		if (!sess) return send(res, 401, { error: 'Sign in first.' });
		const { address, name } = sess;
		if (!name) return send(res, 400, { error: 'Choose a player name first.' });
		let body;
		try { body = await readBody(req); } catch (e) { return send(res, 400, { error: 'Send JSON.' }); }
		if (body && typeof body === 'object' && !Array.isArray(body) && Object.hasOwn(body, 'adventure')) {
			const key = String(body.adventure);
			if (!/^-?\d{1,3}:-?\d{1,3}$/.test(key)) return send(res, 400, { error: 'Not an adventure.' });
			let open = false;
			try {
				const data = JSON.parse(readFileSync(ADVENTURES_FILE, 'utf8'));
				open = Array.isArray(data.adventures) && data.adventures.some(a => a && a.key === key && a.open === true);
			} catch (e) { /* none open */ }
			if (!open) return send(res, 404, { error: 'That adventure is not open.' });
			visits.visits[name.toLowerCase()] = { name, adventure: key, at: new Date().toISOString(), t: Math.floor(Date.now() / 1000) };
			writeJsonAtomic(VISITS_FILE, visits);
			return send(res, 200, { name, adventure: key });
		}
		if (!mayVisit(address, name)) {
			return send(res, 403, { error: 'Arriving anywhere is for holders of a level 7 land.' });
		}
		const x = Math.round(Number(body && body.x)), z = Math.round(Number(body && body.z));
		const EDGE = 58 * 96 + 47;
		if (!Number.isFinite(x) || !Number.isFinite(z) || Math.abs(x) > EDGE || Math.abs(z) > EDGE) {
			return send(res, 400, { error: 'That is outside the world.' });
		}
		visits.visits[name.toLowerCase()] = { name, x, z, at: new Date().toISOString(), t: Math.floor(Date.now() / 1000) };
		writeJsonAtomic(VISITS_FILE, visits);
		return send(res, 200, { name, x, z });
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
			opensea: opensea.status(),
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
	limited: req => limited(req, 60),
});

// Asking OpenSea to refresh lands whose metadata changed (opensea.js): only
// with an API key (OV_OPENSEA_KEY); without one, nothing is sent
const opensea = createOpenSea({
	apiKey: env.OV_OPENSEA_KEY || '',
	contract: CONTRACT,
	stateFile: join(DATA_DIR, 'opensea.json'),
	tokens: metadata.tokens,
	tokenJson: metadata.tokenJson,
	baseUrl: env.OV_OPENSEA_URL || 'https://api.opensea.io',
	everyMs: Math.max(5, parseFloat(env.OV_OPENSEA_EVERY_MIN || '20')) * 60e3,
	log,
});
opensea.start();

const server = http.createServer(async (req, res) => {
	const url = new URL(req.url, 'http://x');
	try {
		if (metadata(req, res, url)) return;
	} catch (e) {
		log('error', req.method, url.pathname, e.message);
		if (!res.headersSent) send(res, 500, { error: 'The request could not be handled.' });
		return;
	}
	const routeKey = `${req.method} ${url.pathname}`;
	const route = Object.hasOwn(routes, routeKey) ? routes[routeKey] : null;
	if (!route) return send(res, 404, { error: 'Not found' });
	try {
		await route(req, res, url);
	} catch (e) {
		log('error', req.method, url.pathname, e.message);
		if (!res.headersSent) send(res, 400, { error: 'The request could not be handled.' });
	}
});

// ---------------------------------------------------------------------------
// Managing characters from the server's terminal (characters.sh at the top of
// the repository runs admin.js in this container, which asks here). It listens
// on an abstract Unix socket, which only processes in this container can
// reach: nothing on the network, the website or the game can.

const ADMIN_SOCKET = '\0orthoverse-auth-admin';
// Characters deleted here, for the game to remove too (its account, what the
// character carries and where it stands): lower-case name -> { name, at }
const DELETED_FILE = join(DATA_DIR, 'deleted.json');
const deleted = readJson(DELETED_FILE, { format: 1, deleted: {} });

// When each game account last joined (auth.sqlite: last_login, seconds)
function lastLogins() {
	const out = new Map();
	if (!existsSync(AUTH_DB)) return out;
	let db;
	try {
		db = openAuthDb();
		for (const r of db.prepare('SELECT name, last_login FROM auth').all()) out.set(r.name, r.last_login);
	} catch (e) {
		log('auth.sqlite read failed:', e.message);
	} finally {
		try { db && db.close(); } catch (e) { /* closed */ }
	}
	return out;
}
const when = s => (s ? new Date(s * 1000).toISOString().slice(0, 16).replace('T', ' ') : null);

function adminRow(p, logins) {
	return {
		name: p.name, wallet: p.address || null, password: !!p.pw, since: p.since || null,
		lastPlayed: when(logins.get(p.name)), locked: p.locked ? (p.locked.why || true) : false, skin: !!p.skin,
	};
}

const adminCommands = {
	list({ text }) {
		const logins = lastLogins();
		const t = String(text || '').toLowerCase();
		const rows = Object.values(registry.players)
			.filter(p => p && p.name && (!t || p.name.toLowerCase().includes(t) || (p.address || '').toLowerCase().includes(t)))
			.map(p => adminRow(p, logins))
			.sort((a, b) => a.name.localeCompare(b.name, 'en', { sensitivity: 'base' }));
		let guests = 0;
		for (const n of logins.keys()) if (GUEST_RE.test(n)) guests++;
		return { characters: rows, guests };
	},
	show({ name }) {
		const p = entryOf(String(name || '').toLowerCase());
		if (!p) return { error: `No character called ${name}.` };
		const row = adminRow(p, lastLogins());
		return {
			...row,
			gameAccount: accountExistsExact(p.name),
			lands: p.address ? landsOf(p.address.toLowerCase()).map(l => `${l.name} (${l.key || l.token})`) : [],
			lastEntry: p.issued ? when(p.issued) : null,
			visit: visits.visits[p.name.toLowerCase()] || null,
			admin: !!(ADMIN && p.name === ADMIN),
		};
	},
	lock({ name, why }) {
		const p = entryOf(String(name || '').toLowerCase());
		if (!p) return { error: `No character called ${name}.` };
		p.locked = { at: new Date().toISOString(), why: String(why || '').slice(0, 200) || null };
		saveRegistry();
		log('admin: locked', p.name, p.locked.why || '');
		return { done: `${p.name} is locked: signed out on the website, and put out of the game within 15 seconds.` };
	},
	unlock({ name }) {
		const p = entryOf(String(name || '').toLowerCase());
		if (!p) return { error: `No character called ${name}.` };
		if (!p.locked) return { done: `${p.name} was not locked.` };
		delete p.locked;
		saveRegistry();
		log('admin: unlocked', p.name);
		return { done: `${p.name} is unlocked.` };
	},
	async recovery({ name }) {
		const p = entryOf(String(name || '').toLowerCase());
		if (!p) return { error: `No character called ${name}.` };
		const code = makeRecoveryCode();
		p.rc = await makeHash(normalCode(code));
		saveRegistry();
		log('admin: new recovery code for', p.name);
		return { done: `A new recovery code for ${p.name} (the old one no longer works): ${code}\n` +
			'With it the player sets a new password: Sign in, then "Forgot your password?".', code };
	},
	delete({ name }) {
		const key = String(name || '').toLowerCase();
		const p = entryOf(key);
		if (!p) return { error: `No character called ${name}.` };
		delete registry.players[key];
		if (p.address) {
			const a = p.address.toLowerCase();
			if (nameOfAddress.get(a) === p.name) nameOfAddress.delete(a);
		}
		delete visits.visits[key];
		writeJsonAtomic(VISITS_FILE, visits);
		try { unlinkSync(join(SKINS_DIR, key + '.png')); } catch (e) { /* none */ }
		deleted.deleted[key] = { name: p.name, at: Math.floor(Date.now() / 1000) };
		writeJsonAtomic(DELETED_FILE, deleted);
		saveRegistry();
		log('admin: deleted', p.name, p.address || '');
		return { done: `${p.name} is deleted. The game puts them out if they are playing, then removes their game account, ` +
			'what they carry and where they stand, within a minute. The name is free again after that' +
			(p.address ? '; the wallet can sign in again and choose a new name.' : '.') };
	},
};

const adminServer = net.createServer(sock => {
	let buf = '';
	sock.setEncoding('utf8');
	sock.on('data', async chunk => {
		buf += chunk;
		if (!buf.includes('\n')) return;
		let out;
		try {
			const req = JSON.parse(buf.slice(0, buf.indexOf('\n')));
			const cmd = Object.hasOwn(adminCommands, req.cmd) ? adminCommands[req.cmd] : null;
			out = cmd ? await cmd(req) : { error: 'Unknown command.' };
		} catch (e) {
			out = { error: e.message };
		}
		sock.end(JSON.stringify(out) + '\n');
	});
	sock.on('error', () => {});
});
adminServer.on('error', e => log('admin socket:', e.message));
adminServer.listen(ADMIN_SOCKET);

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
