// Asking OpenSea to refresh the metadata of lands whose metadata has changed.
//
// What a land's token shows (its name, castle level, title, crest, and its
// picture, which the map service draws again under a new name whenever the
// land changes) comes from metadata.js. Every so often (OV_OPENSEA_EVERY_MIN,
// 20 minutes) this compares each land's metadata with what OpenSea was last
// asked to show, and asks OpenSea to refresh the ones that differ, through
// its API (OV_OPENSEA_KEY). Without a key it does nothing at all.
//
// The first run only notes what every land shows (a complete collection
// refresh is done by hand, on OpenSea, as the collection's owner); after that
// only changes are sent.
//
// Keeping within OpenSea's limits:
// - each run sends at most PER_RUN refreshes, one every SPACING ms, and stops
//   while OpenSea's own count of calls left (X-RateLimit-Remaining) is low;
//   what is left waits in the queue for the next run;
// - "too many" (429): wait as long as OpenSea says (Retry-After), then go on;
// - a refused key (401, 403): stop for KEY_PAUSE, and say so;
// - OpenSea down or failing (5xx, no answer) three times running: stop for
//   BREAK_PAUSE, then try again;
// - a token OpenSea does not know (404): noted as sent, not asked again
//   until it changes.
// The queue and what was sent are kept in a file, so a restart loses nothing
// and sends nothing twice.

import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, renameSync } from 'node:fs';

const PER_RUN = 60;
const SPACING = 1500;            // ms between refreshes
const RESERVE = 5;               // calls left at which a run stops
const KEY_PAUSE = 6 * 3600e3;
const BREAK_PAUSE = 3600e3;
const FAILS_TO_BREAK = 3;

// What a land's metadata says, as a short hash (the description and
// attributes carry the level, title and crest; the image is the picture)
export function fingerprint(json) {
	const { name, description, image, attributes } = json || {};
	return createHash('sha256').update(JSON.stringify([name, description, image, attributes])).digest('hex').slice(0, 16);
}

