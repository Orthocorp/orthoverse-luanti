// Land names, as orthoverse-offline's load-tokens.js made them (config/names.cjs),
// from the token ID: hex digit pairs pick a prefix (rarely), a start, a link, a
// middle and an ending. Lands revealed early (about the first thousand) were
// named with an older scheme, and keep those names in lands.json.

// 8 in 256 names get a prefix such as 'Costa ' or 'North '
const NAMES_0 = [...Array(248).fill(''), 'Costa ', 'El ', 'Porto ', 'New ', 'South ', 'North ', 'East ', 'West '];
const NAMES_1 = [
	'Ar', 'Bel', 'Cor', 'Dun', 'Er', 'Fan', 'Gil', 'Hat',
	'Is', 'Jez', 'Kim', 'Lan', 'Mav', 'Nor', 'On', 'Par',
	'Quil', 'Rot', 'Sag', 'Tel', 'Ur', 'Vor', 'West', 'Cair',
	'Das', 'Fel', 'Gan', 'Her', 'Ili', 'Kar', 'Lem', 'Mor',
	'Nas', 'Ol', 'Pen', 'Ras', 'Sor', 'Taz', 'Un', 'Van',
	'Al', 'Arn', 'Arc', 'As', 'Bal', 'Bol', 'Bil', 'Ber',
	'Cam', 'Com', 'Cyr', 'Clan', 'Dir', 'Den', 'Dot', 'Dyn',
	'El', 'En', 'Em', 'Eth', 'For', 'Fyn', 'Fit', 'Frog',
	'Gaw', 'Gop', 'Giqu', 'Gat', 'Gyr', 'Hal', 'Hor', 'Hyb',
];
const NAMES_1A = [
	'', 'a', 'e', 'i', 'o', 'u', 'y', 'ith',
	'mo', 'ma', 'mi', 'me', 'no', 'na', 'ni', 'ny',
	'ca', 'fa', 'fo', 'fi', 'da', 'do', 'di', 'co',
	'ci', 'ca', 'cy', 'ha', 'ho', 'hi', 'he', 'hy',
	'la', 'lo', 'li', 'le', 'ly', 'pa', 'po', 'pi',
	'qua', 'que', 'ra', 're', 'ro', 'ri', 'ry', 'ru',
	'sa', 'se', 'si', 'so', 'sy', 'ti', 'to', 'ty',
	'tu', 'ta', 'va', 've', 'vi', 'vo', 'vy', 'wa',
	'we', 'wi', 'wo', 'wu', 'wy', 'al', 'ag', 'en',
];
const NAMES_2 = [
	'an', 'ber', 's', 'en', 'il', 'vet', 'tor', 'nar',
	'er', 'ast', 'sel', 'mar', 'mor', 'son', 'rim', 'fors',
	'orb', 'undar', 'arb', 'air', 'from', 'zil', 'wan', 'xior',
	'ust', 'uir', 'ram', 'ner', 'tar', 'wen', 'bar', 'vast',
	'en', 'bur', 'can', 'cor', 'das', 'dal', 'far', 'fur',
	'gor', 'gan', 'hos', 'nir', 'nat', 'siz', 'van', 'zum',
	'am', 'al', 'bo', 'by', 'car', 'cal', 'diz', 'dan',
	'em', 'el', 'ed', 'ef', 'go', 'gyd', 'ha', 'hi',
	'jor', 'jan', 'kit', 'kor', 'lav', 'lot', 'myr', 'math',
	'',
];
const NAMES_3 = [
	'ica', 'land', 'ia', 'dor', 'del', 'ance', 'mia', 'ina',
	'bia', 'tria', 'any', 'ain', 'lia', 'ada', 'ico', 'ala',
	'ize', 'iti', 'aly', 'ili', 'mark', 'den', 'sia', 'nia',
	'sha', 'bya', 'bwe', 'dia', 'fia', 'ely', 'oli', 'ola',
	'ene', 'ium', 'eum', 'ka', 'su', 'mi', 'emi', 'der',
];

const pick = (list, hex) => list[parseInt(hex, 16) % list.length];

// The name for a token ID (0x and 40 hex digits)
export function landName(token) {
	const h = token.slice(2);
	return pick(NAMES_0, h.slice(14, 16)) + pick(NAMES_1, h.slice(6, 8)) + pick(NAMES_1A, h.slice(12, 14)) +
		pick(NAMES_2, h.slice(8, 10)) + pick(NAMES_3, h.slice(10, 12));
}

const TITLES = [
	'Croft', 'Land', 'Domain', 'Fiefdom', 'Barony', 'Duchy', 'Principality', 'Kingdom',
	'Town', 'City', 'Metropolis', 'Region', 'District', 'State', 'Prefecture', 'Nation',
];

export function landDescription(name, level) {
	return 'The Orthoverse ' + (TITLES[level] || 'Land') + ' of ' + name;
}
