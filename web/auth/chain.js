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
//
//   node chain.js           index now, then again every OV_CHAIN_EVERY_HOURS (24)
//   node chain.js --once    index now and exit

'use strict';

import { readFileSync, writeFileSync, renameSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { Interface } from 'ethers';

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
const FROM_BLOCK = parseInt(env.OV_CHAIN_FROM_BLOCK || String(MERGE_BLOCK), 10);
const EVERY_MS = parseFloat(env.OV_CHAIN_EVERY_HOURS || '24') * 3600 * 1000;
const CONFIRMATIONS = 64;       // stay this far behind the chain head (reorgs)
const MAX_SPAN = 500000;        // blocks per eth_getLogs, at most
const LEVEL_CALLS = 50;         // castleLevel calls per JSON-RPC batch

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

// Land tokens, and their holders in the April 2023 snapshot
const landTokens = (() => {
	try {
		const data = JSON.parse(readFileSync(LANDS_FILE, 'utf8'));
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
	const upsert = db.prepare(`INSERT INTO tokens (token_id, holder, revealed_block, last_transfer_block, has_land)
		VALUES (?, ?, ?, ?, ?)
		ON CONFLICT(token_id) DO UPDATE SET holder = excluded.holder, revealed_block = excluded.revealed_block,
			last_transfer_block = excluded.last_transfer_block, has_land = excluded.has_land`);
	db.exec('BEGIN');
	for (const [id, t] of holders) {
		upsert.run(id, t.holder, t.revealed, t.last, landTokens.has(id) ? 1 : 0);
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
		const results = await withRetries('castleLevel', () => rpcBatch('eth_call', chunk.map(id => [
			{ to: CONTRACT, data: abi.encodeFunctionData('castleLevel', [BigInt(id)]) }, 'latest'])));
		db.exec('BEGIN');
		chunk.forEach((id, j) => {
			const level = Number(abi.decodeFunctionResult('castleLevel', results[j])[0]);
			if (before.get(id) !== level) changed++;
			update.run(level, REALMS[level > 7 ? 1 : 0], id);
		});
		db.exec('COMMIT');
		await sleep(100);
	}
	return changed;
}

function writeFiles(block) {
	const rows = db.prepare('SELECT * FROM tokens ORDER BY revealed_block NULLS FIRST, token_id').all();
	const updated = new Date().toISOString();
	const tokens = {};
	for (const r of rows) {
		tokens[r.token_id] = { holder: r.holder, level: r.level, realm: r.realm, revealed: r.revealed_block };
	}
	writeJsonAtomic(join(DIR, 'tokens.json'), { updated, block, contract: CONTRACT, tokens });
	writeJsonAtomic(join(DIR, 'token-data.json'),
		rows.filter(r => r.holder).map(r => [r.holder, String(r.level), r.token_id, r.revealed_block == null ? '' : String(r.revealed_block)]), 1);
	setMeta('updated', updated);
}

async function run() {
	const t0 = Date.now();
	const { found, block } = await readEvents();
	const n = rebuildHolders();
	const changed = await readLevels();
	writeFiles(block);
	const held = db.prepare('SELECT count(*) AS n FROM tokens WHERE holder IS NOT NULL').get().n;
	const holders = db.prepare('SELECT count(DISTINCT holder) AS n FROM tokens WHERE holder IS NOT NULL').get().n;
	const landless = db.prepare('SELECT count(*) AS n FROM tokens WHERE holder IS NOT NULL AND has_land = 0').get().n;
	log(`chain indexed to block ${block}: ${found} new transfers; ${n} tokens, ${held} held by ${holders} wallets; ` +
		`${changed} levels changed; ${landless} tokens have no land in the world yet ` +
		`(${Math.round((Date.now() - t0) / 1000)} s)`);
}

const once = process.argv.includes('--once');
log(`Orthoverse chain indexer: contract ${CONTRACT} via ${RPC_SHOWN}, data in ${DIR}` +
	(once ? '' : `, every ${EVERY_MS / 3600000} h`));

for (;;) {
	let wait = EVERY_MS;
	try {
		await run();
	} catch (e) {
		log('indexing failed (it carries on from where it got to, within the hour):', e.message);
		if (once) process.exit(1);
		wait = Math.min(EVERY_MS, 3600 * 1000);
	}
	if (once) break;
	await sleep(wait);
}
db.close();
