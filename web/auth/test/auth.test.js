// End-to-end test of the auth service, against a stand-in Ethereum endpoint and
// a stand-in game account database. Run: npm test (from web/auth).

import http from 'node:http';
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { Wallet, Interface } from 'ethers';
import { srpVerifier } from '../srp.js';

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
let rpcCalls = 0, balanceCalls = 0;
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
			balanceCalls++;
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

// Stand-in Cloudflare Turnstile: the token "good" passes
const turnstile = http.createServer((req, res) => {
	let body = '';
	req.on('data', c => body += c);
	req.on('end', () => {
		const f = new URLSearchParams(body);
		res.writeHead(200, { 'content-type': 'application/json' });
		res.end(JSON.stringify({ success: f.get('secret') === 'ts-secret' && f.get('response') === 'good' }));
	});
});
await new Promise(r => turnstile.listen(0, '127.0.0.1', r));

// The service
const PORT = 18090;
const svcEnv = {
	OV_AUTH_PORT: String(PORT), OV_AUTH_HOST: '127.0.0.1',
	OV_AUTH_SECRET: 'x'.repeat(40),
	OV_AUTH_RATE: '200',
	OV_DATA_DIR: join(dir, 'data'),
	OV_AUTH_DB: join(dir, 'auth.sqlite'),
	OV_LANDS: join(dir, 'lands.json'),
	OV_CHAIN_TOKENS: join(dir, 'no-chain-index.json'),
	OV_CHAIN_NEW_LANDS: join(dir, 'new-lands.json'),
	OV_ETH_RPC: `http://127.0.0.1:${rpc.address().port}`,
	OV_TURNSTILE_SITEKEY: 'ts-site', OV_TURNSTILE_SECRET: 'ts-secret',
	OV_TURNSTILE_URL: `http://127.0.0.1:${turnstile.address().port}/`,
	OV_REGISTER_PER_DAY: '3',
	OV_ADVENTURES: join(dir, 'adventures.json'),
	OV_ADMIN: 'Bossy',
	NODE_NO_WARNINGS: '1',
};
const svc = spawn(process.execPath, ['server.js'], {
	cwd: new URL('..', import.meta.url).pathname,
	env: { ...process.env, ...svcEnv },
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
	check(r.status === 200 && r.body.name === 'Alice_1' && r.body.password === undefined && r.body.exists === false,
		'name chosen; no game password given out with it; no game account yet');
	{
		const before = JSON.parse(readFileSync(join(dir, 'data', 'registry.json'), 'utf8')).players.alice_1;
		check(/^#1#/.test(before.srp || '') && before.issued === undefined, 'a new character: a record of a password nobody knows, not for entry');
	}
	// Entering the game: a fresh password for that one entry
	r = await call('POST', '/auth/play', {});
	check(r.status === 200 && r.body.name === 'Alice_1' && /^[0-9a-f]{32}$/.test(r.body.password) && r.body.exists === false,
		'play: a fresh game password');
	const password = r.body.password;
	r = await call('POST', '/auth/name', { name: 'Other' });
	check(r.status === 400, 'a wallet cannot choose a second name');

	const reg = JSON.parse(readFileSync(join(dir, 'data', 'registry.json'), 'utf8'));
	check(reg.players.alice_1 && reg.players.alice_1.address === alice.address.toLowerCase(), 'registry.json has the name and wallet');
	{
		// The game makes the account from this, so it must be the record of the
		// password the player was given (same salt, same verifier)
		const srp = reg.players.alice_1.srp || '';
		const salt = Buffer.from(srp.split('#')[2] || '', 'base64');
		check(/^#1#[A-Za-z0-9+/]+=*#[A-Za-z0-9+/]+=*$/.test(srp) && salt.length === 16 &&
			srpVerifier('Alice_1', password, salt) === srp, "registry.json has the game account's password record");
		const issued = reg.players.alice_1.issued;
		check(Number.isInteger(issued) && Math.abs(issued - Date.now() / 1000) < 60, 'and when it was made, for the game to let it in once');
	}

	r = await call('GET', '/auth/me');
	check(r.body.name === 'Alice_1' && r.body.password === undefined, 'the session remembers the player; me gives no password');
	r = await call('POST', '/auth/play', {});
	check(r.status === 200 && r.body.password !== password, 'play again: another password, the last one is dead');
	{
		const srp2 = JSON.parse(readFileSync(join(dir, 'data', 'registry.json'), 'utf8')).players.alice_1.srp;
		const salt2 = Buffer.from(srp2.split('#')[2], 'base64');
		check(srpVerifier('Alice_1', r.body.password, salt2) === srp2 && srpVerifier('Alice_1', password, salt2) !== srp2,
			'registry.json: only the new password\'s record');
	}

	// Arriving where you click on the map: the admin and level 7 holders
	r = await call('GET', '/auth/me');
	check(r.body.canVisit === false, 'visit: not for a holder without a level 7 land');
	r = await call('POST', '/auth/visit', { x: 100, z: -50 });
	check(r.status === 403, 'visit refused for them');
	// ...but any character may arrive at an open adventure's entrance
	writeFileSync(join(dir, 'adventures.json'), JSON.stringify({ adventures: [
		{ key: '0:1', name: "St Morwen's", open: true }, { key: '2:2', name: 'Shut', open: false }] }));
	r = await call('POST', '/auth/visit', { adventure: '0:1' });
	check(r.status === 200 && r.body.adventure === '0:1', 'adventure visit recorded without a level 7 land');
	const av = JSON.parse(readFileSync(join(dir, 'data', 'visits.json'), 'utf8')).visits.alice_1;
	check(av && av.adventure === '0:1' && av.x === undefined && Number.isInteger(av.t), 'visits.json: the adventure, no spot');
	r = await call('POST', '/auth/visit', { adventure: '2:2' });
	check(r.status === 404, 'a closed adventure is refused');
	r = await call('POST', '/auth/visit', { adventure: '9:9' });
	check(r.status === 404, 'a land with no adventure is refused');
	r = await call('POST', '/auth/visit', { adventure: '../x' });
	check(r.status === 400, 'a key that is not a land key is refused');
	r = await call('POST', '/auth/visit', { adventure: { toString: 1 } });
	check(r.status === 400, 'a key that is not a string is refused');
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

	// The skin: a design, painted here; crowns from castle level 7 (Alice has one now)
	r = await call('GET', '/auth/skin');
	check(r.status === 200 && r.body.design === null && r.body.level === 7, `skin: none yet; castle level 7 (${r.body.level})`);
	const look = { skin: '#d49e7a', eyes: 'large', eye: '#64c5ce', hair: 2, hairc: '#bc3b15', beard: 0, beardc: '#000000',
		top: 3, topc: '#2e6b2a', pants: 1, pantsc: '#4d311f', boots: 2, bootsc: '#222222', acc: [13, 0] };
	r = await call('POST', '/auth/skin', { design: look });
	check(r.status === 200 && /^[0-9a-f]{16}$/.test(r.body.hash) && r.body.design.acc.join() === '0,13',
		'skin saved, a gold crown and armbands, tidied');
	{
		const { PNG } = await import('pngjs');
		const png = PNG.sync.read(readFileSync(join(dir, 'data', 'skins', 'alice_1.png')));
		const e = JSON.parse(readFileSync(join(dir, 'data', 'registry.json'), 'utf8')).players.alice_1;
		check(png.width === 64 && png.height === 32 && e.skin && e.skin.h === r.body.hash && e.skin.d.top === 3,
			'skins/alice_1.png (64 x 32) for the game, its hash and the design in registry.json');
	}
	r = await call('GET', '/auth/skin');
	check(r.body.design && r.body.design.hairc === '#bc3b15', 'skin: the design comes back');
	for (const [bad, why] of [[{ ...look, skin: 'red' }, 'a colour that is not #rrggbb'], [{ ...look, hair: 99 }, 'no such hair'],
		[{ ...look, acc: [99] }, 'no such accessory'], [null, 'no design'], [{ ...look, acc: '13' }, 'accessories not a list']]) {
		r = await call('POST', '/auth/skin', { design: bad });
		check(why === 'accessories not a list' ? r.status === 200 && r.body.design.acc.length === 0 : r.status === 400,
			`skin: ${why} (${r.status} ${r.body.error || ''})`);
	}

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

	// Password characters
	cookie = '';
	r = await call('GET', '/auth/config');
	check(r.body.turnstile === 'ts-site', 'config: the Turnstile site key for the registration form');
	r = await call('POST', '/auth/register', { name: 'Pat', password: 'short', turnstile: 'good' });
	check(r.status === 400 && /at least 8/.test(r.body.error), 'register: a short password is refused');
	r = await call('POST', '/auth/register', { name: 'alice_1', password: 'long enough pw', turnstile: 'good' });
	check(r.status === 400 && /taken/.test(r.body.error), 'register: a wallet character\'s name is taken');
	r = await call('POST', '/auth/register', { name: 'Pat', password: 'pat', turnstile: 'good' });
	check(r.status === 400, 'register: the password cannot be the name (and is too short)');
	r = await call('POST', '/auth/register', { name: 'BOSSY', password: 'correct horse', turnstile: 'good' });
	check(r.status === 400 && /kept for the admin/.test(r.body.error), "register: the admin's name (any capitals) is kept for the admin");
	r = await call('POST', '/auth/register', { name: 'Pat', password: 'correct horse', turnstile: 'bad' });
	check(r.status === 400 && /robot/.test(r.body.error), 'register: a failed Turnstile check is refused');
	r = await call('POST', '/auth/register', { name: 'Pat', password: 'correct horse', turnstile: 'good' });
	check(r.status === 200 && r.body.name === 'Pat' && r.body.password === undefined &&
		r.body.hasPassword && !r.body.hasWallet && r.body.address === null && r.body.lands.length === 0,
		'register: a character with a name and password, no wallet');
	check(/^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$/.test(r.body.recoveryCode || ''), 'register: a recovery code is shown once');
	const patCode = r.body.recoveryCode;
	check(/HttpOnly/.test(r.setCookie), 'register: signed in at once');
	r = await call('GET', '/auth/me');
	check(r.body.name === 'Pat' && r.body.signedInWith === 'password', 'me: the password character');
	r = await call('POST', '/auth/play', {});
	const patGame = r.body.password;
	check(r.status === 200 && /^[0-9a-f]{32}$/.test(patGame || ''), 'play: a password character gets a game password too');
	r = await call('GET', '/auth/skin');
	check(r.status === 200 && r.body.level === 0, 'skin: no wallet, castle level 0');
	r = await call('POST', '/auth/skin', { design: { skin: '#d49e7a', eyes: 'small', eye: '#64c5ce', hair: 1, hairc: '#000000',
		beard: 1, beardc: '#000000', top: 1, topc: '#000000', pants: 1, pantsc: '#000000', boots: 1, bootsc: '#000000', acc: [11] } });
	check(r.status === 400 && /level 7/.test(r.body.error), 'skin: a crown needs a castle at level 7');
	const regP = JSON.parse(readFileSync(join(dir, 'data', 'registry.json'), 'utf8')).players.pat;
	check(regP && regP.name === 'Pat' && !regP.address && regP.pw && regP.rc &&
		!JSON.stringify(regP).includes('correct horse') && !JSON.stringify(regP).includes(patCode.replace(/-/g, '')),
		'registry.json: the character, with only hashes of the password and code');
	{
		const salt = Buffer.from((regP.srp || '').split('#')[2] || '', 'base64');
		check(salt.length === 16 && srpVerifier('Pat', patGame, salt) === regP.srp, "and its game account's password record");
	}

	await call('POST', '/auth/logout', {});
	r = await call('POST', '/auth/login', { name: 'pat', password: 'wrong password' });
	check(r.status === 400 && /do not match/.test(r.body.error), 'login: a wrong password is refused');
	r = await call('POST', '/auth/login', { name: '__proto__', password: 'x' });
	check(r.status === 400 && /do not match/.test(r.body.error), 'login: a name like __proto__ is just an unknown name');
	r = await call('POST', '/auth/login', { name: 'PAT', password: 'correct horse' });
	check(r.status === 200 && r.body.name === 'Pat' && r.body.signedInWith === 'password', 'login: name in any capitals and the password');
	r = await call('POST', '/auth/login', { name: 'Alice_1', password: 'anything at all' });
	check(r.status === 400 && /wallet/.test(r.body.error), 'login: a wallet character without a password is told to use the wallet');

	// Changing the password ends the other sessions
	const oldPatCookie = cookie;
	r = await call('POST', '/auth/password', { password: 'battery staple' });
	check(r.status === 400 && /current password/.test(r.body.error), 'password: the current one is needed');
	r = await call('POST', '/auth/password', { current: 'correct horse', password: 'battery staple' });
	check(r.status === 200 && r.body.recoveryCode === null, 'password: changed (the recovery code stays as it was)');
	r = await call('GET', '/auth/me', null, { cookie: oldPatCookie });
	check(r.body.signedIn === false, 'password: a session from before the change no longer works');
	r = await call('GET', '/auth/me');
	check(r.body.name === 'Pat', 'password: this browser stays signed in');

	// Recovery
	cookie = '';
	r = await call('POST', '/auth/recover', { name: 'Pat', code: 'AAAA-BBBB-CCCC-DDDD', password: 'new password 1' });
	check(r.status === 400, 'recover: a wrong code is refused');
	r = await call('POST', '/auth/recover', { name: 'Pat', code: patCode.toLowerCase().replace(/-/g, ' '), password: 'new password 1' });
	check(r.status === 200 && r.body.name === 'Pat' && r.body.recoveryCode && r.body.recoveryCode !== patCode,
		'recover: the code (any capitals and spacing) sets a new password, and a new code is given');
	r = await call('POST', '/auth/recover', { name: 'Pat', code: patCode, password: 'new password 2' });
	check(r.status === 400, 'recover: the old code no longer works');
	cookie = '';
	r = await call('POST', '/auth/login', { name: 'Pat', password: 'new password 1' });
	check(r.status === 200, 'recover: the new password works');

	// Linking a wallet to the password character
	const erin = Wallet.createRandom();
	r = await call('GET', '/auth/nonce?address=' + alice.address);
	r = await call('POST', '/auth/link', { nonce: r.body.nonce, signature: await alice.signMessage(r.body.message) });
	check(r.status === 400 && /already belongs/.test(r.body.error), 'link: a wallet that has a character already is refused');
	r = await call('GET', '/auth/nonce?address=' + erin.address);
	const ln = r.body;
	r = await call('POST', '/auth/link', { nonce: ln.nonce, signature: await bob.signMessage(ln.message) });
	check(r.status === 400, 'link: a signature by another wallet is refused');
	r = await call('GET', '/auth/nonce?address=' + erin.address);
	r = await call('POST', '/auth/link', { nonce: r.body.nonce, signature: await erin.signMessage(r.body.message) });
	check(r.status === 200 && r.body.hasWallet && r.body.address === erin.address && r.body.name === 'Pat', 'link: the wallet is linked');
	const regP2 = JSON.parse(readFileSync(join(dir, 'data', 'registry.json'), 'utf8')).players.pat;
	check(regP2.address === erin.address.toLowerCase() && regP2.pw, 'registry.json: the character now has the wallet and keeps its password');
	cookie = '';
	r = await call('GET', '/auth/nonce?address=' + erin.address);
	r = await call('POST', '/auth/verify', { nonce: r.body.nonce, signature: await erin.signMessage(r.body.message) });
	check(r.status === 200 && r.body.name === 'Pat' && r.body.signedInWith === 'wallet',
		'link: signing in with the wallet now gives the same character');

	// A wallet character adds a password (no current one needed: the wallet proves it)
	cookie = '';
	r = await call('GET', '/auth/nonce?address=' + alice.address);
	r = await call('POST', '/auth/verify', { nonce: r.body.nonce, signature: await alice.signMessage(r.body.message) });
	r = await call('POST', '/auth/password', { password: 'alice password' });
	check(r.status === 200 && r.body.hasPassword && /^[A-Z2-9-]{19}$/.test(r.body.recoveryCode || ''),
		'a wallet character adds a password, and gets a recovery code');
	cookie = '';
	r = await call('POST', '/auth/login', { name: 'Alice_1', password: 'alice password' });
	check(r.status === 200 && r.body.name === 'Alice_1' && r.body.lands.length === 2,
		'and can then sign in with it, lands and all');

	// Registration limit per address per day (3 in this test; Pat was the first)
	cookie = '';
	r = await call('POST', '/auth/register', { name: 'Quin', password: 'quin password', turnstile: 'good' });
	check(r.status === 200, 'register: a second character from the same address');
	cookie = '';
	r = await call('POST', '/auth/register', { name: 'Rex', password: 'rex password', turnstile: 'good' });
	cookie = '';
	r = await call('POST', '/auth/register', { name: 'Sam', password: 'sam password', turnstile: 'good' });
	check(r.status === 429 && /tomorrow/.test(r.body.error), 'register: the fourth in a day from one address is refused');

	// Too many wrong passwords for one name
	for (let i = 0; i < 10; i++) await call('POST', '/auth/login', { name: 'Quin', password: 'nope nope' + i });
	r = await call('POST', '/auth/login', { name: 'Quin', password: 'quin password' });
	check(r.status === 429, 'login: after 10 wrong passwords the name rests, even for the right one');

	// With a chain index: holders come from it, and only the lands it says a
	// player's wallet holds are asked about. Alicemark has gone to Bob since
	// the index was written.
	svc.kill();
	await new Promise(r => setTimeout(r, 300));
	holder['0xa2'] = bob.address;
	writeFileSync(join(dir, 'chain-index.json'), JSON.stringify({
		updated: new Date().toISOString(), block: 23000000, tokens: {
			'0x00000000000000000000000000000000000000a1': { holder: alice.address },
			'0x00000000000000000000000000000000000000a2': { holder: alice.address },
			'0x00000000000000000000000000000000000000b1': { holder: bob.address },
			'0x00000000000000000000000000000000000000c1': { holder: carol.address },
		},
	}));
	const idxBefore = balanceCalls;
	let log2 = '';
	const svc2 = spawn(process.execPath, ['server.js'], {
		cwd: new URL('..', import.meta.url).pathname,
		env: { ...process.env, ...svcEnv, OV_AUTH_PORT: String(PORT + 5), OV_CHAIN_TOKENS: join(dir, 'chain-index.json') },
		stdio: ['ignore', 'pipe', 'pipe'],
	});
	svc2.stdout.on('data', d => log2 += d);
	svc2.stderr.on('data', d => log2 += d);
	await new Promise(r => setTimeout(r, 1500));
	svc2.kill();
	const o2 = JSON.parse(readFileSync(join(dir, 'data', 'owners.json'), 'utf8')).owners;
	const lc = a => a.toLowerCase();
	check(o2['0x00000000000000000000000000000000000000a1'] === lc(alice.address) &&
		o2['0x00000000000000000000000000000000000000a2'] === null &&
		o2['0x00000000000000000000000000000000000000b1'] === lc(bob.address) &&
		o2['0x00000000000000000000000000000000000000c1'] === lc(carol.address),
		'chain index: holders from it, a player\'s land sold since then caught');
	check(/1 lands held by player wallets \(checked with 1 request; 1 no longer held\)/.test(log2) && balanceCalls - idxBefore === 1,
		`chain index: one request for the player's two lands, none for the rest (${balanceCalls - idxBefore})`);
	if (failures.length) svcLog += '\n--- with the chain index:\n' + log2;

} catch (e) {
	failures.push('exception: ' + e.stack);
	console.log(e);
} finally {
	svc.kill();
	rpc.close();
	turnstile.close();
}

if (failures.length) {
	console.log('\nservice log:\n' + svcLog);
	console.log(`${failures.length} FAILED`);
	process.exit(1);
}
console.log('all passed');
