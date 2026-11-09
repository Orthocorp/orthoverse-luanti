// Luanti's password record for a player: an SRP-6a verifier (SHA-256, the
// RFC 5054 2048-bit group), in the form auth.sqlite keeps it:
// "#1#<salt, base64>#<verifier, base64>". The same as Luanti's
// get_encoded_srp_verifier (src/util/auth.cpp, src/util/srp.cpp):
//
//   x = SHA-256(salt || SHA-256(lower(name) ":" password))   (big-endian)
//   v = g^x mod N,  g = 2,  written in as few bytes as it needs
//
// The auth service writes one for each character it makes (registry.json), so
// the game can create the character's account with the right password before
// anyone else can claim the name (orthoverse_wallets, on_prejoinplayer).

import { createHash, randomBytes } from 'node:crypto';

const N = BigInt('0x' +
	'AC6BDB41324A9A9BF166DE5E1389582FAF72B6651987EE07FC319294' +
	'3DB56050A37329CBB4A099ED8193E0757767A13DD52312AB4B03310D' +
	'CD7F48A9DA04FD50E8083969EDB767B0CF6095179A163AB3661A05FB' +
	'D5FAAAE82918A9962F0B93B855F97993EC975EEAA80D740ADBF4FF74' +
	'7359D041D5C33EA71D281E446B14773BCA97B43A23FB801676BD207A' +
	'436C6481F1D2B9078717461A5B9D32E688F87748544523B524B0D57D' +
	'5EA77A2775D2ECFA032CFBDBF52FB3786160279004E57AE6AF874E73' +
	'03CE53299CCC041C7BC308D82A5698F3A8D0C38271AE35F8E9DBFBB6' +
	'94B5C803D89F7AE435DE236D525F54759B65E372FCD68EF20FA7111F' +
	'9E4AFF73');
const G = 2n;

function modPow(base, exp, mod) {
	let result = 1n;
	base %= mod;
	while (exp > 0n) {
		if (exp & 1n) result = (result * base) % mod;
		base = (base * base) % mod;
		exp >>= 1n;
	}
	return result;
}

function toBytes(n) {
	let hex = n.toString(16);
	if (hex.length % 2) hex = '0' + hex;
	return Buffer.from(hex, 'hex');
}

const sha256 = (...parts) => {
	const h = createHash('sha256');
	for (const p of parts) h.update(p);
	return h.digest();
};

// Luanti lower-cases names with ASCII rules
const lower = s => s.replace(/[A-Z]/g, c => c.toLowerCase());

export function srpVerifier(name, password, salt = randomBytes(16)) {
	const inner = sha256(Buffer.from(lower(name), 'utf8'), Buffer.from(':'), Buffer.from(password, 'utf8'));
	const x = BigInt('0x' + sha256(salt, inner).toString('hex'));
	const v = modPow(G, x, N);
	return '#1#' + salt.toString('base64') + '#' + toBytes(v).toString('base64');
}
