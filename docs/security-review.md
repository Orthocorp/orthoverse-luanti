# Security review, November 2026

A sweep of everything built so far: the game mods, the auth service, the web
proxy, the website, nginx and the Docker setup. What was found, what was
fixed (patch 1038), and what is left.

## How the pieces are exposed

- Only nginx is published, on 127.0.0.1, reached through the Cloudflare
  tunnel. Nothing listens on a public address.
- The Luanti server sits on an internal Docker network with no way in or out
  except the web proxy, which relays the game's datagrams to that one server
  and nothing else (no TCP, no other addresses, names answered for the
  Orthoverse only).
- The auth service holds the only secret (OV_AUTH_SECRET, in .env, which git
  ignores). The game reads its registry read-only; the auth service reads the
  game's accounts read-only.
- Containers run as the service user, most of them read-only.

## Fixed

### Critical: anyone could take a new character

Luanti makes an account the first time a client joins under a name, with
whatever password that client sends. The website hands each character a
password, but the game account did not exist until the player first joined.
Anyone who learned a new name (the lands page, the map, chat) and joined first
owned the character for good, including the admin's name before the admin's
first join (the admin mod gives that name every privilege).

Now the auth service stores, for each character, the game account's password
record (an SRP verifier, exactly as Luanti stores it; web/auth/srp.js), and
the game makes the account itself, before the engine looks the name up
(orthoverse_wallets, on_prejoinplayer). A client with the wrong password is
refused like any wrong password. A character without a record yet is told to
try again in a minute. Characters made before the change get a record when the
auth service starts.

Tested with the native client against the real server: the right password
joins, a wrong one on the very first join is refused and does not make the
account.

**After deploying, run** `docker compose exec auth node check-accounts.js`. It
lists characters whose game account has a password the website did not give:
either the player changed it in the game, or someone took the character
before the fix. For one that was taken, `/setpassword <name> <password>` with
the password the website shows its player gives it back.

### High: loot chests could be emptied twice

A player's share opens as a private inventory. Closing it forgot which share
was open but left the items in the inventory, and taking was still allowed,
so a modified client could take everything, close, reopen and take it all
again. Taking now needs the share to be open, and closing (or leaving) empties
the private inventory.

### Medium: a spawner could flood the server

A spawner's "test" button brings its monsters every click, with no limit.
Anyone allowed to set a spawner (on their own land) could bring thousands of
entities and slow or crash the server. Now no more than 30 monsters near any
spawner; the button says so when there are enough.

### Medium: no browser security headers

Every response now carries nosniff, X-Frame-Options DENY, a referrer policy,
a permissions policy and HSTS, and the nginx version is hidden. Site pages get
a Content-Security-Policy: scripts only from the site and Cloudflare
Turnstile, fonts from Google, nothing loaded or sent to any other site, no
plugins, no framing, forms post only to the site. Checked in a browser: no
page breaks. The browser game (/play/) keeps its own headers without the
policy, because its engine builds code at run time.

### Lower

- **Dependencies.** ws 8.18.3 to 8.21.3 (the proxy), ethers 6.15.0 to 6.17.0
  (the auth service). `npm audit`: no known vulnerabilities in either.
- **Map tooltip.** A land's name was shown as HTML on the map; a holder could
  name a land with markup. Now shown as text. (Every other page already wrote
  text, not HTML.)
- **Registry lookups.** A name like `__proto__` looked up the object's
  prototype instead of a character. Harmless here, but lookups now check the
  name is really in the registry.
- **Token pictures.** Any token id's classic picture can be asked for, and
  drawing one costs time. Drawings not already cached are now rate-limited
  per address (60 a minute).
- **The proxy.** Connections that have not yet bound to the game are limited
  to 20 per address and 15 seconds, so nobody can hold open thousands of idle
  sockets. (Bound connections were already limited to 6 per address, 100 in
  all.)
- **/adventure place** checks the name is a plain name before building a file
  path from it (admin only, so not reachable by players).

## Checked, nothing to fix

- Sessions are signed with the secret and compared in constant time; cookies
  are HttpOnly, SameSite=Strict, Secure over https, limited to /auth. A
  password session ends when the password changes.
- Passwords and recovery codes are stored as scrypt hashes only. Logins are
  rate-limited per address and per name (15 minutes after repeated wrong
  passwords).
- Request bodies: JSON only, 8 KB at most (nginx: 16 KB).
- Wallet sign-in: the service writes the message to sign, keeps it, accepts
  a signature of exactly that message once, and only for a few minutes.
- Form handlers and chat commands in the mods check permission on the server
  (protection, admin privileges), not in the client.
- Backups and restore are operator-only; no web route touches them.
- No secrets in the repository or its history.

## Left as they are (known risks)

- **A modified game client can cheat** within what the server allows: aim, see
  through walls, record a faster adventure time. Luanti's server checks
  movement and digging roughly; records and rank should be treated as for fun.
- **Names can be checked.** /auth/exists says whether a name is taken (it has
  to, to make characters). Rate-limited.
- **A name can be locked out for 15 minutes** by someone typing wrong
  passwords for it on the website. The recovery code still works. The game's
  own login is separate and unaffected.
- **Wallet sessions cannot be ended early** except by signing out on that
  browser; they last 30 days. Changing OV_AUTH_SECRET ends every session (and
  changes every game password, so do it only with a plan).
- **Guests** (Guest-xxxxxx) are made by whoever joins first under the name,
  as before. They hold nothing worth taking.
- **The robot check** is off unless OV_TURNSTILE_SECRET is set. Set it in
  production.
- **Base images** (node, nginx, Ubuntu) are pinned; rebuild them now and then
  for security updates (`docker compose build --pull`).
- **Inline scripts.** Each page has an inline script, so the policy allows
  them; it limits what injected script could reach, but does not stop it
  running. Moving the scripts into files would allow a stricter policy.
