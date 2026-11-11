// The Orthoverse's backups: every night, a copy of everything that cannot be
// made again (the world, player sign-ins, the chain index) on the backup drive.
//
//   node backup.js            run for ever, backing up every day at OV_BACKUP_AT
//   node backup.js now        one backup now, then exit
//   node backup.js list       the backups there are
//   node backup.js restore NAME
//                             put backup NAME back (the restore service, with
//                             the game, auth and chain services stopped)
//
// What is copied (the map tiles and the browser game are drawn again from
// these, so they are left out):
//   /world        the Luanti world: map, players, game passwords, mod storage
//   /data/auth    wallet sign-ins and player names
//   /data/chain   the chain index
//
// Each backup is a folder in /backup named by its UTC time, for example
// 2026-11-08T0130. SQLite databases are copied with SQLite's own backup, which
// is safe while the game runs, checked, and compressed (.zst). The folder is
// written as NAME.partial and renamed when complete, so a folder without
// .partial is a whole backup. manifest.json lists what is in it.
//
// The backup drive must hold a file called .orthoverse-backup (create it once):
// if the drive is not mounted, the folder Docker gives us instead is on the
// system disk, without that file, and nothing is written.
//
// Kept: every backup of the last OV_BACKUP_DAYS days, then the newest of each
// week for OV_BACKUP_WEEKS weeks and of each month for OV_BACKUP_MONTHS months.

import { DatabaseSync, backup } from 'node:sqlite';
import { createReadStream, createWriteStream, existsSync } from 'node:fs';
import { readdir, stat, mkdir, rename, rm, copyFile, writeFile, readFile, unlink, open } from 'node:fs/promises';
import { join, dirname, relative } from 'node:path';
import { pipeline } from 'node:stream/promises';
import { createZstdCompress, createZstdDecompress, constants as Z } from 'node:zlib';
import { env, argv, exit } from 'node:process';

const DEST = env.OV_BACKUP_DIR || '/backup';
const MARKER = '.orthoverse-backup';
const SOURCES = [
	{ name: 'world', path: env.OV_BACKUP_WORLD || '/world' },
	{ name: 'auth', path: env.OV_BACKUP_AUTH || '/data/auth' },
	{ name: 'chain', path: env.OV_BACKUP_CHAIN || '/data/chain' },
];
const AT = env.OV_BACKUP_AT || '01:30';                   // UTC
const DAYS = parseInt(env.OV_BACKUP_DAYS || '14', 10);
const WEEKS = parseInt(env.OV_BACKUP_WEEKS || '8', 10);
const MONTHS = parseInt(env.OV_BACKUP_MONTHS || '12', 10);
const RATE = 2048;          // pages copied per step (8 MB at 4 kB pages)
const MAX_RESTARTS = 5;     // then copy in one step (the game waits for that: up to a minute,
                            // docker/luanti/Dockerfile; the engine alone gives up after 3 seconds)
// Left out: SQLite's temporary files, the game's log, and the folders other
// services mount into the world (backed up from where they really are)
// (and what a restore moved aside)
const SKIP = /^debug\.txt$|^orthoverse_(auth|chain)$|^\.before-restore-/;
const TEMP = /(-journal|-wal|-shm)$/;

const log = (...a) => console.log(new Date().toISOString(), ...a);
const sleep = ms => new Promise(r => setTimeout(r, ms));
const mb = n => (n / 1048576).toFixed(1) + ' MB';

// ---------------------------------------------------------------------------
// Copying

async function compress(from, to) {
	await pipeline(createReadStream(from),
		// (one thread: Node 24's zstd stream breaks with worker threads)
		createZstdCompress({ params: { [Z.ZSTD_c_compressionLevel]: 6 } }),
		createWriteStream(to));
}

