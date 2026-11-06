// Test of the token metadata API (/api/metadata/), with stand-in lands, chain
// index and Ethereum endpoint. Run: npm test (from web/auth).

import http from 'node:http';
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { PNG } from 'pngjs';

const dir = mkdtempSync(join(tmpdir(), 'ov-meta-'));
const failures = [];
function check(cond, what) {
	console.log((cond ? 'ok   ' : 'FAIL ') + what);
	if (!cond) failures.push(what);
}

const OWNER = '0x2830B5a3b5242BC2c64C390594ED971E7deD47D2';
const KING = '0x60515c2da6c76ef0b092534fa5be84b07e4da689';   // a kingdom with a crest
const CROFT = '0x8f626958ec428d258f6481b563126640f8aef54e';  // no castle
const ZEROS = '0x00ab0c3d1e2f30415263748596a7b8c9dae0f102';  // ID starts with a zero byte
const NEWBIE = '0x5c3a9e7d10f2b84c6a0e93d7215fb8a4c09e6d31'; // a new land
const WAITING = '0x1111111111111111111111111111111111111111'; // revealed, not placed yet

writeFileSync(join(dir, 'lands.json'), JSON.stringify({
	format: 1, land_size: 96, map_radius: 56,
	lands: {
		'12:-3': { token: KING, name: 'Fangwanina', level: 7, crest: '7030.png' },
		'-1:-2': { token: CROFT, name: 'Isnataly', level: 0, crest: null },
		'4:4': { token: ZEROS, name: 'Zeroland', level: 0, crest: null },
	},
	henges: {}, seas: [],
}));
writeFileSync(join(dir, 'new-lands.json'), JSON.stringify({
	format: 1, lands: { '-7:4': { token: NEWBIE, name: 'Urtilotland', level: 1, crest: '9000.png' } },
}));
writeFileSync(join(dir, 'tokens.json'), JSON.stringify({
	block: 1, tokens: {
		[KING]: { holder: OWNER.toLowerCase(), level: 15, realm: 'futuristic', revealed: 13992468, crest: 7030 },
		[CROFT]: { holder: CROFT, level: 0, realm: 'fantasy', revealed: 13993499, crest: null },
		[NEWBIE]: { holder: NEWBIE, level: 1, realm: 'fantasy', revealed: 26000000, crest: 9000 },
		[WAITING]: { holder: WAITING, level: 4, realm: 'fantasy', revealed: 26000001, crest: 15 },
	},
}));

// Stand-in Ethereum endpoint: owner(), and nothing else of interest
const rpc = http.createServer((req, res) => {
	let body = '';
	req.on('data', c => body += c);
	req.on('end', () => {
		const out = JSON.parse(body).map(r => {
			const data = r.params[0].data;
			if (data === '0x8da5cb5b') return { jsonrpc: '2.0', id: r.id, result: '0x' + OWNER.slice(2).toLowerCase().padStart(64, '0') };
			return { jsonrpc: '2.0', id: r.id, result: '0x' + '0'.repeat(64) };
		});
		res.writeHead(200, { 'content-type': 'application/json' });
		res.end(JSON.stringify(out));
	});
});
await new Promise(r => rpc.listen(0, '127.0.0.1', r));

const PORT = 18092;
const svc = spawn(process.execPath, ['server.js'], {
	cwd: new URL('..', import.meta.url).pathname,
	env: {
		...process.env,
		OV_AUTH_PORT: String(PORT), OV_AUTH_HOST: '127.0.0.1', OV_AUTH_SECRET: 'x'.repeat(40),
		OV_DATA_DIR: join(dir, 'data'), OV_AUTH_DB: join(dir, 'none.sqlite'),
		OV_LANDS: join(dir, 'lands.json'), OV_CHAIN_TOKENS: join(dir, 'tokens.json'),
		OV_CHAIN_NEW_LANDS: join(dir, 'new-lands.json'),
		OV_ETH_RPC: `http://127.0.0.1:${rpc.address().port}`, OV_PUBLIC_URL: 'https://orthoverse.land',
		NODE_NO_WARNINGS: '1',
	},
	stdio: ['ignore', 'pipe', 'pipe'],
});
let svcLog = '';
svc.stdout.on('data', d => svcLog += d);
svc.stderr.on('data', d => svcLog += d);
await new Promise(r => setTimeout(r, 2000));

