// Test of the chain indexer (chain.js) and of the auth service using its index,
// against a stand-in Ethereum endpoint. Run: npm test (from web/auth).

import http from 'node:http';
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { Wallet, Interface } from 'ethers';

const dir = mkdtempSync(join(tmpdir(), 'ov-chain-'));
const failures = [];
function check(cond, what) {
	console.log((cond ? 'ok   ' : 'FAIL ') + what);
	if (!cond) failures.push(what);
}

const abi = new Interface([
	'event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value)',
	'event TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values)',
	'function castleLevel(uint256 tokenId) view returns (uint256)',
	'function balanceOfBatch(address[] accounts, uint256[] ids) view returns (uint256[])',
	'function supportsInterface(bytes4 interfaceId) view returns (bool)',
]);
const multicall = new Interface([
	'function aggregate3((address target, bool allowFailure, bytes callData)[] calls) payable returns ((bool success, bytes returnData)[] returnData)',
]);
const MULTICALL3 = '0xca11bde05977b3631167028862be2a173976ca11';
let multicalls = 0;
const CONTRACT = '0x118aed2606d02c2545c6d7d2d1021e567cc08922';
const ZERO = '0x' + '0'.repeat(40);
const [alice, bob, carol, dave] = [1, 2, 3, 4].map(() => Wallet.createRandom().address.toLowerCase());
const id = a => BigInt(a);
const hex = a => a.toLowerCase();

// The stand-in chain: events, castle levels, and a head block
let head = 14600000;
const events = [];   // { block, single: [from, to, id] } or { block, batch: [from, to, ids] }
function single(block, from, to, tokenAddr) { events.push({ block, single: [from, to, id(tokenAddr)] }); }
function batch(block, from, to, tokenAddrs) { events.push({ block, batch: [from, to, tokenAddrs.map(id)] }); }
single(14100000, ZERO, alice, alice);              // Alice reveals her land
single(14100500, ZERO, bob, bob);                  // Bob reveals his
single(14200000, alice, carol, alice);             // Alice sells hers to Carol
single(14300000, ZERO, dave, dave);                // Dave reveals; no land in the world
batch(14400000, bob, carol, [bob]);                // Bob sells his to Carol, in a batch
const levels = { [alice]: 3n, [bob]: 9n, [dave]: 0n };