export function createOpenSea({
	apiKey, contract, stateFile, tokens, tokenJson, log = () => {},
	baseUrl = 'https://api.opensea.io', chain = 'ethereum', everyMs = 20 * 60e3,
	spacingMs = SPACING, perRun = PER_RUN, now = () => Date.now(), fetchFn = fetch,
}) {
	const on = typeof apiKey === 'string' && apiKey.trim() !== '';
	let state;
	try {
		state = JSON.parse(readFileSync(stateFile, 'utf8'));
	} catch (e) {
		state = null;
	}
	if (!state || typeof state !== 'object' || typeof state.sent !== 'object' || !Array.isArray(state.queue)) {
		state = { format: 1, sent: null, queue: [], pausedUntil: 0, why: null, fails: 0, refreshed: 0, lastRun: null,
			lastError: null, limit: null, remaining: null, reset: null };
	}
	const save = () => {
		const tmp = stateFile + '.tmp';
		writeFileSync(tmp, JSON.stringify(state));
		renameSync(tmp, stateFile);
	};
	const sleep = ms => new Promise(r => setTimeout(r, ms));
	let running = false, timer = null;

	function pause(ms, why) {
		state.pausedUntil = now() + ms;
		state.why = why;
		log('opensea: paused ' + Math.round(ms / 60e3) + ' min: ' + why);
	}

	// Ask OpenSea to refresh one token's metadata. Returns 'ok', 'skip' (OpenSea
	// does not know it), 'stop' (stop this run; the token stays queued) or
	// 'retry' (failed; it stays queued)
	async function refresh(token) {
		const id = BigInt(token).toString();
		const url = `${baseUrl}/api/v2/chain/${chain}/contract/${contract}/nfts/${id}/refresh`;
		let res;
		try {
			res = await fetchFn(url, {
				method: 'POST',
				headers: { 'x-api-key': apiKey.trim(), accept: 'application/json' },
				signal: AbortSignal.timeout(20000),
			});
		} catch (e) {
			state.lastError = 'no answer: ' + e.message;
			return 'retry';
		}
		const h = name => res.headers.get(name);
		if (h('x-ratelimit-limit') !== null) state.limit = Number(h('x-ratelimit-limit'));
		if (h('x-ratelimit-remaining') !== null) state.remaining = Number(h('x-ratelimit-remaining'));
		if (h('x-ratelimit-reset') !== null) state.reset = h('x-ratelimit-reset');
		if (res.ok) { state.fails = 0; return 'ok'; }
		state.lastError = 'HTTP ' + res.status;
		if (res.status === 404) return 'skip';
		if (res.status === 429) {
			const s = Number(h('retry-after'));
			pause(Math.min(Math.max(Number.isFinite(s) ? s * 1000 : 60e3, 30e3), 3600e3), 'too many requests (429)');
			return 'stop';
		}
		if (res.status === 401 || res.status === 403) {
			pause(KEY_PAUSE, 'the API key was refused (' + res.status + '): check OV_OPENSEA_KEY');
			return 'stop';
		}
		return 'retry';
	}

	// One run: queue what changed, then send what the limits allow
	async function run() {
		if (!on || running) return;
		if (now() < state.pausedUntil) return;
		running = true;
		try {
			state.lastRun = new Date(now()).toISOString();
			const current = new Map();
			for (const t of tokens()) {
				try { current.set(t, fingerprint(tokenJson(t))); } catch (e) { /* skipped this time */ }
			}
			if (state.sent === null) {
				// The first run: what every land shows now (refreshed by hand)
				state.sent = Object.fromEntries(current);
				log(`opensea: noted ${current.size} lands as they are now; from here on, changes are sent`);
				save();
				return;
			}
			const queued = new Set(state.queue);
			for (const [t, fp] of current) {
				if (state.sent[t] !== fp && !queued.has(t)) { state.queue.push(t); queued.add(t); }
			}
			let sent = 0, left = null;    // calls left, as OpenSea said during this run
			while (state.queue.length && sent < perRun) {
				if (left !== null && left <= RESERVE) break;
				const t = state.queue[0];
				state.remaining = null;
				const r = await refresh(t);
				if (state.remaining !== null) left = state.remaining;
				if (r === 'stop') break;
				if (r === 'retry') {
					state.fails++;
					if (state.fails >= FAILS_TO_BREAK) {
						pause(BREAK_PAUSE, 'OpenSea is failing (' + state.lastError + ')');
						state.fails = 0;
						break;
					}
					state.queue.push(state.queue.shift());   // to the back; others first
				} else {
					state.queue.shift();
					state.sent[t] = current.get(t) || state.sent[t];
					if (r === 'ok') { state.refreshed++; sent++; }
				}
				save();
				if (state.queue.length) await sleep(spacingMs);
			}
			if (sent) log(`opensea: refreshed ${sent} lands; ${state.queue.length} waiting`);
			save();
		} finally {
			running = false;
		}
	}

	return {
		on,
		run,
		start() {
			if (!on) { log('opensea: no OV_OPENSEA_KEY, so OpenSea is not asked to refresh anything'); return; }
			log(`opensea: refreshing changed lands every ${Math.round(everyMs / 60e3)} minutes`);
			setTimeout(() => run().catch(e => log('opensea: ' + e.message)), 30e3).unref();
			timer = setInterval(() => run().catch(e => log('opensea: ' + e.message)), everyMs);
			timer.unref();
		},
		stop() { if (timer) clearInterval(timer); },
		status() {
			if (!on) return { on: false };
			return {
				on: true, lastRun: state.lastRun, waiting: state.queue.length, refreshed: state.refreshed,
				paused: now() < state.pausedUntil ? { until: new Date(state.pausedUntil).toISOString(), why: state.why } : null,
				lastError: state.lastError, limit: state.limit, remaining: state.remaining,
				noted: state.sent ? Object.keys(state.sent).length : 0,
			};
		},
	};
}
