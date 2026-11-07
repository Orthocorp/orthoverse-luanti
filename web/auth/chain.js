// Orthoverse chain indexer: every token of the Orthoverse contract, who holds
// it, its castle level and realm, kept in a SQLite database and refreshed
// daily. It does what scrape-tokenids-and-levels.js in orthoverse-contracts
// did, but incrementally, through a public RPC endpoint.
//
// The contract is an ERC-1155 with one token per land; a token's ID is the
// address that revealed it. Every reveal, gift, migration and transfer emits a
// TransferSingle (or TransferBatch) event, always for one token, so replaying
// the events in order gives the holder of every token. Castle levels change
// without an event (upgradeCastleLevel, flipRealm), so they are read afresh
// with castleLevel() on every run.
//
// Writes, in OV_CHAIN_DIR (default /chain):
//   orthoverse-chain.sqlite  tables tokens, transfers (since FROM_BLOCK) and meta
//   tokens.json              { updated, block, contract, tokens: { id: {holder, level, realm, revealed} } }
//   token-data.json          the old format: [[holder, level, tokenId, revealBlock], ...]
//   land-levels.json         every land's current castle level: { levels: { "x:z": level } },
//                            which the game builds the lands from
//   new-lands.json           lands placed for tokens revealed after the world's lands
//                            were fixed: { updated, lands: { "x:z": land } }, read by
//                            the game, the auth service and the web map
//
//   node chain.js           index now, then again every OV_CHAIN_EVERY_HOURS (24)
//   node chain.js --once    index now and exit

'use strict';

import { readFileSync, writeFileSync, renameSync, mkdirSync, existsSync, statSync } from 'node:fs';
import { randomInt } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { Interface } from 'ethers';
import { landName, landDescription } from './names.js';

const env = process.env;
const RPC_URL = env.OV_ETH_RPC || 'https://ethereum-rpc.publicnode.com';
// The endpoint's host only: keyed endpoints (Alchemy, Infura) carry the API
// key in the path, which must not reach logs or the public status page
const RPC_SHOWN = (() => { try { return new URL(RPC_URL).host; } catch (e) { return '(endpoint)'; } })();
const CONTRACT = (env.OV_CONTRACT || '0x118aeD2606D02C2545C6D7D2d1021e567cc08922').toLowerCase();
const DIR = env.OV_CHAIN_DIR || '/chain';
const LANDS_FILE = env.OV_LANDS || '/app/lands.json';
// Where the events are read from: the Merge (15 September 2022). Most nodes
// no longer keep logs from before it (history expiry, EIP-4444), so the
// holders before that come from the lands file's snapshot of April 2023
// (owner_snapshot), and events from here on are replayed over it. Any block
// before the snapshot works; with a node that keeps full history, 14000000
// reads everything since before V2 was deployed.
const MERGE_BLOCK = 15537394;
// Alchemy endpoints: read transfers with alchemy_getAssetTransfers, which
// takes any block range, 1000 transfers a call, and keeps the whole history.
// (Alchemy's free plan allows eth_getLogs only a few blocks at a time.)
// OV_CHAIN_METHOD=logs or =transfers overrides the choice.
const METHOD = env.OV_CHAIN_METHOD ||
	(/(^|\.)alchemy\.com$/.test((() => { try { return new URL(RPC_URL).hostname; } catch (e) { return ''; } })()) ? 'transfers' : 'logs');
// With the transfers API, everything since before V2 was deployed
const FROM_BLOCK = parseInt(env.OV_CHAIN_FROM_BLOCK || (METHOD === 'transfers' ? '14000000' : String(MERGE_BLOCK)), 10);
const EVERY_MS = parseFloat(env.OV_CHAIN_EVERY_HOURS || '24') * 3600 * 1000;
const CONFIRMATIONS = 64;       // stay this far behind the chain head (reorgs)
const MAX_SPAN = 500000;        // blocks per eth_getLogs, at most
const LEVEL_CALLS = 500;        // castleLevel calls per Multicall3 eth_call
// Multicall3, the same address on every chain: many read calls in one
// eth_call, which keyed endpoints count as one call (Alchemy's free plan
// refuses 50 separate calls a second)
const MULTICALL3 = '0xcA11bde05977b3631167028862bE2a173976CA11';
const multicall = new Interface([
	'function aggregate3((address target, bool allowFailure, bytes callData)[] calls) payable returns ((bool success, bytes returnData)[] returnData)',
]);

