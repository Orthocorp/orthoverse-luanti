// Orthoverse token metadata: what the contract's uri() and contractURI() point
// at, served under /api/metadata/ (set both of the contract's base URIs,
// setURI and setVoidURI, to <OV_PUBLIC_URL>/api/metadata/).
//
//   contract.json                  the collection (OpenSea's contractURI)
//   <0xtoken>-<level>.json         a token: uri(id) gives the token ID in hex
//                                  and its castle level at the time of asking
//   crest/<n>-<rank>.png           a crest, with its rank's headgear above it
//   classic/<0xtoken>-<level>[-unrevealed].png
//                                  the classic pixel-art picture of a token
//
// A placed land's picture is its card, drawn ahead by the map service from the
// world itself (map/cards/, see web/map/cards.py); tokens with no land to draw
// get the classic picture, unrevealed ones in grey.
//
// A token is a land of the world (lands.json, or new-lands.json from the chain
// service), a revealed token whose land is not placed yet, or (any other
// address) an unrevealed one. Levels, crests and reveal blocks come from the
// chain service's tokens.json; the land pictures are the map service's.

import { readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { PNG } from 'pngjs';
import { landName, landDescription, TITLES } from './names.js';
import { classicCard } from './classic.js';

// What each hex digit of a token makes of its 16 x 16 tile (as the mapgen draws it)
const TERRAIN = {
	0: 'Lush hills', 1: 'Lush mountains', 2: 'Lakes', 3: 'Plains', 4: 'Woods', 5: 'Lush plains',
	6: 'Quarries', 7: 'Evergreen forest', 8: 'Barren hills', 9: 'Barren mountains', a: 'Lakes',
	b: 'Desert', c: 'Woods', d: 'Badlands', e: 'Quarries', f: 'Woods',
};
const LAKE = '2a', MOUNTAIN = '19', FOREST = '47cf';

const OR = 2817;         // a plain gold shield: the collection
const SCALE = 16;        // crest pixels to image pixels

// A cached JSON file, read again when it changes
function watched(path) {
	let mtime = -1, value = null;
	return () => {
		let m;
		try { m = statSync(path).mtimeMs; } catch (e) { return value; }
		if (m !== mtime) {
			try { value = JSON.parse(readFileSync(path, 'utf8')); mtime = m; } catch (e) { /* keep the last */ }
		}
		return value;
	};
}

export function createMetadata({ landsFile, newLandsFile, tokensFile, cardsIndex, heraldryDir, publicUrl, royaltyRecipient }) {
	const BASE = publicUrl.replace(/\/+$/, '');
	const API = BASE + '/api/metadata';

	const fixed = JSON.parse(readFileSync(landsFile, 'utf8'));
	const byToken = new Map();   // 40-digit token -> { key, land, fixed }
	for (const [key, land] of Object.entries(fixed.lands)) {
		if (land.token) byToken.set(land.token.toLowerCase(), { key, land, fixed: true });
	}
	const newLands = watched(newLandsFile);
	const tokens = watched(tokensFile);
	const cards = watched(cardsIndex);

	function landOf(token) {
		const hit = byToken.get(token);
		if (hit) return hit;
		const nl = newLands();
		if (nl && nl.lands) {
			for (const [key, land] of Object.entries(nl.lands)) {
				if (land.token && land.token.toLowerCase() === token) {
					const entry = { key, land, fixed: false };
					byToken.set(token, entry);
					return entry;
				}
			}
		}
		return null;
	}

	// Heraldry: the sheet of crests, their blazons, and the headgear
	const heraldry = JSON.parse(readFileSync(join(heraldryDir, 'heraldry.json'), 'utf8'));
	const sheet = PNG.sync.read(readFileSync(join(heraldryDir, 'escutcheons.png')));
	const headgear = {};
	for (const r of ['crown', 'coronet', 'baron']) headgear[r] = PNG.sync.read(readFileSync(join(heraldryDir, r + '.png')));
	const missing = new Set(heraldry.missing);
	const images = new Map();

	function crestImage(n, r) {
		const k = n + '-' + r;
		if (images.has(k)) return images.get(k);
		const W = heraldry.width, H = heraldry.height, TOP = 7;
		const out = new PNG({ width: W * SCALE, height: (H + TOP) * SCALE });
		out.data.fill(0);
		const put = (src, sx, sy, dx, dy) => {
			const i = (sy * src.width + sx) * 4;
			if (src.data[i + 3] === 0) return;
			for (let y = 0; y < SCALE; y++) {
				for (let x = 0; x < SCALE; x++) {
					const o = (((dy * SCALE + y) * out.width) + dx * SCALE + x) * 4;
					out.data[o] = src.data[i]; out.data[o + 1] = src.data[i + 1];
					out.data[o + 2] = src.data[i + 2]; out.data[o + 3] = src.data[i + 3];
				}
			}
		};
		if (headgear[r]) {
			const g = headgear[r];
			for (let y = 0; y < g.height; y++) for (let x = 0; x < g.width; x++) put(g, x, y, x, y);
		}
		const cx = (n % heraldry.columns) * W, cy = Math.floor(n / heraldry.columns) * H;
		for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) put(sheet, cx + x, cy + y, x, y + TOP);
		const png = PNG.sync.write(out);
		if (images.size > 2000) images.clear();
		images.set(k, png);
		return png;
	}

	const crestUrl = (n, r) => `${API}/crest/${n}-${r}.png`;
	const classicUrl = (token, level, unrevealed) => `${API}/classic/${token}-${level}${unrevealed ? '-unrevealed' : ''}.png`;
	const classics = new Map();

	function terrain(token) {
		const tiles = token.slice(2, 38);
		const count = {};
		for (const ch of tiles) count[TERRAIN[ch]] = (count[TERRAIN[ch]] || 0) + 1;
		const main = Object.entries(count).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0][0];
		const n = set => [...tiles].filter(ch => set.includes(ch)).length;
		return { main, lakes: n(LAKE), mountains: n(MOUNTAIN), forests: n(FOREST) };
	}

	function tokenJson(token, urlLevel) {
		const t = (tokens() || { tokens: {} }).tokens[token];
		const hit = landOf(token);
		if (!hit && !t) {
			return {
				name: 'Unrevealed Orthoverse land',
				description: 'Every Ethereum address has an Orthoverse land, waiting to be revealed. ' +
					'Once revealed it takes its place in the Orthoverse, which you can explore at ' + BASE + '.',
				image: classicUrl(token, Number.isInteger(urlLevel) ? urlLevel % 16 : 0, true),
				external_url: BASE,
				attributes: [{ trait_type: 'Status', value: 'Unrevealed' }],
			};
		}
		const level = Number.isInteger(t?.level) ? t.level
			: Number.isInteger(urlLevel) ? urlLevel : (hit ? hit.land.level || 0 : 0);
		const castle = level % 8;
		const crest = t && Number.isInteger(t.crest) ? t.crest
			: hit && /^\d+\.png$/.test(hit.land.crest || '') ? parseInt(hit.land.crest, 10) : null;
		const name = hit ? hit.land.name : landName(token);
		const ter = terrain(token);
		const attributes = [
			{ trait_type: 'Realm', value: level >= 8 ? 'Futuristic' : 'Fantasy' },
			{ trait_type: 'Title', value: TITLES[level] || 'Land' },
			{ trait_type: 'Castle level', value: castle, display_type: 'number', max_value: 7 },
		];
		if (crest !== null && castle > 0 && !missing.has(crest)) {
			attributes.push({ trait_type: 'Crest', value: heraldry.blazons[String(crest)] || 'Crest ' + crest });
		}
		attributes.push(
			{ trait_type: 'Terrain', value: ter.main },
			{ trait_type: 'Lakes', value: ter.lakes, display_type: 'number', max_value: 36 },
			{ trait_type: 'Mountains', value: ter.mountains, display_type: 'number', max_value: 36 },
			{ trait_type: 'Forests', value: ter.forests, display_type: 'number', max_value: 36 },
		);
		if (hit) {
			attributes.push({ trait_type: 'Coordinates', value: hit.key },
				{ trait_type: 'Land', value: hit.fixed ? 'Original' : 'New' });
		} else {
			attributes.push({ trait_type: 'Status', value: 'Awaiting placement' });
		}
		if (t && Number.isInteger(t.revealed)) {
			attributes.push({ trait_type: 'Revealed in block', value: t.revealed, display_type: 'number' });
		}

		// The card the map service drew, or until there is one, the classic picture
		const card = hit && (cards() || {})[hit.key];
		const image = card && /^[-\w.]+\.png$/.test(card) ? `${BASE}/map/cards/${card}` : classicUrl(token, level % 16, false);

		const where = hit ? `, land ${hit.key} of the Orthoverse` : ', in the Orthoverse (its land is being placed)';
		return {
			name,
			description: landDescription(name, level) + where + '. Its holder can build on it in the game at ' + BASE + '/play/.',
			image,
			external_url: hit ? `${BASE}/map/#${hit.key}` : BASE,
			attributes,
		};
	}

	function contractJson() {
		const out = {
			name: 'The Orthoverse Land Collection',
			description: 'Every Ethereum address has a land in the Orthoverse. Revealed lands take their place on the ' +
				'map, with castles and crests as they are built up. Explore the world, and build on your own lands, at ' +
				BASE + '.',
			image: crestUrl(OR, 'crown'),
			external_link: BASE,
			seller_fee_basis_points: 250,
		};
		const r = royaltyRecipient();
		if (r) out.fee_recipient = r;
		return out;
	}

	function sendJson(res, status, body) {
		res.writeHead(status, {
			'content-type': 'application/json; charset=utf-8',
			'access-control-allow-origin': '*',
			'cache-control': status === 200 ? 'public, max-age=300' : 'no-store',
		});
		res.end(JSON.stringify(body, null, 1));
	}

	// Handles /api/metadata/...; returns false for anything else
	return function handle(req, res, url) {
		const path = url.pathname;
		if (!path.startsWith('/api/metadata/')) return false;
		if (req.method !== 'GET' && req.method !== 'HEAD') { sendJson(res, 405, { error: 'GET only' }); return true; }
		const rest = path.slice('/api/metadata/'.length);
		if (rest === 'contract.json') { sendJson(res, 200, contractJson()); return true; }
		let m = /^(0x[0-9a-fA-F]{1,64})(?:-(\d{1,3}))?\.json$/.exec(rest);
		if (m) {
			// uri() writes the ID without leading zero bytes: back to 40 digits
			const id = BigInt(m[1]);
			const token = '0x' + id.toString(16).padStart(40, '0');
			sendJson(res, 200, tokenJson(token, m[2] === undefined ? null : parseInt(m[2], 10)));
			return true;
		}
		m = /^classic\/(0x[0-9a-fA-F]{1,64})-(\d{1,2})(-unrevealed)?\.png$/.exec(rest);
		if (m) {
			const token = '0x' + BigInt(m[1]).toString(16).padStart(40, '0');
			const level = parseInt(m[2], 10) % 16;
			const k = token + '-' + level + (m[3] || '');
			let png = classics.get(k);
			if (!png) {
				png = classicCard(token, level, !!m[3]);
				if (classics.size > 500) classics.clear();
				classics.set(k, png);
			}
			res.writeHead(200, {
				'content-type': 'image/png',
				'access-control-allow-origin': '*',
				'cache-control': 'public, max-age=31536000, immutable',
			});
			res.end(req.method === 'HEAD' ? undefined : png);
			return true;
		}
		m = /^crest\/(\d{1,5})-(none|baron|coronet|crown)\.png$/.exec(rest);
		if (m) {
			const n = parseInt(m[1], 10);
			if (n >= heraldry.count || missing.has(n)) { sendJson(res, 404, { error: 'No such crest' }); return true; }
			const png = crestImage(n, m[2]);
			res.writeHead(200, {
				'content-type': 'image/png',
				'access-control-allow-origin': '*',
				'cache-control': 'public, max-age=31536000, immutable',
			});
			res.end(req.method === 'HEAD' ? undefined : png);
			return true;
		}
		sendJson(res, 404, { error: 'Not found' });
		return true;
	};
}