let getLogsCalls = 0, refused = 0, historyExpired = false, transferPages = 0;
const rpc = http.createServer((req, res) => {
	let body = '';
	req.on('data', c => body += c);
	req.on('end', () => {
		const one = r => {
			if (r.method === 'eth_blockNumber') return { result: '0x' + head.toString(16) };
			if (r.method === 'eth_getLogs') {
				getLogsCalls++;
				const f = r.params[0];
				const from = parseInt(f.fromBlock, 16), to = parseInt(f.toBlock, 16);
				if (to - from + 1 > 50000) { refused++; return { error: { code: -32701, message: 'block range too large' } }; }
				if (historyExpired && from < 15537394) return { error: { code: -32000, message: 'history expired' } };
				if (f.address.toLowerCase() !== CONTRACT) return { result: [] };
				const logs = [];
				events.forEach((e, i) => {
					if (e.block < from || e.block > to) return;
					const log = e.single
						? abi.encodeEventLog('TransferSingle', [e.single[0], e.single[0], e.single[1], e.single[2], 1n])
						: abi.encodeEventLog('TransferBatch', [e.batch[0], e.batch[0], e.batch[1], e.batch[2], e.batch[2].map(() => 1n)]);
					logs.push({ ...log, address: CONTRACT, blockNumber: '0x' + e.block.toString(16),
						logIndex: '0x' + i.toString(16), transactionHash: '0x' + String(i).padStart(64, '0'), removed: false });
				});
				return { result: logs };
			}
			if (r.method === 'alchemy_getAssetTransfers') {
				// Alchemy's transfers API, two transfers a page
				const q = r.params[0];
				const from = parseInt(q.fromBlock, 16), to = parseInt(q.toBlock, 16);
				if (q.contractAddresses[0].toLowerCase() !== CONTRACT || q.category[0] !== 'erc1155') return { result: { transfers: [] } };
				const all = [];
				events.forEach((e, i) => {
					if (e.block < from || e.block > to) return;
					const [f, t, ids] = e.single ? [e.single[0], e.single[1], [e.single[2]]] : e.batch;
					const hash = '0x' + String(i).padStart(64, '0');
					all.push({ blockNum: '0x' + e.block.toString(16), uniqueId: `${hash}:log:${i}`, hash,
						from: f, to: t, category: 'erc1155',
						erc1155Metadata: ids.map(x => ({ tokenId: '0x' + x.toString(16).padStart(64, '0'), value: '0x1' })) });
				});
				const startAt = parseInt(q.pageKey || '0', 10);
				const page = all.slice(startAt, startAt + 2);
				transferPages++;
				return { result: { transfers: page, ...(startAt + 2 < all.length ? { pageKey: String(startAt + 2) } : {}) } };
			}
			if (r.method === 'eth_call' && r.params[0].to.toLowerCase() === MULTICALL3) {
				multicalls++;
				const calls = multicall.decodeFunctionData('aggregate3', r.params[0].data)[0];
				const out = calls.map(c => {
					if (c.target.toLowerCase() !== CONTRACT) return [false, '0x'];
					const inner = one({ method: 'eth_call', params: [{ to: CONTRACT, data: c.callData }, 'latest'] });
					return [true, inner.result];
				});
				return { result: multicall.encodeFunctionResult('aggregate3', [out]) };
			}
			if (r.method === 'eth_call') {
				const tx = abi.parseTransaction({ data: r.params[0].data });
				if (!tx) return { result: '0x' + '0'.repeat(64) };   // owner() and the like
				if (tx.name === 'castleLevel') {
					return { result: abi.encodeFunctionResult('castleLevel', [levels[hex('0x' + tx.args[0].toString(16).padStart(40, '0'))] || 0n]) };
				}
				if (tx.name === 'supportsInterface') return { result: abi.encodeFunctionResult('supportsInterface', [true]) };
				if (tx.name === 'balanceOfBatch') {
					// Who holds what after all events
					const holder = {};
					for (const e of events) {
						const [f, t, ids] = e.single ? [e.single[0], e.single[1], [e.single[2]]] : e.batch;
						for (const i of ids) holder[i.toString()] = t;
					}
					const [accounts, ids] = tx.args;
					return { result: abi.encodeFunctionResult('balanceOfBatch',
						[accounts.map((a, i) => holder[ids[i].toString()] === a.toLowerCase() ? 1n : 0n)]) };
				}
			}
			return { error: { code: -32601, message: 'no such method' } };
		};
		const req1 = JSON.parse(body);
		const out = Array.isArray(req1)
			? req1.map(r => ({ jsonrpc: '2.0', id: r.id, ...one(r) }))
			: { jsonrpc: '2.0', id: req1.id, ...one(req1) };
		res.writeHead(200, { 'content-type': 'application/json' });
		res.end(JSON.stringify(out));
	});
});
await new Promise(r => rpc.listen(0, '127.0.0.1', r));

// Two lands in the world: Alice's and Bob's tokens
const lands = {
	'1:1': { name: 'Aliceholm', token: alice, owner_snapshot: alice },
	'2:2': { name: 'Bobmark', token: bob, owner_snapshot: bob },
};
writeFileSync(join(dir, 'lands.json'), JSON.stringify({ lands }));

const env = {
	...process.env,
	OV_ETH_RPC: `http://127.0.0.1:${rpc.address().port}`,
	OV_CHAIN_DIR: join(dir, 'chain'),
	OV_LANDS: join(dir, 'lands.json'),
	OV_CHAIN_FROM_BLOCK: '14000000',   // a node with full history
	NODE_NO_WARNINGS: '1',
};
const cwd = new URL('..', import.meta.url).pathname;

function runNode(args, extraEnv = {}, killAfterMs = 0) {
	return new Promise(resolve => {
		const p = spawn(process.execPath, args, { cwd, env: { ...env, ...extraEnv }, stdio: ['ignore', 'pipe', 'pipe'] });
		let out = '';
		p.stdout.on('data', d => out += d);
		p.stderr.on('data', d => out += d);
		if (killAfterMs) setTimeout(() => p.kill(), killAfterMs);
		p.on('exit', code => resolve({ code, out }));
	});
}