// The crests (web/heraldry, /app/heraldry in the image)
const HERALDRY = env.OV_HERALDRY || fileURLToPath(new URL(
	existsSync(new URL('./heraldry', import.meta.url)) ? './heraldry/' : '../heraldry/', import.meta.url));

const ZERO = '0x' + '0'.repeat(40);
const abi = new Interface([
	'event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value)',
	'event TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values)',
	'function castleLevel(uint256 tokenId) view returns (uint256)',
]);
const TOPICS = [abi.getEvent('TransferSingle').topicHash, abi.getEvent('TransferBatch').topicHash];
const REALMS = ['fantasy', 'futuristic'];   // castle levels 0-7 and 8-15

function log(...args) {
	console.log(new Date().toISOString(), ...args);
}

const sleep = ms => new Promise(r => setTimeout(r, ms));

// Token IDs as the lands file writes them: 0x and at least 40 hex digits
function tokenHex(id) {
	return '0x' + BigInt(id).toString(16).padStart(40, '0');
}

function writeJsonAtomic(path, value, indent) {
	writeFileSync(path + '.tmp', JSON.stringify(value, null, indent));
	renameSync(path + '.tmp', path);
}

// ---------------------------------------------------------------------------
// JSON-RPC

// What the endpoint said when it refused, briefly
async function reason(res) {
	try { return (await res.text()).replace(/\s+/g, ' ').trim().slice(0, 200); } catch (e) { return ''; }
}

let rpcId = 0;
async function rpc(method, params) {
	const res = await fetch(RPC_URL, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ jsonrpc: '2.0', id: ++rpcId, method, params }),
		signal: AbortSignal.timeout(60000),
	});
	if (!res.ok) throw new Error(`${method}: HTTP ${res.status} ${await reason(res)}`);
	const out = await res.json();
	if (out.error) throw new Error(`${method}: ${out.error.message || JSON.stringify(out.error)}`);
	return out.result;
}

async function rpcBatch(method, paramsList) {
	const body = paramsList.map((params, i) => ({ jsonrpc: '2.0', id: i, method, params }));
	const res = await fetch(RPC_URL, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body),
		signal: AbortSignal.timeout(60000),
	});
	if (!res.ok) throw new Error(`${method} batch: HTTP ${res.status} ${await reason(res)}`);
	const out = await res.json();
	if (!Array.isArray(out)) throw new Error(`${method} batch: ${JSON.stringify(out).slice(0, 200)}`);
	const byId = new Map(out.map(r => [r.id, r]));
	return paramsList.map((p, i) => {
		const r = byId.get(i);
		if (!r || r.error || r.result === undefined) {
			throw new Error(`${method}: ${JSON.stringify(r && (r.error || r)).slice(0, 200)}`);
		}
		return r.result;
	});
}

async function withRetries(what, fn) {
	for (let attempt = 1; ; attempt++) {
		try {
			return await fn();
		} catch (e) {
			if (attempt >= 4) throw e;
			log(`${what} failed (${e.message}); trying again`);
			await sleep(2000 * attempt);
		}
	}
}

// ---------------------------------------------------------------------------
// Database

mkdirSync(DIR, { recursive: true });
const db = new DatabaseSync(join(DIR, 'orthoverse-chain.sqlite'));
db.exec(`
	CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
	CREATE TABLE IF NOT EXISTS transfers (
		block INTEGER NOT NULL, log_index INTEGER NOT NULL, item INTEGER NOT NULL,
		tx TEXT NOT NULL, token_id TEXT NOT NULL, from_addr TEXT NOT NULL, to_addr TEXT NOT NULL,
		PRIMARY KEY (block, log_index, item));
	CREATE INDEX IF NOT EXISTS transfers_token ON transfers (token_id);
	CREATE TABLE IF NOT EXISTS tokens (
		token_id TEXT PRIMARY KEY,
		holder TEXT,              -- NULL if burnt
		level INTEGER,            -- castleLevel(): 0-7 fantasy, 8-15 futuristic
		realm TEXT,
		revealed_block INTEGER,
		last_transfer_block INTEGER,
		has_land INTEGER NOT NULL DEFAULT 0);
	CREATE INDEX IF NOT EXISTS tokens_holder ON tokens (holder);
	-- Each castle's crest (a picture in web/heraldry/escutcheons.png)
	CREATE TABLE IF NOT EXISTS crests (
		token_id TEXT PRIMARY KEY, crest INTEGER NOT NULL UNIQUE, assigned_at TEXT NOT NULL);
	-- Where new lands were placed: for good, never moved
	CREATE TABLE IF NOT EXISTS placements (
		token_id TEXT PRIMARY KEY, land_key TEXT NOT NULL UNIQUE,
		name TEXT NOT NULL, placed_at TEXT NOT NULL);
`);

