// Orthoverse skins: a character's look, made from parts (after Ready Player
// Doomed, the Orthoverse avatar designer). Shared by the Account page, which
// paints a preview in the browser, and the auth service, which paints the skin
// the game uses: the same design always gives the same picture, and nobody
// uploads a picture of their own.
//
// A design: { v: 1, skin, eyes ('small' or 'large'), eye, hair, hairc, beard,
// beardc, top, topc, pants, pantsc, boots, bootsc, acc } where the colours are
// '#rrggbb', the styles numbers (0: none), and acc the accessories worn (their
// numbers in ACCESSORIES). Some accessories need a castle level.
//
// The parts (parts/*.png) are 64 x 64 skins, painted over each other; the game
// uses the 64 x 32 layout (toGame). The parts are by Orthocorp, CC BY-SA 3.0.

export const W = 64, H = 64;

export const PALETTES = {
	skin: [
		'#291709', '#271910', '#392416', '#5f3310', '#733f17', '#6a4225', '#7f4422',
		'#8b5831', '#935f37', '#bb6436', '#b26644', '#cf965f', '#d49e7a', '#f2c280',
		'#ecc091', '#f8d998', '#f9d4a0', '#fde7ad', '#fee3c6', '#f3eeea',
	],
	eye: [
		'#dec27c', '#cff087', '#64c5ce', '#a1ad79', '#9ada76', '#69a6dd', '#79bc5e',
		'#7f92d6', '#8b8959', '#7288db', '#9c713e', '#614023', '#83240f', '#4d311f',
		'#403321', '#392c2c', '#53212f', '#2b246d', '#22201a', '#1f0e46',
	],
	hair: [
		'#030303', '#343434', '#787a79', '#eeeeee', '#bc3b15', '#ba6025', '#fe5f35',
		'#fbcf2b', '#fef87e', '#beb85e', '#92593b', '#553118', '#c98359', '#dfbdb2',
		'#bd3d46', '#eb9fb3', '#579ec8', '#008c48', '#e14674', '#9d1bb3',
	],
	beard: [
		'#030303', '#343434', '#686a69', '#b1b5b8', '#dde3e7', '#bc3b15', '#ba6025',
		'#fe5f35', '#fbcf2b', '#fef87e', '#1c0a19', '#92593b', '#553118', '#c98359',
		'#dfbdb2', '#bd3d46', '#eb9fb3', '#579ec8', '#008c48', '#e14674',
	],
	top: [
		'#fe0000', '#0232dc', '#208d10', '#b1b5b8', '#dde3e7', '#623412', '#ecefff',
		'#fee101', '#dd8b1b', '#bdbdbd', '#ffd08d', '#d07870', '#974c5b', '#90ac64',
		'#abc587', '#663399', '#4066e0', '#b9bfff', '#bbbbbb', '#f74b00', '#222222',
	],
	pants: [
		'#fe0000', '#0232dc', '#208d10', '#b1b5b8', '#dde3e7', '#623412', '#ecefff',
		'#fee101', '#dd8b1b', '#bdbdbd', '#ffd08d', '#d07870', '#974c5b', '#90ac64',
		'#abc587', '#663399', '#4066e0', '#b9bfff', '#bbbbbb', '#f74b00', '#222222',
	],
	boots: [
		'#fe0000', '#0232dc', '#208d10', '#b1b5b8', '#dde3e7', '#623412', '#ecefff',
		'#fee101', '#dd8b1b', '#bdbdbd', '#ffd08d', '#d07870', '#974c5b', '#90ac64',
		'#abc587', '#663399', '#4066e0', '#b9bfff', '#bbbbbb', '#f74b00', '#222222',
	],
};

// How many of each style there are (besides 0, none)
export const STYLES = { hair: 6, beard: 7, top: 8, pants: 5, boots: 5 };

// Accessories: file, name, the castle level they need
export const ACCESSORIES = [
	['armbands', 'Armbands', 0],
	['tiara', 'Tiara', 0],
	['rope-belt', 'Rope belt', 0],
	['simple-belt', 'Simple belt', 0],
	['borgo-hat', 'Borgo hat', 1],
	['copper-diadem', 'Copper diadem', 5],
	['silver-diadem', 'Silver diadem', 5],
	['gold-diadem', 'Gold diadem', 5],
	['copper-coronet', 'Copper coronet', 6],
	['silver-coronet', 'Silver coronet', 6],
	['gold-coronet', 'Gold coronet', 6],
	['copper-crown', 'Copper crown', 7],
	['silver-crown', 'Silver crown', 7],
	['gold-crown', 'Gold crown', 7],
];

const STYLE_FILE = { hair: 'hair', beard: 'beard', top: 'top', pants: 'pants', boots: 'boots' };
const HEX = /^#[0-9a-f]{6}$/;

