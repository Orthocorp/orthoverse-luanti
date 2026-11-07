// For the admin: give a character a new recovery code, for a player who has
// lost both their password and their code. Stop the auth service first (it
// keeps the names in memory and would write over the change):
//
//   docker compose stop auth
//   docker compose run --rm auth node recovery-code.js <player name>
//   docker compose start auth
//
// Tell the player the code; with it they set a new password ("Forgot your
// password?" in the sign-in panel). Check first that the request really comes
// from the character's player.

import { readFileSync, writeFileSync, renameSync } from 'node:fs';
import { join } from 'node:path';
import { randomBytes, scryptSync } from 'node:crypto';

const DATA_DIR = process.env.OV_DATA_DIR || '/data';
const FILE = join(DATA_DIR, 'registry.json');
const name = (process.argv[2] || '').toLowerCase();
const registry = JSON.parse(readFileSync(FILE, 'utf8'));
const entry = registry.players[name];
if (!entry) {
	console.error(`No character called ${process.argv[2] || '(none given)'}.`);
	process.exit(1);
}
const abc = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const bytes = randomBytes(16);
let code = '';
for (let i = 0; i < 16; i++) code += abc[bytes[i] % abc.length] + (i % 4 === 3 && i < 15 ? '-' : '');
const salt = randomBytes(16);
entry.rc = { s: salt.toString('base64'), h: scryptSync(code.replace(/-/g, ''), salt, 32, { N: 16384, r: 8, p: 1 }).toString('base64') };
writeFileSync(FILE + '.tmp', JSON.stringify(registry, null, 1));
renameSync(FILE + '.tmp', FILE);
console.log(`New recovery code for ${entry.name}: ${code}`);