function getMeta(key) {
	const r = db.prepare('SELECT value FROM meta WHERE key = ?').get(key);
	return r ? r.value : null;
}
function setMeta(key, value) {
	db.prepare('INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value')
		.run(key, String(value));
}

const contractSeen = getMeta('contract');
if (contractSeen && contractSeen !== CONTRACT) {
	console.error(`The database in ${DIR} is for contract ${contractSeen}, not ${CONTRACT}. ` +
		'Move it away to index the new contract from the start.');
	process.exit(1);
}
setMeta('contract', CONTRACT);

const insertTransfer = db.prepare(`INSERT OR IGNORE INTO transfers
	(block, log_index, item, tx, token_id, from_addr, to_addr) VALUES (?, ?, ?, ?, ?, ?, ?)`);

// The world's fixed lands (keys and names), its planned seas, and its radius
const world = { keys: new Set(), names: new Set(), seas: new Set(), radius: 56, crests: new Map(), keyOf: new Map() };

// Land tokens, and their holders in the April 2023 snapshot
const landTokens = (() => {
	try {
		const data = JSON.parse(readFileSync(LANDS_FILE, 'utf8'));
		for (const [key, l] of Object.entries(data.lands)) {
			world.keys.add(key);
			world.names.add(l.name);
			if (l.token) world.keyOf.set(l.token.toLowerCase(), key);
			const m = /^(\d+)\.png$/.exec(l.crest || '');
			if (m && l.token) world.crests.set(l.token.toLowerCase(), parseInt(m[1], 10));
		}
		for (const key of data.seas || []) world.seas.add(key);
		if (data.map_radius) world.radius = data.map_radius;
		const map = new Map();
		for (const l of Object.values(data.lands)) {
			if (!l.token) continue;
			const snap = /^0x[0-9a-fA-F]{40}$/.test(l.owner_snapshot || '') ? l.owner_snapshot.toLowerCase() : null;
			map.set(l.token.toLowerCase(), snap);
		}
		return map;
	} catch (e) {
		log('cannot read the lands file', LANDS_FILE, '- no snapshot, and has_land will be 0 for every token');
		return new Map();
	}
})();

// ---------------------------------------------------------------------------
// Steps

// New transfer events since the last run, in block ranges that shrink when
// the endpoint refuses a range (too many blocks or results) and grow again
// while ranges come back nearly empty
async function readEvents() {
	return METHOD === 'transfers' ? readTransfers() : readLogs();
}

// Alchemy's transfers API: every transfer of the contract's tokens in the
// range, oldest first, a page at a time
async function readTransfers() {
	const head = parseInt(await withRetries('eth_blockNumber', () => rpc('eth_blockNumber', [])), 16);
	const to = head - CONFIRMATIONS;
	const from = parseInt(getMeta('last_block') || String(FROM_BLOCK - 1), 10) + 1;
	let found = 0;
	if (from > to) return { found, block: to };
	let pageKey;
	let pages = 0;
	do {
		const params = {
			fromBlock: '0x' + from.toString(16), toBlock: '0x' + to.toString(16),
			contractAddresses: [CONTRACT], category: ['erc1155'],
			withMetadata: false, excludeZeroValue: false, maxCount: '0x3e8', order: 'asc',
		};
		if (pageKey) params.pageKey = pageKey;
		const result = await withRetries('alchemy_getAssetTransfers', () => rpc('alchemy_getAssetTransfers', [params]));
		const perBlock = new Map();
		db.exec('BEGIN');
		try {
			for (const t of result.transfers || []) {
				const block = parseInt(t.blockNum, 16);
				// uniqueId is "<tx hash>:log:<log index>"
				const m = /:log:(\d+)$/.exec(t.uniqueId || '');
				let index;
				if (m) index = parseInt(m[1], 10);
				else { index = 100000 + (perBlock.get(block) || 0); perBlock.set(block, index - 99999); }
				const fromAddr = (t.from || ZERO).toLowerCase();
				const toAddr = (t.to || ZERO).toLowerCase();
				(t.erc1155Metadata || []).forEach((item, n) => {
					insertTransfer.run(block, index, n, t.hash, tokenHex(item.tokenId), fromAddr, toAddr);
					found++;
				});
			}
			db.exec('COMMIT');
		} catch (e) {
			db.exec('ROLLBACK');
			throw e;
		}
		pageKey = result.pageKey;
		pages++;
		if (pages % 10 === 0) log(`transfers: ${pages} pages, ${found} so far`);
		await sleep(100);
	} while (pageKey);
	setMeta('last_block', to);
	return { found, block: to };
}