// A live SQLite database, a page range at a time; if the game keeps changing
// it so that the copy keeps starting again, in one go instead
async function copyDatabase(from, to) {
	const src = new DatabaseSync(from, { readOnly: true, timeout: 30000 });
	try {
		let rate = RATE, tries = 0;
		for (;;) {
			const tmp = to + '.tmp';
			await rm(tmp, { force: true });
			// Between steps the game may write; SQLite then starts the copy
			// again, which shows as the pages left going up
			let restarts = 0, last = Infinity;
			const progress = ({ remainingPages }) => {
				if (remainingPages > last) restarts++;
				last = remainingPages;
				if (restarts > MAX_RESTARTS && rate === RATE) throw new Error('restarting');
			};
			const began = Date.now();
			try {
				await backup(src, tmp, { rate, progress });
				if (rate !== RATE) log(`  ${from} copied in one go in ${((Date.now() - began) / 1000).toFixed(1)} s`);
			} catch (e) {
				if (restarts > MAX_RESTARTS && rate === RATE) {
					log(`  ${from} kept changing during the copy; copying it in one go`);
					rate = 1 << 30;
					continue;
				}
				// The game was writing at that moment (busy or locked): again
				if (++tries > 30) throw new Error(`could not copy ${from}: ${e.message}`);
				if (tries === 10 && rate === RATE) {
					log(`  ${from} kept being busy; copying it in one go`);
					rate = 1 << 30;
				}
				await sleep(1000);
				continue;
			}
			await rename(tmp, to);
			break;
		}
	} finally {
		src.close();
	}
	const db = new DatabaseSync(to, { readOnly: true });
	try {
		const ok = db.prepare('PRAGMA quick_check').all().map(r => Object.values(r)[0]);
		if (ok.length !== 1 || ok[0] !== 'ok') throw new Error(`the copy of ${from} failed its check: ${ok.slice(0, 3).join('; ')}`);
	} finally {
		db.close();
	}
}

async function* files(dir, base = dir) {
	let entries;
	try { entries = await readdir(dir, { withFileTypes: true }); } catch { return; }
	for (const e of entries) {
		if (SKIP.test(e.name) && dir === base || TEMP.test(e.name)) continue;
		const p = join(dir, e.name);
		if (e.isDirectory()) yield* files(p, base);
		else if (e.isFile()) yield p;
	}
}

const isSqlite = async p => {
	if (!/\.(sqlite|db)$/.test(p)) return false;
	const buf = Buffer.alloc(16);
	const fh = await open(p, 'r');
	try { await fh.read(buf, 0, 16, 0); } finally { await fh.close(); }
	return buf.toString('latin1') === 'SQLite format 3\0';
};

async function backupNow() {
	if (!existsSync(join(DEST, MARKER))) {
		throw new Error(`${DEST} has no ${MARKER} file: is the backup drive mounted? Nothing written.`);
	}
	const started = new Date();
	const name = started.toISOString().slice(0, 16).replace(/[-:]/g, (c) => c === ':' ? '' : '-');
	const final = join(DEST, name);
	const part = final + '.partial';
	await rm(part, { recursive: true, force: true });
	const manifest = { started: started.toISOString(), files: [] };
	let total = 0;
	for (const s of SOURCES) {
		for await (const p of files(s.path)) {
			const rel = join(s.name, relative(s.path, p));
			const out = join(part, rel);
			await mkdir(dirname(out), { recursive: true });
			const t0 = Date.now();
			const size = (await stat(p)).size;
			if (await isSqlite(p)) {
				const raw = out + '.copy';
				await copyDatabase(p, raw);
				await compress(raw, out + '.zst');
				await unlink(raw);
				manifest.files.push({ path: rel, size, stored: rel + '.zst', sqlite: true });
			} else {
				await copyFile(p, out);
				manifest.files.push({ path: rel, size, stored: rel });
			}
			total += size;
			const secs = (Date.now() - t0) / 1000;
			if (secs > 2) log(`  ${rel}: ${mb(size)} in ${secs.toFixed(0)} s`);
		}
	}
	manifest.finished = new Date().toISOString();
	await writeFile(join(part, 'manifest.json'), JSON.stringify(manifest, null, '\t') + '\n');
	await rename(part, final);
	log(`backup ${name}: ${manifest.files.length} files, ${mb(total)}, ` +
		`${((Date.now() - started) / 1000).toFixed(0)} s`);
	await prune();
	return name;
}

// ---------------------------------------------------------------------------
// Keeping and listing

const BACKUP_NAME = /^(\d{4})-(\d{2})-(\d{2})T(\d{2})(\d{2})$/;
const timeOf = n => {
	const m = n.match(BACKUP_NAME);
	return m && Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]);
};

async function backups() {
	const names = (await readdir(DEST)).filter(n => BACKUP_NAME.test(n));
	return names.sort();
}

