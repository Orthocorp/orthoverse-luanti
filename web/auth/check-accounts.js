// Which game accounts do not have the password the website gave their
// character. Before characters' accounts were made by the game itself
// (orthoverse_wallets, on_prejoinplayer), the first client to join under a new
// name set its password, so someone who saw a name first could have taken the
// character. Run once after updating, in the auth container:
//
//   docker compose exec auth node check-accounts.js
//
// A character listed here either changed its password in the game (the
// client's "Change password"), or was taken. Ask its player; to give it back,
// the admin types /setpassword <name> <the password the website shows them>.
//
// Prints names only; never passwords.

import { createHmac } from 'node:crypto';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { srpVerifier } from './srp.js';

const env = process.env;
const SECRET = env.OV_AUTH_SECRET || '';
const DATA_DIR = env.OV_DATA_DIR || '/data';
const AUTH_DB = env.OV_AUTH_DB || '/world/auth.sqlite';
if (SECRET.length < 32) { console.error('OV_AUTH_SECRET is not set'); process.exit(1); }
if (!existsSync(AUTH_DB)) { console.error(`No game accounts yet (${AUTH_DB})`); process.exit(0); }

// The same as server.js's gamePassword
const gamePassword = name => createHmac('sha256', SECRET)
	.update('orthoverse-player\n' + name.toLowerCase()).digest().toString('hex').slice(0, 32);

const registry = JSON.parse(readFileSync(join(DATA_DIR, 'registry.json'), 'utf8'));
const db = new DatabaseSync(AUTH_DB, { readOnly: true });
const get = db.prepare('SELECT name, password FROM auth WHERE lower(name) = lower(?)');
let checked = 0;
const odd = [];
for (const p of Object.values(registry.players || {})) {
	if (!p || typeof p.name !== 'string') continue;
	const row = get.get(p.name);
	if (!row) continue;
	checked++;
	const parts = String(row.password).split('#');   // "", "1", salt, verifier
	const ok = row.name === p.name && parts.length === 4 && parts[1] === '1' &&
		srpVerifier(p.name, gamePassword(p.name), Buffer.from(parts[2], 'base64')) === row.password;
	if (!ok) odd.push(row.name === p.name ? p.name : `${p.name} (account named ${row.name})`);
}
db.close();
console.log(`${checked} characters have game accounts; ${odd.length} with a password the website did not give:`);
for (const n of odd) console.log('  ' + n);