// Checks a design (from a page, or storage) and gives it back tidied, or
// throws an Error saying what is wrong. level: the castle level the player
// holds (0 to 7), for the accessories that need one.
export function checkDesign(d, level) {
	if (!d || typeof d !== 'object' || Array.isArray(d)) throw new Error('Not a design.');
	const out = { v: 1 };
	const colour = k => {
		const c = String(d[k] || '').toLowerCase();
		if (!HEX.test(c)) throw new Error('Not a colour: ' + k + '.');
		return c;
	};
	out.skin = colour('skin');
	out.eyes = d.eyes === 'large' ? 'large' : 'small';
	out.eye = colour('eye');
	for (const k of Object.keys(STYLES)) {
		const n = Number(d[k]);
		if (!Number.isInteger(n) || n < 0 || n > STYLES[k]) throw new Error('No such ' + k + '.');
		out[k] = n;
		out[k + 'c'] = colour(k + 'c');
	}
	const acc = Array.isArray(d.acc) ? d.acc : [];
	if (acc.length > ACCESSORIES.length) throw new Error('Too many accessories.');
	const worn = new Set();
	for (const a of acc) {
		const i = Number(a);
		if (!Number.isInteger(i) || i < 0 || i >= ACCESSORIES.length) throw new Error('No such accessory.');
		if (ACCESSORIES[i][2] > (level | 0)) {
			throw new Error('The ' + ACCESSORIES[i][1].toLowerCase() + ' needs a castle at level ' + ACCESSORIES[i][2] + '.');
		}
		worn.add(i);
	}
	out.acc = [...worn].sort((a, b) => a - b);
	return out;
}

// A design picked at random (rand: a function giving 0 <= x < 1)
export function randomDesign(rand = Math.random) {
	const pick = list => list[Math.floor(rand() * list.length)];
	const d = { v: 1, skin: pick(PALETTES.skin), eyes: rand() < 0.5 ? 'small' : 'large', eye: pick(PALETTES.eye), acc: [] };
	for (const k of Object.keys(STYLES)) {
		d[k] = 1 + Math.floor(rand() * STYLES[k]);
		d[k + 'c'] = pick(PALETTES[k]);
	}
	if (rand() < 0.4) d.beard = 0;
	return d;
}

// The part files a design is painted from, in order, each with the colour it
// is tinted towards and how far (as the designer did: 75%, the face 55%)
export function layers(d) {
	const out = [
		{ file: 'base', tint: d.skin, by: 0.75 },
		{ file: 'features', tint: d.skin, by: 0.55 },
		{ file: 'sclera-' + d.eyes },
		{ file: 'iris-' + d.eyes, tint: d.eye, by: 0.75 },
	];
	for (const k of ['top', 'beard', 'hair', 'pants', 'boots']) {
		if (d[k] > 0) out.push({ file: STYLE_FILE[k] + '-' + d[k], tint: d[k + 'c'], by: 0.75 });
	}
	for (const i of d.acc) out.push({ file: 'acc-' + ACCESSORIES[i][0] });
	return out;
}

// Every part file there is (for loading them ahead)
export function allParts() {
	const files = ['base', 'features', 'sclera-small', 'sclera-large', 'iris-small', 'iris-large'];
	for (const k of Object.keys(STYLES)) for (let n = 1; n <= STYLES[k]; n++) files.push(STYLE_FILE[k] + '-' + n);
	for (const a of ACCESSORIES) files.push('acc-' + a[0]);
	return files;
}

const rgb = hex => [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16));

// Paints a design: part(file) gives a part's 64 x 64 RGBA pixels (a
// Uint8Array or Uint8ClampedArray of 64 * 64 * 4). Gives the 64 x 64 skin.
export function paint(d, part) {
	const out = new Uint8ClampedArray(W * H * 4);
	for (const l of layers(d)) {
		const src = part(l.file);
		const t = l.tint ? rgb(l.tint) : null;
		for (let i = 0; i < W * H * 4; i += 4) {
			const a = src[i + 3] / 255;
			if (a === 0) continue;
			let r = src[i], g = src[i + 1], b = src[i + 2];
			if (t) {
				r = Math.round(r + (t[0] - r) * l.by);
				g = Math.round(g + (t[1] - g) * l.by);
				b = Math.round(b + (t[2] - b) * l.by);
			}
			// over what is there
			const da = out[i + 3] / 255, oa = a + da * (1 - a);
			out[i] = Math.round((r * a + out[i] * da * (1 - a)) / oa);
			out[i + 1] = Math.round((g * a + out[i + 1] * da * (1 - a)) / oa);
			out[i + 2] = Math.round((b * a + out[i + 2] * da * (1 - a)) / oa);
			out[i + 3] = Math.round(oa * 255);
		}
	}
	return out;
}

// The game's 64 x 32 skin from a 64 x 64 one: the top half (head, the hat
// layer, body, right arm and leg), with the outer layers of the body, the
// right arm and the right leg painted onto them. The game's model mirrors the
// right arm and leg for the left.
export function toGame(sk) {
	const out = new Uint8ClampedArray(64 * 32 * 4);
	out.set(sk.subarray(0, 64 * 32 * 4));
	const over = (sx, sy, w, h, dx, dy) => {
		for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
			const s = ((sy + y) * 64 + sx + x) * 4, o = ((dy + y) * 64 + dx + x) * 4;
			const a = sk[s + 3] / 255;
			if (a === 0) continue;
			for (let c = 0; c < 3; c++) out[o + c] = Math.round(sk[s + c] * a + out[o + c] * (1 - a));
			out[o + 3] = Math.max(out[o + 3], sk[s + 3]);
		}
	};
	over(0, 32, 16, 16, 0, 16);     // the right leg's outer layer
	over(16, 32, 24, 16, 16, 16);   // the jacket, onto the body
	over(40, 32, 16, 16, 40, 16);   // the right sleeve
	return out;
}