// Which backups to keep: all of the last DAYS days, then the newest of each
// week and of each month, as far back as WEEKS and MONTHS go
export function toKeep(names, now = Date.now()) {
	const keep = new Set();
	const day = 86400000;
	const week = t => Math.floor((t / day + 3) / 7);     // weeks since a Monday
	const month = t => { const d = new Date(t); return d.getUTCFullYear() * 12 + d.getUTCMonth(); };
	const nowMonth = month(now);
	const seenWeek = new Set(), seenMonth = new Set();
	for (const n of [...names].sort().reverse()) {        // newest first
		const t = timeOf(n);
		if (now - t < DAYS * day) keep.add(n);
		if (now - t < WEEKS * 7 * day && !seenWeek.has(week(t))) { keep.add(n); seenWeek.add(week(t)); }
		if (nowMonth - month(t) < MONTHS && !seenMonth.has(month(t))) { keep.add(n); seenMonth.add(month(t)); }
	}
	if (names.length) keep.add([...names].sort().at(-1));  // never the last one
	return keep;
}

async function prune() {
	const names = await backups();
	const keep = toKeep(names);
	for (const n of names) {
		if (!keep.has(n)) {
			await rm(join(DEST, n), { recursive: true, force: true });
			log(`removed old backup ${n}`);
		}
	}
	// A backup that died part-way, older than a day
	for (const n of await readdir(DEST)) {
		if (n.endsWith('.partial') && Date.now() - (await stat(join(DEST, n))).mtimeMs > 86400000) {
			await rm(join(DEST, n), { recursive: true, force: true });
		}
	}
}

async function list() {
	for (const n of await backups()) {
		try {
			const m = JSON.parse(await readFile(join(DEST, n, 'manifest.json'), 'utf8'));
			const size = m.files.reduce((a, f) => a + f.size, 0);
			console.log(`${n}  ${m.files.length} files, ${mb(size)}`);
		} catch {
			console.log(`${n}  (no manifest)`);
		}
	}
}

// ---------------------------------------------------------------------------
// Restoring: what is there now is moved aside to .before-restore-<time>
// inside each folder, never deleted

async function restore(name) {
	if (!name || !BACKUP_NAME.test(name)) throw new Error('Which backup? node backup.js list shows them.');
	const dir = join(DEST, name);
	const m = JSON.parse(await readFile(join(dir, 'manifest.json'), 'utf8'));
	const stamp = new Date().toISOString().slice(0, 19).replace(/[-:]/g, '');
	const where = Object.fromEntries(SOURCES.map(s => [s.name, s.path]));
	const moved = new Set();
	for (const f of m.files) {
		const [src, ...rest] = f.path.split('/');
		const root = where[src];
		if (!root) continue;
		const target = join(root, ...rest);
		if (existsSync(target)) {
			const aside = join(root, '.before-restore-' + stamp, ...rest);
			await mkdir(dirname(aside), { recursive: true });
			await rename(target, aside);
			moved.add(join(root, '.before-restore-' + stamp));
		}
		for (const suffix of ['-journal', '-wal', '-shm']) await rm(target + suffix, { force: true });
		await mkdir(dirname(target), { recursive: true });
		if (f.sqlite) {
			await pipeline(createReadStream(join(dir, f.stored)), createZstdDecompress(), createWriteStream(target));
		} else {
			await copyFile(join(dir, f.stored), target);
		}
	}
	log(`restored ${name}: ${m.files.length} files`);
	for (const p of moved) log(`what was there before is in ${p}`);
}

// ---------------------------------------------------------------------------

function msUntil(at) {
	const [h, mi] = at.split(':').map(Number);
	const now = new Date();
	const next = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), h, mi));
	if (next <= now) next.setUTCDate(next.getUTCDate() + 1);
	return next - now;
}

async function main() {
	const cmd = argv[2] || 'serve';
	if (cmd === 'now') return void await backupNow();
	if (cmd === 'list') return void await list();
	if (cmd === 'restore') return void await restore(argv[3]);
	if (cmd !== 'serve') throw new Error('node backup.js [serve | now | list | restore NAME]');
	log(`backing up every day at ${AT} UTC to ${DEST}; keeping ${DAYS} days, ${WEEKS} weeks, ${MONTHS} months`);
	if (!existsSync(join(DEST, MARKER))) log(`WARNING: ${DEST} has no ${MARKER} file; backups will not run until it does`);
	for (;;) {
		await sleep(msUntil(AT));
		try {
			await backupNow();
		} catch (e) {
			log('BACKUP FAILED:', e.message);
		}
	}
}

if (import.meta.url === `file://${argv[1]}`) {
	main().catch(e => { log('error:', e.message); exit(1); });
}
