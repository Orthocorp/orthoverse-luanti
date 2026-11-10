// Managing characters from the server's terminal: asks the running auth
// service (its admin socket, reachable only inside its container). Run by
// characters.sh at the top of the repository:
//
//   docker compose exec -T auth node admin.js <command> [arguments]
//
// Commands: list [text], show <name>, lock <name> [reason], unlock <name>,
// recovery <name>, delete <name>. Prints JSON (characters.sh shows it as a
// table or text).
import net from 'node:net';

const [cmd, name, ...rest] = process.argv.slice(2);
const req = cmd === 'list' ? { cmd, text: name || '' } : { cmd, name, why: rest.join(' ') };
const sock = net.createConnection('\0orthoverse-auth-admin');
let buf = '';
sock.setEncoding('utf8');
sock.on('connect', () => sock.write(JSON.stringify(req) + '\n'));
sock.on('data', d => { buf += d; });
sock.on('end', () => {
	process.stdout.write(buf);
	try { process.exit(JSON.parse(buf).error ? 1 : 0); } catch (e) { process.exit(1); }
});
sock.on('error', e => {
	console.log(JSON.stringify({ error: 'The auth service did not answer (' + e.code + '): is it running?' }));
	process.exit(1);
});