try {
	// First run: the whole history
	let r = await runNode(['chain.js', '--once']);
	check(r.code === 0, 'first run finishes');

	check(refused > 0, `ranges the endpoint refuses are split (${refused} refused, ${getLogsCalls} eth_getLogs)`);
	const tokens = JSON.parse(readFileSync(join(dir, 'chain', 'tokens.json'), 'utf8'));
	check(tokens.block === head - 64, 'indexed to 64 blocks behind the head');
	check(tokens.tokens[alice].holder === carol, 'a sold token is held by the buyer');
	check(tokens.tokens[bob].holder === carol, 'a token sold in a TransferBatch is held by the buyer');
	check(tokens.tokens[dave].holder === dave, 'a revealed token is held by its revealer');
	check(tokens.tokens[bob].level === 9 && tokens.tokens[bob].realm === 'futuristic', 'level 9 is a futuristic castle');
	check(multicalls === 1, `castle levels read through one Multicall3 call (${multicalls})`);
	check(tokens.tokens[alice].revealed === 14100000, 'reveal block recorded');
	check(/3 held by 2 wallets/.test(r.out) && /1 new lands placed \(1 in all\)/.test(r.out),
		'the log sums up tokens, holders and new lands');
	const nl0 = JSON.parse(readFileSync(join(dir, 'chain', 'new-lands.json'), 'utf8')).lands;
	check(nl0['0:0'] && nl0['0:0'].token === dave, 'a token without land gets one: the first free cell of the spiral');
	const ll = JSON.parse(readFileSync(join(dir, 'chain', 'land-levels.json'), 'utf8')).levels;
	check(ll['1:1'] === 3 && ll['2:2'] === 9 && ll['0:0'] === 0, 'land-levels.json: every land\'s current level, new lands included');
	const old = JSON.parse(readFileSync(join(dir, 'chain', 'token-data.json'), 'utf8'));
	check(old.length === 3 && old.some(t => t[0] === carol && t[1] === '3' && t[2] === alice && t[3] === '14100000'),
		'token-data.json in the old [holder, level, tokenId, block] format');

	// Crests: a castle (level 1 to 7 in either realm) gets one; a plain one
	// below castle level 4
	check(Number.isInteger(tokens.tokens[bob].crest) && tokens.tokens[bob].crest >= 2808, `castle level 1 (level 9): a plain crest (${tokens.tokens[bob].crest})`);
	check(Number.isInteger(tokens.tokens[alice].crest) && tokens.tokens[alice].crest >= 2808, `castle level 3: a plain crest (${tokens.tokens[alice].crest})`);
	check(tokens.tokens[dave].crest === null, 'no castle: no crest');
	check(/2 crests given, 0 upgraded/.test(r.out), 'the log counts crests given');

	// Second run: only what is new
	const callsBefore = getLogsCalls;
	head += 1000;
	single(14600500, carol, dave, alice);      // Carol sells Aliceholm to Dave
	levels[alice] = 11n;                       // and Dave flips its realm (no event)
	r = await runNode(['chain.js', '--once']);
	const tokens2 = JSON.parse(readFileSync(join(dir, 'chain', 'tokens.json'), 'utf8'));
	check(r.code === 0 && getLogsCalls - callsBefore <= 2, `second run reads only new blocks (${getLogsCalls - callsBefore} eth_getLogs)`);
	check(tokens2.tokens[alice].holder === dave && tokens2.tokens[alice].level === 11, 'a new sale and a changed level are picked up');
	check(/1 new transfers/.test(r.out) && /1 levels changed/.test(r.out), 'the log counts new transfers and changed levels');

	const db = new DatabaseSync(join(dir, 'chain', 'orthoverse-chain.sqlite'), { readOnly: true });
	check(db.prepare('SELECT count(*) AS n FROM transfers').get().n === 6, 'every transfer is kept in the database');
	check(db.prepare("SELECT has_land FROM tokens WHERE token_id = ?").get(dave).has_land === 1 &&
		db.prepare("SELECT land_key FROM placements WHERE token_id = ?").get(dave).land_key === '0:0', 'the placement is in the database');
	db.close();

	// Castle level 4: the plain crest is swapped for one with an animal
	{
		const before = JSON.parse(readFileSync(join(dir, 'chain', 'tokens.json'), 'utf8')).tokens;
		levels[bob] = 12n;
		r = await runNode(['chain.js', '--once']);
		const after = JSON.parse(readFileSync(join(dir, 'chain', 'tokens.json'), 'utf8')).tokens;
		check(after[bob].crest < 2808 && after[bob].crest !== before[bob].crest && /0 crests given, 1 upgraded/.test(r.out),
			`castle level 4: an animal crest instead (${before[bob].crest} -> ${after[bob].crest})`);
		check(after[alice].crest === before[alice].crest, 'other crests stay as they are');
		const db2 = new DatabaseSync(join(dir, 'chain', 'orthoverse-chain.sqlite'), { readOnly: true });
		const n = db2.prepare('SELECT count(*) AS n, count(DISTINCT crest) AS d FROM crests').get();
		db2.close();
		check(n.n === n.d, 'no crest is used twice');
		levels[bob] = 9n;
	}

	// A database for another contract is refused
	r = await runNode(['chain.js', '--once'], { OV_CONTRACT: '0x' + '1'.repeat(40) });
	check(r.code === 1 && /is for contract/.test(r.out), 'refuses to mix contracts in one database');

	// New lands, with the real lands file: tokens revealed after the world's
	// lands were fixed get the next cells of the old spiral, for good
	{
		const real = new URL('../../../mods/orthoverse_lands/data/lands.json', import.meta.url).pathname;
		const fixed = JSON.parse(readFileSync(real, 'utf8'));
		const saved = events.splice(0);
		const savedHead = head;
		const erin = Wallet.createRandom().address.toLowerCase();
		const fred = Wallet.createRandom().address.toLowerCase();
		head = 16000000;
		single(15900000, ZERO, erin, erin);
		single(15900100, ZERO, fred, fred);
		const dir5 = join(dir, 'chain5');
		r = await runNode(['chain.js', '--once'], { OV_LANDS: real, OV_CHAIN_FROM_BLOCK: '', OV_CHAIN_DIR: dir5 });
		const nl = JSON.parse(readFileSync(join(dir5, 'new-lands.json'), 'utf8')).lands;
		const keys = Object.keys(nl);
		check(r.code === 0 && keys.length === 2, `two new lands placed (${keys.join(', ')})`);
		check(nl['-7:4'] && nl['-7:4'].token === erin, 'the first goes to -7:4, the next free cell of the old spiral');
		const other = keys.find(k => k !== '-7:4');
		check(other && !fixed.lands[other] && !fixed.seas.includes(other) && nl[other].token === fred,
			`the second goes to the next free cell (${other}), not on a land or a planned sea`);
		const { landName } = await import('../names.js');
		check(nl['-7:4'].name === landName(erin) && /^The Orthoverse (Croft|Land) of /.test(nl['-7:4'].description),
			`named as load-tokens.js named lands (${nl['-7:4'].name})`);
		check(/2 new lands placed/.test(r.out) && !/still without land/.test(r.out), 'the log says so');
		// Stays put
		head += 10;
		r = await runNode(['chain.js', '--once'], { OV_LANDS: real, OV_CHAIN_FROM_BLOCK: '', OV_CHAIN_DIR: dir5 });
		const nl2 = JSON.parse(readFileSync(join(dir5, 'new-lands.json'), 'utf8')).lands;
		check(JSON.stringify(Object.keys(nl2).sort()) === JSON.stringify(keys.sort()) && /0 new lands placed \(2 in all\)/.test(r.out),
			'a placed land stays where it is');
		events.splice(0, events.length, ...saved);
		head = savedHead;
	}

	// The auth service checks the indexed holders instead of the 2023 snapshot
	r = await runNode(['server.js'], {
		OV_AUTH_PORT: '18091', OV_AUTH_HOST: '127.0.0.1', OV_AUTH_SECRET: 'x'.repeat(40),
		OV_DATA_DIR: join(dir, 'auth'), OV_AUTH_DB: join(dir, 'none.sqlite'),
		OV_CHAIN_TOKENS: join(dir, 'chain', 'tokens.json'),
	}, 2500);
	const owners = JSON.parse(readFileSync(join(dir, 'auth', 'owners.json'), 'utf8'));
	check(/2 of 2 held as the chain index \(block \d+\) says/.test(r.out), 'auth: holders come from the chain index');
	check(owners.owners[alice] === dave && owners.owners[bob] === carol, 'auth: owners.json has the current holders');
	// Alchemy: the transfers API, a page at a time, from before V2
	r = await runNode(['chain.js', '--once'], { OV_CHAIN_FROM_BLOCK: '', OV_CHAIN_METHOD: 'transfers', OV_CHAIN_DIR: join(dir, 'chain4') });
	const t4 = JSON.parse(readFileSync(join(dir, 'chain4', 'tokens.json'), 'utf8'));
	const t1 = JSON.parse(readFileSync(join(dir, 'chain', 'tokens.json'), 'utf8'));
	check(r.code === 0 && transferPages >= 3 && /alchemy_getAssetTransfers/.test(r.out),
		`transfers API: read in pages (${transferPages})`);
	check(JSON.stringify(Object.keys(t4.tokens).sort().map(k => [k, t4.tokens[k].holder, t4.tokens[k].revealed])) ===
		JSON.stringify(Object.keys(t1.tokens).sort().map(k => [k, t1.tokens[k].holder, t1.tokens[k].revealed])),
		'transfers API: the same holders and reveal blocks as eth_getLogs, batch transfer included');

	// A node without pre-Merge history: start from the 2023 snapshot at the Merge
	historyExpired = true;
	head = 15700000;
	single(15600000, dave, bob, alice);        // after the Merge, Dave sells Aliceholm to Bob
	r = await runNode(['chain.js', '--once'], { OV_CHAIN_FROM_BLOCK: '', OV_CHAIN_DIR: join(dir, 'chain2') });
	const t3 = JSON.parse(readFileSync(join(dir, 'chain2', 'tokens.json'), 'utf8'));
	check(r.code === 0 && !/failed/.test(r.out), 'from the Merge, no pre-Merge logs are asked for');
	check(t3.tokens[bob].holder === bob, 'a land with no transfer since the Merge keeps its snapshot holder');
	check(t3.tokens[alice].holder === bob, 'a land sold since the Merge has its new holder');
	check(!t3.tokens[dave], 'a token without land revealed before the Merge is not known (no history)');
	r = await runNode(['chain.js', '--once'], { OV_CHAIN_DIR: join(dir, 'chain3') });   // 14000000 again
	check(r.code === 1 && /may not keep history that old/.test(r.out), 'refused old history is explained');
	historyExpired = false;


	// Running for good: asked to index now (after a reveal), it does not wait
	// for the next daily run
	{
		const req = join(dir, 'index-now');
		const p = spawn(process.execPath, ['chain.js'], { cwd, stdio: ['ignore', 'pipe', 'pipe'],
			env: { ...env, OV_CHAIN_REQUEST: req, OV_CHAIN_REQUEST_GAP_MS: '0', OV_CHAIN_REQUEST_POLL_MS: '200' } });
		let out = '';
		p.stdout.on('data', d => out += d);
		p.stderr.on('data', d => out += d);
		const runs = () => (out.match(/chain indexed to block/g) || []).length;
		for (let i = 0; i < 100 && runs() < 1; i++) await new Promise(r2 => setTimeout(r2, 100));
		await new Promise(r2 => setTimeout(r2, 600));
		check(runs() === 1, 'running for good: one run, then it waits');
		writeFileSync(req, 'now');
		for (let i = 0; i < 100 && runs() < 2; i++) await new Promise(r2 => setTimeout(r2, 100));
		check(runs() === 2 && /asked to index now/.test(out), 'asked to index now: a second run straight away');
		await new Promise(r2 => setTimeout(r2, 800));
		check(runs() === 2, 'the same request is not taken twice');
		p.kill();
	}
} catch (e) {
	failures.push('exception: ' + e.stack);
	console.log(e);
} finally {
	rpc.close();
}

if (failures.length) {
	console.log(`${failures.length} FAILED`);
	process.exit(1);
}
console.log('all passed');
