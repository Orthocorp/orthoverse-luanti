// End-to-end test of the auth service, against a stand-in Ethereum endpoint and
// a stand-in game account database. Run: npm test (from web/auth).

import http from 'node:http';
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { Wallet, Interface } from 'ethers';

const dir = mkdtempSync(join(tmpdir(), 'ov-auth-'));
const failures = [];
function check(cond, what) {
	console.log((cond ? 'ok   ' : 'FAIL ') + what);
	if (!cond) failures.push(what);
}

// Three lands; the first two belong to the test wallet, the third to someone else
const alice = Wallet.createRandom();
const bob = Wallet.createRandom();
const carol = Wallet.createRandom();   // a 2023 owner who never signs in
const lands = {
	'1:2': { name: 'Aliceholm', token: '0x00000000000000000000000000000000000000a1', owner_snapshot: carol.address },
	'3:4': { name: 'Alicemark', token: '0x00000000000000000000000000000000000000a2' },
	'5:6': { name: 'Elsewhere', token: '0x00000000000000000000000000000000000000b1' },
	'7:8': { name: 'Carolby', token: '0x00000000000000000000000000000000000000c1', owner_snapshot: carol.address },
};
writeFileSync(join(dir, 'lands.json'), JSON.stringify({ lands }));
// Who holds each token on the stand-in chain (Aliceholm was Carol's in 2023)
const holder = {
	'0xa1': alice.address, '0xa2': alice.address, '0xb1': bob.address, '0xc1': carol.address,
};
const erc1155 = new Interface([
	'function balanceOfBatch(address[] accounts, uint256[] ids) view returns (uint256[])',
	'function supportsInterface(bytes4 interfaceId) view returns (bool)',
	'function castleLevel(uint256 tokenId) view returns (uint256)',
	'function revealedTokenIds(uint256 tokenId) view returns (bool)',
]);
// A newcomer who reveals their own token during the test
const dave = Wallet.createRandom();
const revealed = new Set();
// Castle levels on the stand-in chain
const castle = { '0xa1': 3n };

// A game account database with one existing player
const db = new DatabaseSync(join(dir, 'auth.sqlite'));
db.exec('CREATE TABLE auth (id INTEGER PRIMARY KEY, name VARCHAR(32) UNIQUE, password VARCHAR(512), last_login INTEGER)');
db.prepare('INSERT INTO auth (name, password, last_login) VALUES (?, ?, 0)').run('Keirtest', '#1#x#y');
db.close();

// Stand-in Ethereum JSON-RPC endpoint: an ERC-1155 answering balanceOfBatch
let rpcCalls = 0;
const rpc = http.createServer((req, res) => {
	let body = '';
	req.on('data', c => body += c);
	req.on('end', () => {
		const batch = JSON.parse(body);
		rpcCalls += batch.length;
		const out = batch.map(r => {
			const tx = erc1155.parseTransaction({ data: r.params[0].data });
			if (!tx) return { jsonrpc: '2.0', id: r.id, result: '0x' + '0'.repeat(64) };   // owner() and the like
			if (tx.name === 'revealedTokenIds') {
				return { jsonrpc: '2.0', id: r.id, result: erc1155.encodeFunctionResult('revealedTokenIds', [revealed.has(tx.args[0])]) };
			}
			if (tx.name === 'castleLevel') {
				return { jsonrpc: '2.0', id: r.id, result: erc1155.encodeFunctionResult('castleLevel', [castle['0x' + tx.args[0].toString(16)] || 0n]) };
			}
			if (tx.name === 'supportsInterface') {
				return { jsonrpc: '2.0', id: r.id, result: erc1155.encodeFunctionResult('supportsInterface', [true]) };
			}
			const [accounts, ids] = tx.args;
			const bal = accounts.map((a, i) =>
				(holder['0x' + ids[i].toString(16)] || '').toLowerCase() === a.toLowerCase() ? 1n : 0n);
			return { jsonrpc: '2.0', id: r.id, result: erc1155.encodeFunctionResult('balanceOfBatch', [bal]) };
		});
		res.writeHead(200, { 'content-type': 'application/json' });
		res.end(JSON.stringify(out));
	});
});
await new Promise(r => rpc.listen(0, '127.0.0.1', r));

// The service
const PORT = 18090;
const svc = spawn(process.execPath, ['server.js'], {
	cwd: new URL('..', import.meta.url).pathname,
	env: {
		...process.env,
		OV_AUTH_PORT: String(PORT), OV_AUTH_HOST: '127.0.0.1',
		OV_AUTH_SECRET: 'x'.repeat(40),
		OV_AUTH_RATE: '200',
		OV_DATA_DIR: join(dir, 'data'),
		OV_AUTH_DB: join(dir, 'auth.sqlite'),
		OV_LANDS: join(dir, 'lands.json'),
		OV_CHAIN_TOKENS: join(dir, 'no-chain-index.json'),
		OV_CHAIN_NEW_LANDS: join(dir, 'new-lands.json'),
		OV_ETH_RPC: `http://127.0.0.1:${rpc.address().port}`,
		NODE_NO_WARNINGS: '1',
	},
	stdio: ['ignore', 'pipe', 'pipe'],
});
let svcLog = '';
svc.stdout.on('data', d => svcLog += d);
svc.stderr.on('data', d => svcLog += d);
await new Promise(r => setTimeout(r, 1500));

