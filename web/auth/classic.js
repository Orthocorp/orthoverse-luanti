// The classic Orthoverse land picture, drawn from nothing but a token ID and
// its castle level, as orthoverse-offline's make-map-image.js drew each land
// on the old map: a 6 x 6 isometric diamond of 16 x 11 pixel tiles, each
// chosen by one hex digit of the ID (the low three bits pick the tile, the
// high bit the palette), a castle in the middle from level 1, and for the
// futuristic realm a two-letter sign and, from level 13, a tower.
//
// Used for tokens with no land in the world to draw from: unrevealed ones
// (in grey, as the old map showed lands not yet placed) and revealed ones
// awaiting their land.

import { PNG } from 'pngjs';
import { tiles_fantasy, palettes_fantasy } from './classic/tiles-fantasy.js';
import { tiles_futuristic, palettes_futuristic, small_font, tower } from './classic/tiles-futuristic.js';

const W = 101, H = 44;     // the old pictures' size
const OX = 30;             // the diamond's tile origin within them

// Background ("bg-nft") colour of the old token pictures, per realm, picked by
// the ID's last byte (palette slot 8)
function background(id, futuristic) {
	const palettes = (futuristic ? palettes_futuristic : palettes_fantasy).slice(0, 6);
	return palettes[parseInt(id.slice(-2), 16) % palettes.length][8];
}

// The art at its own size: { width, height, data (RGBA) }
export function classicArt(token, level, grey) {
	const id = token.replace(/^0x/, '').toLowerCase().padStart(40, '0');
	const castle = level | 0;
	const futuristic = castle > 7;
	const tiles = futuristic ? tiles_futuristic : tiles_fantasy;
	const palettes = futuristic ? palettes_futuristic : palettes_fantasy;
	const data = Buffer.alloc(W * H * 4);
	const set = (x, y, c) => {
		if (x < 0 || y < 0 || x >= W || y >= H) return;
		let r = (c >>> 24) & 255, g = (c >>> 16) & 255, b = (c >>> 8) & 255;
		if (grey) r = g = b = Math.round(0.3 * r + 0.59 * g + 0.11 * b);
		const i = (y * W + x) * 4;
		data[i] = r; data[i + 1] = g; data[i + 2] = b; data[i + 3] = 255;
	};

	const tileChoice = [], paletteChoice = [];
	for (let i = 0; i < 36; i++) {
		tileChoice.push(parseInt(id[i], 16) & 7);
		paletteChoice.push((parseInt(id[i], 16) & 8) / 8);
	}
	// The castle: the middle four tiles (fantasy), the front middle four (futuristic)
	const putCastle = (row, base) => {
		tileChoice[2 + row * 6] = 8 + base * 4;
		tileChoice[3 + row * 6] = 9 + base * 4;
		tileChoice[2 + (row + 1) * 6] = 10 + base * 4;
		tileChoice[3 + (row + 1) * 6] = 11 + base * 4;
		for (const i of [2 + row * 6, 3 + row * 6, 2 + (row + 1) * 6, 3 + (row + 1) * 6]) paletteChoice[i] = 6;
	};
	if (castle !== 0 && castle < 8) putCastle(2, castle - 1);
	if (castle > 8) putCastle(4, castle - 9);

	for (let x = 0; x < 6; x++) {
		for (let y = 0; y < 6; y++) {
			const tile = tileChoice[x + y * 6];
			for (let sx = 0; sx < 16; sx++) {
				for (let sy = 0; sy < 11; sy++) {
					const tc = tiles[tile][sy][sx];
					if (tc === 9) continue;   // transparent
					let swatch = tile !== 2 ? paletteChoice[x + y * 6] : 2;   // lakes: the lake palette
					if (tile === 4 && castle < 8) swatch = 0;   // forest
					if (tile === 7 && castle < 8) swatch = 5;   // pine forest
					set(OX + x * 11 - y * 6 + sx, y * 6 + sy, palettes[swatch][tc]);
				}
			}
		}
	}

	// Futuristic castles carry a sign with the ID's first two digits
	if (castle > 8) {
		const [xs, ys] = castle === 9 ? [OX + 4, 32] : [OX + 1, 35];
		const c1 = parseInt(id[0], 16), c2 = parseInt(id[1], 16);
		for (let y = 0; y < 5; y++) {
			for (let x = 0; x < 3; x++) {
				if (small_font[c1][x + y * 3] === 1) set(xs + x, ys + y, 0x109eefff);
				if (small_font[c2][x + y * 3] === 1) set(xs + x + 4, ys + y, 0x109eefff);
			}
		}
	}
	// and from level 13 a tower
	if (castle > 12) {
		for (let y = 0; y < 26; y++) {
			for (let x = 0; x < 17; x++) {
				const tc = tower[castle - 13][y][x];
				if (tc !== 9) set(OX + 1 + x, 5 + y, palettes[6][tc]);
			}
		}
	}
	return { width: W, height: H, data };
}

// A token picture: the art scaled up on the old background colour
export function classicCard(token, level, grey, size = 800) {
	const art = classicArt(token, level, grey);
	const scale = Math.floor((size - 64) / art.width);
	const out = new PNG({ width: size, height: size });
	const id = token.replace(/^0x/, '').toLowerCase().padStart(40, '0');
	let bg = background(id, level > 7);
	let r = (bg >>> 24) & 255, g = (bg >>> 16) & 255, b = (bg >>> 8) & 255;
	if (grey) r = g = b = Math.round(0.3 * r + 0.59 * g + 0.11 * b);
	for (let i = 0; i < size * size; i++) {
		out.data[i * 4] = r; out.data[i * 4 + 1] = g; out.data[i * 4 + 2] = b; out.data[i * 4 + 3] = 255;
	}
	const ox = Math.floor((size - art.width * scale) / 2), oy = Math.floor((size - art.height * scale) / 2);
	for (let y = 0; y < art.height; y++) {
		for (let x = 0; x < art.width; x++) {
			const i = (y * art.width + x) * 4;
			if (!art.data[i + 3]) continue;
			for (let dy = 0; dy < scale; dy++) {
				const row = (oy + y * scale + dy) * size;
				for (let dx = 0; dx < scale; dx++) {
					const o = (row + ox + x * scale + dx) * 4;
					out.data[o] = art.data[i]; out.data[o + 1] = art.data[i + 1];
					out.data[o + 2] = art.data[i + 2]; out.data[o + 3] = 255;
				}
			}
		}
	}
	return PNG.sync.write(out);
}