// Plain eth_getLogs, for any other endpoint
async function readLogs() {
	const head = parseInt(await withRetries('eth_blockNumber', () => rpc('eth_blockNumber', [])), 16);
	const to = head - CONFIRMATIONS;
	let from = parseInt(getMeta('last_block') || String(FROM_BLOCK - 1), 10) + 1;
	let span = parseInt(getMeta('span') || '10000', 10);
	let ceiling = MAX_SPAN;    // the largest range not yet refused this run
	let found = 0;
	const start = from;
	let lastReport = Date.now();
	while (from <= to) {
		const end = Math.min(from + span - 1, to);
		let logs;
		try {
			logs = await rpc('eth_getLogs', [{
				address: CONTRACT, topics: [TOPICS],
				fromBlock: '0x' + from.toString(16), toBlock: '0x' + end.toString(16),
			}]);
		} catch (e) {
			if (span > 1) {
				span = Math.max(1, Math.floor(span / 2));
				ceiling = span;
				await sleep(500);
				continue;
			}
			// One block and still refused: not a range problem
			try {
				await withRetries(`eth_getLogs at block ${from}`, async () => {
					logs = await rpc('eth_getLogs', [{ address: CONTRACT, topics: [TOPICS],
						fromBlock: '0x' + from.toString(16), toBlock: '0x' + end.toString(16) }]);
				});
			} catch (e2) {
				throw new Error(`${e2.message}. The endpoint will not give logs for block ${from}: ` +
					'it may not keep history that old (OV_CHAIN_FROM_BLOCK), or may not allow eth_getLogs (OV_ETH_RPC)');
			}
		}
		db.exec('BEGIN');
		try {
			for (const l of logs) {
				if (l.removed) continue;
				const ev = abi.parseLog({ topics: l.topics, data: l.data });
				if (!ev) continue;
				const block = parseInt(l.blockNumber, 16);
				const index = parseInt(l.logIndex, 16);
				const fromAddr = ev.args.from.toLowerCase();
				const toAddr = ev.args.to.toLowerCase();
				const ids = ev.name === 'TransferSingle' ? [ev.args.id] : [...ev.args.ids];
				ids.forEach((id, item) => {
					insertTransfer.run(block, index, item, l.transactionHash, tokenHex(id), fromAddr, toAddr);
				});
				found += ids.length;
			}
			setMeta('last_block', end);
			setMeta('span', span);
			db.exec('COMMIT');
		} catch (e) {
			db.exec('ROLLBACK');
			throw e;
		}
		from = end + 1;
		if (logs.length < 1000) span = Math.min(ceiling, span * 2);
		if (Date.now() - lastReport > 60000) {
			log(`events: block ${end} of ${to} (${Math.round(100 * (end - start) / Math.max(1, to - start))}%), ${found} so far`);
			lastReport = Date.now();
		}
		await sleep(100);
	}
	return { found, block: to };
}