const base = `http://127.0.0.1:${PORT}`;
let cookie = '';
async function call(method, path, body, headers = {}) {
	const res = await fetch(base + path, {
		method,
		headers: {
			...(body ? { 'content-type': 'application/json' } : {}),
			...(cookie ? { cookie } : {}),
			host: 'orthoverse.land',
			...headers,
		},
		body: body ? JSON.stringify(body) : undefined,
	});
	const set = res.headers.get('set-cookie');
	if (set) cookie = set.split(';')[0].replace(/^ov_session=$/, '');
	return { status: res.status, body: await res.json(), setCookie: set };
}

try {
	// Ownership indexed at start-up
	const owners = JSON.parse(readFileSync(join(dir, 'data', 'owners.json'), 'utf8'));
	check(owners.owners[lands['7:8'].token] === carol.address.toLowerCase(), 'owners.json: a land still with its 2023 owner');
	check(owners.owners[lands['1:2'].token] === null, 'owners.json: a land sold since 2023 to a wallet that has not signed in');
	check(/1 of 4 held as the 2023 snapshot says/.test(svcLog), 'without a chain index, the 2023 snapshot is checked');
	check(/is an ERC-1155/.test(svcLog), 'the contract is checked to be an ERC-1155');

	let r = await call('GET', '/auth/me');
	check(r.body.signedIn === false, 'not signed in at first');

	// Sign in
	r = await call('GET', '/auth/nonce?address=' + alice.address);
	// (fetch cannot set Host, so the domain is the address the test uses)
	check(r.status === 200 && r.body.message.startsWith(`127.0.0.1:${PORT} wants you to sign in with your Ethereum account:\n` + alice.address) &&
		/\nChain ID: 1\n/.test(r.body.message) && /\nURI: http:\/\/127\.0\.0\.1:/.test(r.body.message),
		'sign-in message is EIP-4361 for this domain and address');
	const { nonce, message } = r.body;

	r = await call('POST', '/auth/verify', { nonce, signature: await bob.signMessage(message) });
	check(r.status === 400 && /not from the wallet/.test(r.body.error), 'a signature by another wallet is refused');

	r = await call('GET', '/auth/nonce?address=' + alice.address);
	const n2 = r.body;
	r = await call('POST', '/auth/verify', { nonce: n2.nonce, signature: await alice.signMessage(n2.message) },
		{ 'x-forwarded-proto': 'https' });
	check(r.status === 200 && r.body.signedIn && r.body.name === null, 'signed in, no name yet');
	check(/HttpOnly/.test(r.setCookie) && /SameSite=Strict/.test(r.setCookie) && /Secure/.test(r.setCookie),
		'session cookie is HttpOnly, SameSite=Strict, Secure over https');
	check(r.body.lands.length === 2, 'on signing in, the wallet\'s lands are looked up at once: both listed');
	check(r.body.lands.every(l => /^0x[0-9a-f]+$/.test(l.token)), 'each of them with its token ID (for the lands page)');
	const owners2 = JSON.parse(readFileSync(join(dir, 'data', 'owners.json'), 'utf8'));
	check(owners2.owners[lands['1:2'].token] === alice.address.toLowerCase(), 'owners.json: Aliceholm now shows the player\'s wallet');
	check(owners2.owners[lands['5:6'].token] === null, 'owners.json: a land held by a wallet that has not signed in');

	r = await call('POST', '/auth/verify', { nonce: n2.nonce, signature: await alice.signMessage(n2.message) });
	check(r.status === 400, 'a sign-in request cannot be used twice');

	// Choosing a name
	for (const [bad, why] of [['ab', 'too short'], ['has space', 'space'], ['Guest-123', 'Guest prefix'],
		['keirtest', 'existing game account, other capitals']]) {
		r = await call('POST', '/auth/name', { name: bad });
		check(r.status === 400, `name refused: ${why} (${r.body.error})`);
	}
	r = await call('POST', '/auth/name', { name: 'Alice_1' });
	check(r.status === 200 && r.body.name === 'Alice_1' && /^[0-9a-f]{32}$/.test(r.body.password) && r.body.exists === false,
		'name chosen; a game password is given; no game account yet');
	const password = r.body.password;
	r = await call('POST', '/auth/name', { name: 'Other' });
	check(r.status === 400, 'a wallet cannot choose a second name');

	const reg = JSON.parse(readFileSync(join(dir, 'data', 'registry.json'), 'utf8'));
	check(reg.players.alice_1 && reg.players.alice_1.address === alice.address.toLowerCase(), 'registry.json has the name and wallet');

	r = await call('GET', '/auth/me');
	check(r.body.name === 'Alice_1' && r.body.password === password, 'the session remembers the player; same password each time');

	// Arriving where you click on the map: the admin and level 7 holders
	r = await call('GET', '/auth/me');
	check(r.body.canVisit === false, 'visit: not for a holder without a level 7 land');
	r = await call('POST', '/auth/visit', { x: 100, z: -50 });
	check(r.status === 403, 'visit refused for them');
	castle['0xa2'] = 7n;
	await call('POST', '/api/levels/check', { key: '3:4' });
	r = await call('GET', '/auth/me');
	check(r.body.canVisit === true, 'visit: allowed once a land they hold is level 7');
	r = await call('POST', '/auth/visit', { x: 100.4, z: -50 });
	check(r.status === 200 && r.body.x === 100 && r.body.z === -50, 'visit recorded (rounded to a node)');
	const vis = JSON.parse(readFileSync(join(dir, 'data', 'visits.json'), 'utf8')).visits.alice_1;
	check(vis && vis.name === 'Alice_1' && vis.x === 100 && Number.isInteger(vis.t), 'visits.json for the game: name, place, time');
	r = await call('POST', '/auth/visit', { x: 999999, z: 0 });
	check(r.status === 400, 'a spot outside the world is refused');

	// Another wallet cannot take the name
	const saved = cookie;
	cookie = '';
	r = await call('GET', '/auth/nonce?address=' + bob.address);
	r = await call('POST', '/auth/verify', { nonce: r.body.nonce, signature: await bob.signMessage(r.body.message) });
	r = await call('POST', '/auth/name', { name: 'ALICE_1' });
	check(r.status === 400, 'another wallet cannot take the same name in other capitals');
	cookie = saved;

	// A forged session
	const forged = cookie.replace(/\.[A-Za-z0-9_-]+$/, '.AAAA');
	r = await call('GET', '/auth/me', null, { cookie: forged });
	check(r.body.signedIn === false, 'a tampered session cookie is ignored');

	// Guests: whether their account exists
	r = await call('GET', '/auth/exists?name=Keirtest');
	check(r.body.exists === true, 'exists: an existing account');
	r = await call('GET', '/auth/exists?name=Guest-ABC123');
	check(r.body.exists === false, 'exists: a new guest');

	r = await call('POST', '/auth/logout', {});
	check(/Max-Age=0/.test(r.setCookie), 'signing out clears the cookie');
	r = await call('GET', '/auth/status');
	check(r.body.players === 1 && r.body.ownersUpdated && !r.body.ownersError, 'status: one player, ownership current');

	// After an upgrade on the lands page: the level read from the contract,
	// written where the game reads it
	const aKey = '1:2';   // Aliceholm, token 0xa1
	r = await call('POST', '/api/levels/check', { key: aKey });
	check(r.status === 200 && r.body.level === 3, 'level check: read from the contract (3)');
	const fresh = JSON.parse(readFileSync(join(dir, 'data', 'levels.json'), 'utf8'));
	check(fresh.levels[aKey].level === 3 && /^\d{4}-\d\d-\d\dT/.test(fresh.levels[aKey].checked), 'levels.json for the game: level and when it was checked');
	castle['0xa1'] = 4n;
	const before = rpcCalls;
	r = await call('POST', '/api/levels/check', { key: aKey });
	check(r.body.level === 3 && r.body.cached && rpcCalls === before, 'a second check within 15 seconds is answered without asking the chain');
	r = await call('POST', '/api/levels/check', { key: 'nowhere' });
	check(r.status === 404, 'level check: an unknown land is refused');

	// Revealing a land on the lands page
	r = await call('POST', '/api/reveal/check', { address: dave.address });
	check(r.status === 200 && r.body.revealed === false, 'reveal check: not revealed yet');
	check(!existsSync(join(dir, 'data', 'index-now')), 'and the chain service is not asked to index');
	revealed.add(BigInt(dave.address));
	holder['0x' + BigInt(dave.address).toString(16)] = dave.address;
	r = await call('POST', '/api/reveal/check', { address: dave.address });
	check(r.body.revealed === true && existsSync(join(dir, 'data', 'index-now')), 'revealed: the chain service is asked to index now');
	r = await call('GET', '/api/reveal/status?address=' + dave.address);
	check(r.body.placed === null, 'status: no land yet');
	writeFileSync(join(dir, 'new-lands.json'), JSON.stringify({ lands: { '9:9': { name: 'Daveholm', token: dave.address.toLowerCase(), level: 0 } } }));
	r = await call('GET', '/api/reveal/status?address=' + dave.address);
	check(r.body.placed && r.body.placed.key === '9:9' && r.body.placed.name === 'Daveholm', 'status: the land, once the chain service has placed it');
	const own3 = JSON.parse(readFileSync(join(dir, 'data', 'owners.json'), 'utf8'));
	check(own3.owners[dave.address.toLowerCase()] === dave.address.toLowerCase(), 'and its holder noted at once (checked on the contract)');
	r = await call('GET', '/api/reveal/status?address=' + carol.address);
	check(r.body.placed === null, 'status for an address with no land: none');

} catch (e) {
	failures.push('exception: ' + e.stack);
	console.log(e);
} finally {
	svc.kill();
	rpc.close();
}

if (failures.length) {
	console.log('\nservice log:\n' + svcLog);
	console.log(`${failures.length} FAILED`);
	process.exit(1);
}
console.log('all passed');