const base = `http://127.0.0.1:${PORT}/api/metadata/`;
async function get(path) {
	const res = await fetch(base + path);
	const type = res.headers.get('content-type') || '';
	return {
		status: res.status, headers: res.headers,
		body: type.startsWith('application/json') ? await res.json() : Buffer.from(await res.arrayBuffer()),
	};
}
const attr = (j, name) => (j.attributes.find(a => a.trait_type === name) || {}).value;

try {
	let r = await get('contract.json');
	check(r.status === 200 && r.body.name === 'The Orthoverse Land Collection' && r.body.seller_fee_basis_points === 250 &&
		r.body.fee_recipient === OWNER && r.body.external_link === 'https://orthoverse.land',
		'contract.json: name, 2.5% royalty to the contract owner, link');
	check(r.headers.get('access-control-allow-origin') === '*', 'open to any site (CORS)');

	// As uri() writes it: hex ID, a dash, the castle level then
	r = await get(`${KING}-7.json`);
	const k = r.body;
	check(k.name === 'Fangwanina' && /^The Orthoverse Nation of Fangwanina, land 12:-3 of the Orthoverse\./.test(k.description),
		`a land: name, and the description from the current level (15: Nation), not the URL's (${k.description})`);
	check(attr(k, 'Realm') === 'Futuristic' && attr(k, 'Title') === 'Nation' && attr(k, 'Castle level') === 7 &&
		attr(k, 'Coordinates') === '12:-3' && attr(k, 'Land') === 'Original' && attr(k, 'Revealed in block') === 13992468,
		'attributes: realm, title, castle level, coordinates, original land, reveal block');
	check(typeof attr(k, 'Crest') === 'string' && attr(k, 'Crest').length > 3, `the crest's blazon (${attr(k, 'Crest')})`);
	check(k.image === 'https://orthoverse.land/api/metadata/crest/7030-crown.png', 'a kingdom shows its crest under a crown');
	check(k.external_url === 'https://orthoverse.land/map/#12:-3', 'links to the land on the map');
	check(typeof attr(k, 'Terrain') === 'string' && Number.isInteger(attr(k, 'Lakes')), `terrain (${attr(k, 'Terrain')}, ${attr(k, 'Lakes')} lakes)`);

	r = await get(`${CROFT}-0.json`);
	check(r.body.image === 'https://orthoverse.land/map/lands/-1_-2.png' && attr(r.body, 'Crest') === undefined,
		'a land without a castle shows the picture of the land');

	r = await get('0xab0c3d1e2f30415263748596a7b8c9dae0f102-0.json');
	check(r.body.name === 'Zeroland', 'an ID with leading zero bytes (as uri() writes it) finds its land');

	r = await get(`${NEWBIE}-1.json`);
	check(r.body.name === 'Urtilotland' && attr(r.body, 'Land') === 'New' && attr(r.body, 'Coordinates') === '-7:4' &&
		r.body.image.endsWith('/crest/9000-none.png'), 'a new land, with its crest and no headgear at castle level 1');

	r = await get(`${WAITING}-4.json`);
	check(attr(r.body, 'Status') === 'Awaiting placement' && r.body.image.endsWith('/crest/15-baron.png'),
		'a revealed token whose land is not placed yet, with a baron at level 4');

	r = await get('0x000000000000000000000000000000000000dead-0.json');
	check(r.body.name === 'Unrevealed Orthoverse land' && attr(r.body, 'Status') === 'Unrevealed',
		'any other address: an unrevealed land');

	// Pictures
	r = await get('crest/7030-crown.png');
	const png = PNG.sync.read(r.body);
	const alpha = (x, y) => png.data[(y * png.width + x) * 4 + 3];
	check(r.status === 200 && png.width === 320 && png.height === 512, 'crest picture: 320 x 512');
	let top = 0, shield = 0;
	for (let y = 0; y < 112; y++) for (let x = 0; x < 320; x++) if (alpha(x, y)) top++;
	for (let y = 112; y < 512; y++) for (let x = 0; x < 320; x++) if (alpha(x, y)) shield++;
	check(top > 1000 && shield > 50000, 'the crown above, the shield below');
	check(/immutable/.test(r.headers.get('cache-control')), 'crest pictures are cached for good');
	const plain = PNG.sync.read((await get('crest/7030-none.png')).body);
	let topPlain = 0;
	for (let y = 0; y < 112; y++) for (let x = 0; x < 320; x++) if (plain.data[(y * 320 + x) * 4 + 3]) topPlain++;
	check(topPlain === 0, 'no headgear: nothing above the shield');
	r = await get('crest/9173-none.png');
	check(r.status === 404, 'a crest that does not exist: 404');
	r = await get('nonsense');
	check(r.status === 404, 'anything else: 404');
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
