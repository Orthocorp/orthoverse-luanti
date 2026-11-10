// Tests for opensea.js, against a stand-in OpenSea API.
//   node test/opensea.test.js
import http from 'node:http';
import { mkdtempSync, existsSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createOpenSea } from '../opensea.js';

const failures = [];
function check(ok, what) {
	console.log((ok ? 'ok   ' : 'FAIL ') + what);
	if (!ok) failures.push(what);
}
const dir = mkdtempSync(join(tmpdir(), 'ov-opensea-'));
const CONTRACT = '0x118aed2606d02c2545c6d7d2d1021e567cc08922';

// The stand-in OpenSea: answers each refresh as `answer` says
const calls = [];
let answer = () => ({ status: 200, headers: { 'x-ratelimit-limit': '30', 'x-ratelimit-remaining': '25', 'x-ratelimit-reset': '60' } });
const api = http.createServer((req, res) => {
	calls.push({ method: req.method, url: req.url, key: req.headers['x-api-key'] });
	const a = answer(req);
	res.writeHead(a.status, { 'content-type': 'application/json', ...(a.headers || {}) });
	res.end(JSON.stringify({ message: 'ok' }));
});
await new Promise(r => api.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${api.address().port}`;

// Three lands; what each shows can be changed
const T = ['0x' + 'a1'.padStart(40, '0'), '0x' + 'a2'.padStart(40, '0'), '0x' + 'b1'.padStart(40, '0')];
const shows = Object.fromEntries(T.map(t => [t, { name: 'Land ' + t.slice(-2), image: '/map/cards/' + t.slice(-2) + '-1.png', attributes: [] }]));
let clock = Date.parse('2026-11-10T12:00:00Z');
const make = (key, file = 'opensea.json', extra = {}) => createOpenSea({
	apiKey: key, contract: CONTRACT, stateFile: join(dir, file), tokens: () => T, tokenJson: t => shows[t],
	baseUrl: base, spacingMs: 0, now: () => clock, ...extra,
});

try {
	// Without a key: nothing at all
	const off = make('', 'off.json');
	await off.run();
	check(!off.on && calls.length === 0 && !existsSync(join(dir, 'off.json')), 'no key: OpenSea is not asked anything, no file kept');
	check(JSON.stringify(off.status()) === '{"on":false}', 'no key: the status says off');

	let os = make('secret-key');
	await os.run();
	check(calls.length === 0 && os.status().noted === 3, 'first run: only notes what the 3 lands show now');
	await os.run();
	check(calls.length === 0, 'nothing changed: nothing sent');

	// A land's picture changes
	shows[T[1]] = { ...shows[T[1]], image: '/map/cards/a2-2.png' };
	await os.run();
	check(calls.length === 1 && calls[0].method === 'POST' && calls[0].key === 'secret-key' &&
		calls[0].url === `/api/v2/chain/ethereum/contract/${CONTRACT}/nfts/${BigInt(T[1])}/refresh`,
		`a changed picture: one refresh, with the key, for that token (${calls[0] && calls[0].url})`);
	await os.run();
	check(calls.length === 1 && os.status().refreshed === 1 && os.status().waiting === 0, 'and not again');

	// Kept across a restart
	os = make('secret-key');
	await os.run();
	check(calls.length === 1 && os.status().noted === 3, 'after a restart: nothing sent twice, nothing noted afresh');

	// Too many requests: wait as long as OpenSea says
	shows[T[0]] = { ...shows[T[0]], attributes: [{ trait_type: 'Castle level', value: 3 }] };
	shows[T[2]] = { ...shows[T[2]], name: 'Renamed' };
	answer = () => ({ status: 429, headers: { 'retry-after': '120' } });
	await os.run();
	let st = os.status();
	check(calls.length === 2 && st.paused && /429/.test(st.paused.why) && st.waiting === 2, '429: paused, both changes still waiting');
	answer = () => ({ status: 200, headers: { 'x-ratelimit-remaining': '25', 'x-ratelimit-reset': '60' } });
	clock += 60e3;
	await os.run();
	check(calls.length === 2, 'still paused a minute later (OpenSea said two)');
	clock += 90e3;
	await os.run();
	check(calls.length === 4 && os.status().waiting === 0 && !os.status().paused, 'after the wait: both sent');

	// Few calls left: stop, the rest next run
	for (const t of T) shows[t] = { ...shows[t], image: shows[t].image + '?v2' };
	let n = 0;
	answer = () => ({ status: 200, headers: { 'x-ratelimit-remaining': String(++n === 1 ? 4 : 20), 'x-ratelimit-reset': '60' } });
	await os.run();
	check(calls.length === 5 && os.status().waiting === 2, 'few calls left (4): stops after one, two waiting');
	await os.run();
	check(calls.length === 7 && os.status().waiting === 0, 'the next run sends the rest');

	// OpenSea failing three times: a break of an hour
	for (const t of T) shows[t] = { ...shows[t], image: shows[t].image + '3' };
	answer = () => ({ status: 503 });
	await os.run();
	st = os.status();
	check(calls.length === 10 && st.paused && /failing/.test(st.paused.why) && st.waiting === 3, '503 three times: a break, all still waiting');
	answer = () => ({ status: 200 });
	clock += 30 * 60e3;
	await os.run();
	check(calls.length === 10, 'no calls during the break');
	clock += 31 * 60e3;
	await os.run();
	check(calls.length === 13 && os.status().waiting === 0, 'after it: all sent');

	// A refused key: stop for hours, say why
	shows[T[0]] = { ...shows[T[0]], name: 'Again' };
	answer = () => ({ status: 401 });
	await os.run();
	st = os.status();
	check(st.paused && /refused/.test(st.paused.why) && st.waiting === 1, '401: paused, the key named as the trouble');

	// A token OpenSea does not know: not asked again
	clock += 7 * 3600e3;
	answer = () => ({ status: 404 });
	await os.run();
	await os.run();
	check(calls.length === 15 && os.status().waiting === 0, '404: dropped, not asked again');

	const saved = JSON.parse(readFileSync(join(dir, 'opensea.json'), 'utf8'));
	check(!JSON.stringify(saved).includes('secret-key'), 'the key is never written to the file');
} catch (e) {
	failures.push('exception: ' + e.stack);
	console.log(e);
} finally {
	api.close();
}
if (failures.length) { console.log(failures.length + ' FAILED'); process.exit(1); }
console.log('all passed');