// Start from the snapshot, then replay every transfer in order: the last
// recipient holds the token
function rebuildHolders() {
	const holders = new Map();   // token -> { holder, revealed, last }
	for (const [id, snap] of landTokens) {
		holders.set(id, { holder: snap, revealed: null, last: null });
	}
	const rows = db.prepare('SELECT block, token_id, from_addr, to_addr FROM transfers ORDER BY block, log_index, item').all();
	for (const r of rows) {
		const t = holders.get(r.token_id) || { holder: null, revealed: null, last: null };
		if (r.from_addr === ZERO && t.revealed === null) t.revealed = r.block;
		t.holder = r.to_addr === ZERO ? null : r.to_addr;
		t.last = r.block;
		holders.set(r.token_id, t);
	}
	const placed = new Set(db.prepare('SELECT token_id FROM placements').all().map(r => r.token_id));
	const upsert = db.prepare(`INSERT INTO tokens (token_id, holder, revealed_block, last_transfer_block, has_land)
		VALUES (?, ?, ?, ?, ?)
		ON CONFLICT(token_id) DO UPDATE SET holder = excluded.holder, revealed_block = excluded.revealed_block,
			last_transfer_block = excluded.last_transfer_block, has_land = excluded.has_land`);
	db.exec('BEGIN');
	for (const [id, t] of holders) {
		upsert.run(id, t.holder, t.revealed, t.last, landTokens.has(id) || placed.has(id) ? 1 : 0);
	}
	db.exec('COMMIT');
	return holders.size;
}

async function readLevels() {
	const ids = db.prepare('SELECT token_id FROM tokens').all().map(r => r.token_id);
	const update = db.prepare('UPDATE tokens SET level = ?, realm = ? WHERE token_id = ?');
	let changed = 0;
	const before = new Map(db.prepare('SELECT token_id, level FROM tokens').all().map(r => [r.token_id, r.level]));
	for (let i = 0; i < ids.length; i += LEVEL_CALLS) {
		const chunk = ids.slice(i, i + LEVEL_CALLS);
		const data = multicall.encodeFunctionData('aggregate3', [chunk.map(id =>
			[CONTRACT, false, abi.encodeFunctionData('castleLevel', [BigInt(id)])])]);
		const raw = await withRetries('castleLevel', () => rpc('eth_call', [{ to: MULTICALL3, data }, 'latest']));
		const results = multicall.decodeFunctionResult('aggregate3', raw)[0];
		db.exec('BEGIN');
		chunk.forEach((id, j) => {
			const level = Number(abi.decodeFunctionResult('castleLevel', results[j].returnData)[0]);
			if (before.get(id) !== level) changed++;
			update.run(level, REALMS[level > 7 ? 1 : 0], id);
		});
		db.exec('COMMIT');
		await sleep(250);
	}
	return changed;
}

function writeFiles(block) {
	const rows = db.prepare(`SELECT t.*, c.crest FROM tokens t LEFT JOIN crests c ON c.token_id = t.token_id
		ORDER BY t.revealed_block NULLS FIRST, t.token_id`).all();
	const updated = new Date().toISOString();
	const tokens = {};
	for (const r of rows) {
		tokens[r.token_id] = { holder: r.holder, level: r.level, realm: r.realm, revealed: r.revealed_block, crest: r.crest ?? null };
	}
	writeJsonAtomic(join(DIR, 'tokens.json'), { updated, block, contract: CONTRACT, tokens });
	writeJsonAtomic(join(DIR, 'token-data.json'),
		rows.filter(r => r.holder).map(r => [r.holder, String(r.level), r.token_id, r.revealed_block == null ? '' : String(r.revealed_block)]), 1);
	setMeta('updated', updated);
}

// ---------------------------------------------------------------------------
// New lands

// The cells of the old map in the order generate-map-from-db-sqlite.js filled
// them: one square spiral around each henge centre, all nine growing together,
// a land dealt to each spiral in turn. Coordinates are land keys (x, z; z grows
// southwards). The 1943 fixed lands are exactly the first cells of this order,
// skipping the planned seas.
const SPIRAL_CENTRES = [[0, 0], [-30, -30], [0, -30], [30, -30], [-30, 0], [30, 0], [-30, 30], [0, 30], [30, 30]];
function* spiral() {
	let x = 0, y = 0, d = 1;
	for (let m = 1; m < 4 * world.radius; m++) {
		while (2 * y * d < m) {
			for (const [cx, cy] of SPIRAL_CENTRES) yield [cx + x, cy + y];
			y += d;
		}
		while (2 * x * d < m) {
			for (const [cx, cy] of SPIRAL_CENTRES) yield [cx + x, cy + y];
			x += d;
		}
		d = -d;
	}
}

