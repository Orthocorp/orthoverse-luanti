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

let getLogsCalls = 0, refused = 0;
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
			if (r.method === 'eth_call') {
				const tx = abi.parseTransaction({ data: r.params[0].data });
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
	check(tokens.tokens[alice].revealed === 14100000, 'reveal block recorded');
	check(/2 held by 2 wallets|3 held by 2 wallets/.test(r.out) && /1 tokens have no land/.test(r.out),
		'the log sums up tokens, holders and tokens without land');
	const old = JSON.parse(readFileSync(join(dir, 'chain', 'token-data.json'), 'utf8'));
	check(old.length === 3 && old.some(t => t[0] === carol && t[1] === '3' && t[2] === alice && t[3] === '14100000'),
		'token-data.json in the old [holder, level, tokenId, block] format');

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
	check(db.prepare("SELECT has_land FROM tokens WHERE token_id = ?").get(dave).has_land === 0, 'a token without land is marked');
	db.close();

	// A database for another contract is refused
	r = await runNode(['chain.js', '--once'], { OV_CONTRACT: '0x' + '1'.repeat(40) });
	check(r.code === 1 && /is for contract/.test(r.out), 'refuses to mix contracts in one database');

	// The auth service checks the indexed holders instead of the 2023 snapshot
	r = await runNode(['server.js'], {
		OV_AUTH_PORT: '18091', OV_AUTH_HOST: '127.0.0.1', OV_AUTH_SECRET: 'x'.repeat(40),
		OV_DATA_DIR: join(dir, 'auth'), OV_AUTH_DB: join(dir, 'none.sqlite'),
		OV_CHAIN_TOKENS: join(dir, 'chain', 'tokens.json'),
	}, 2500);
	const owners = JSON.parse(readFileSync(join(dir, 'auth', 'owners.json'), 'utf8'));
	check(/2 of 2 held as the chain index \(block \d+\) says/.test(r.out), 'auth: holders come from the chain index');
	check(owners.owners[alice] === dave && owners.owners[bob] === carol, 'auth: owners.json has the current holders');
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