// Give every token that has no land yet the next free cell, in the order the
// tokens were revealed. Returns how many were placed.
function placeNewLands() {
	const waiting = db.prepare(`SELECT token_id FROM tokens
		WHERE has_land = 0 AND holder IS NOT NULL
		ORDER BY revealed_block IS NULL, revealed_block, token_id`).all().map(r => r.token_id);
	if (!waiting.length) return 0;
	const taken = new Set([...world.keys, ...world.seas,
		...db.prepare('SELECT land_key FROM placements').all().map(r => r.land_key)]);
	const names = new Set([...world.names, ...db.prepare('SELECT name FROM placements').all().map(r => r.name)]);
	const insert = db.prepare('INSERT INTO placements (token_id, land_key, name, placed_at) VALUES (?, ?, ?, ?)');
	const mark = db.prepare('UPDATE tokens SET has_land = 1 WHERE token_id = ?');
	const cells = spiral();
	let n = 0;
	db.exec('BEGIN');
	for (const token of waiting) {
		// (next() by hand: leaving a for...of would close the generator)
		let key = null;
		for (let c = cells.next(); !c.done; c = cells.next()) {
			const [x, z] = c.value;
			const k = `${x}:${z}`;
			if (Math.max(Math.abs(x), Math.abs(z)) > world.radius || taken.has(k)) continue;
			key = k;
			break;
		}
		if (!key) { log('no free cell left for', token); break; }
		taken.add(key);
		let name = landName(token);
		if (names.has(name)) name += ' Parva';   // as orthoverse-offline did for a repeat
		for (let i = 2; names.has(name); i++) name = landName(token) + ' ' + i;
		names.add(name);
		insert.run(token, key, name, new Date().toISOString());
		mark.run(token);
		log(`new land ${name} at ${key} for token ${token}`);
		n++;
	}
	db.exec('COMMIT');
	return n;
}

function writeNewLands() {
	const rows = db.prepare(`SELECT p.land_key, p.token_id, p.name, p.placed_at, t.level, t.holder, c.crest
		FROM placements p JOIN tokens t ON t.token_id = p.token_id LEFT JOIN crests c ON c.token_id = p.token_id
		ORDER BY p.placed_at, p.land_key`).all();
	const lands = {};
	for (const r of rows) {
		const level = r.level || 0;
		lands[r.land_key] = {
			token: r.token_id, name: r.name, level, crest: r.crest == null ? null : r.crest + '.png',
			owner_snapshot: r.holder, description: landDescription(r.name, level), placed: r.placed_at,
		};
	}
	writeJsonAtomic(join(DIR, 'new-lands.json'), { format: 1, updated: new Date().toISOString(), lands }, 1);

	// Every land's current level, fixed lands and new ones
	const levels = {};
	for (const r of db.prepare('SELECT token_id, level FROM tokens WHERE level IS NOT NULL').all()) {
		const key = world.keyOf.get(r.token_id);
		if (key) levels[key] = r.level;
	}
	for (const r of rows) if (r.level != null) levels[r.land_key] = r.level;
	writeJsonAtomic(join(DIR, 'land-levels.json'), { format: 1, updated: new Date().toISOString(), levels });
	return rows.length;
}

// ---------------------------------------------------------------------------
// Crests, as orthoverse-offline's update-escutcheons.js gave them out: a land
// gets a crest when it has a castle (castle level 1 to 7 in either realm),
// chosen at random from those not yet used: a plain one (2808 and up) for
// levels 1 to 3, one with an animal (below 2808) from level 4, and a plain one
// is swapped for an animal one when the land reaches level 4. The crests in
// the lands file (2023) are kept.

const heraldry = (() => {
	try {
		return JSON.parse(readFileSync(join(HERALDRY, 'heraldry.json'), 'utf8'));
	} catch (e) {
		log('cannot read the heraldry in', HERALDRY, '- no crests will be given out');
		return null;
	}
})();

function assignCrests() {
	if (!heraldry) return { given: 0, upgraded: 0 };
	const now = new Date().toISOString();
	const seed = db.prepare('INSERT OR IGNORE INTO crests (token_id, crest, assigned_at) VALUES (?, ?, ?)');
	db.exec('BEGIN');
	for (const [token, crest] of world.crests) seed.run(token, crest, now);
	db.exec('COMMIT');

	const current = new Map(db.prepare('SELECT token_id, crest FROM crests').all().map(r => [r.token_id, r.crest]));
	const used = new Set(current.values());
	const free = { animals: [], plain: [] };
	const missing = new Set(heraldry.missing);
	for (let i = 0; i < heraldry.count; i++) {
		if (used.has(i) || missing.has(i) || !heraldry.blazons[String(i)]) continue;
		(i < heraldry.animals_below ? free.animals : free.plain).push(i);
	}
	const take = list => list.length ? list.splice(randomInt(list.length), 1)[0] : null;
	const set = db.prepare(`INSERT INTO crests (token_id, crest, assigned_at) VALUES (?, ?, ?)
		ON CONFLICT(token_id) DO UPDATE SET crest = excluded.crest, assigned_at = excluded.assigned_at`);
	let given = 0, upgraded = 0;
	db.exec('BEGIN');
	for (const t of db.prepare('SELECT token_id, level FROM tokens WHERE holder IS NOT NULL AND level IS NOT NULL').all()) {
		const castle = t.level % 8;
		if (castle === 0) continue;
		const had = current.get(t.token_id);
		if (had === undefined) {
			const crest = castle >= 4 ? (take(free.animals) ?? take(free.plain)) : take(free.plain);
			if (crest === null) { log('no crests left for', t.token_id); continue; }
			set.run(t.token_id, crest, now);
			given++;
		} else if (castle >= 4 && had >= heraldry.animals_below) {
			const crest = take(free.animals);
			if (crest === null) continue;   // the animals have run out: keep the plain one
			set.run(t.token_id, crest, now);
			free.plain.push(had);
			upgraded++;
		}
	}
	db.exec('COMMIT');
	return { given, upgraded };
}

async function run() {
	const t0 = Date.now();
	const { found, block } = await readEvents();
	const n = rebuildHolders();
	const changed = await readLevels();
	const placedNow = placeNewLands();
	const crests = assignCrests();
	const newLands = writeNewLands();
	writeFiles(block);
	const held = db.prepare('SELECT count(*) AS n FROM tokens WHERE holder IS NOT NULL').get().n;
	const holders = db.prepare('SELECT count(DISTINCT holder) AS n FROM tokens WHERE holder IS NOT NULL').get().n;
	const landless = db.prepare('SELECT count(*) AS n FROM tokens WHERE holder IS NOT NULL AND has_land = 0').get().n;
	log(`chain indexed to block ${block}: ${found} new transfers; ${n} tokens, ${held} held by ${holders} wallets; ` +
		`${changed} levels changed; ${crests.given} crests given, ${crests.upgraded} upgraded; ` +
		`${placedNow} new lands placed (${newLands} in all)` +
		(landless ? `; ${landless} tokens still without land` : '') + ' ' +
		`(${Math.round((Date.now() - t0) / 1000)} s)`);
}

const once = process.argv.includes('--once');
log(`Orthoverse chain indexer: contract ${CONTRACT} via ${RPC_SHOWN} (${METHOD === 'transfers' ? 'alchemy_getAssetTransfers' : 'eth_getLogs'}), data in ${DIR}` +
	(once ? '' : `, every ${EVERY_MS / 3600000} h`));

// Asked to index now: the auth service writes this file when someone has just
// revealed a token on the lands page, so the land is placed in a minute
// rather than at the next daily run. Looked for every 15 seconds; at most one
// extra run a minute.
const REQUEST_FILE = env.OV_CHAIN_REQUEST || '/requests/index-now';
const REQUEST_GAP_MS = parseInt(env.OV_CHAIN_REQUEST_GAP_MS || '60000', 10);
const REQUEST_POLL_MS = parseInt(env.OV_CHAIN_REQUEST_POLL_MS || '15000', 10);
function requestedAfter(t) {
	try { return statSync(REQUEST_FILE).mtimeMs > t; } catch (e) { return false; }
}

for (;;) {
	let wait = EVERY_MS;
	const started = Date.now();
	try {
		await run();
	} catch (e) {
		log('indexing failed (it carries on from where it got to, within the hour):', e.message);
		if (once) process.exit(1);
		wait = Math.min(EVERY_MS, 3600 * 1000);
	}
	if (once) break;
	const until = Date.now() + wait;
	while (Date.now() < until) {
		await sleep(REQUEST_POLL_MS);
		if (requestedAfter(started) && Date.now() - started > REQUEST_GAP_MS) {
			log('asked to index now (a token was revealed on the lands page)');
			break;
		}
	}
}
db.close();
