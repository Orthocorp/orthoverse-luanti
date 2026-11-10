# Accounts with a password, and linking a wallet later: plan

> **Built** on the adventure branch in patches 1002 to 1005 (auth service, sign-in panel, Account page, the game side). What changed from this plan: the "Keep this character" hand-off for guests is not built yet. The plan is kept as the record of why.

Draft, 8 Nov 2026 (night). Keir's idea: let people create a character with a name and password, and register an Ethereum address against it later. It would make the world more accessible: today the choice is a wallet or a throwaway guest. No code yet.

This reverses part of the 6 Nov decision ("old name and password accounts removed"), for a good reason: once adventures, character levels and parties exist, people need a character that keeps its progress, and most people who might enjoy a dungeon have no Ethereum wallet and will not install one to try a game.

## How players sign in today

- Wallet players: Sign-In with Ethereum on the website; the name is chosen once and bound to the wallet in registry.json; the auth service makes a fresh game password for each entry into the game (since patch 1062; it was derived from the name before), so the player never sees or types one. The game lets in only names in the registry, and guests.
- Guests: the play page makes up Guest-XXXXXX and a random password, kept in that browser only. Lose the browser data and the guest is gone. Guests explore, cannot build.

## The idea: one character, two ways in

Every player has one **character** (the player name in the game, with its inventory, character level, party and so on). A character can have:

- a **password** (an email-free account made on the website), and/or
- a **wallet** (linked by signing in with it).

Either way in leads to the same character. A player can start with a password today and link a wallet next year; their character, levels and builds carry over.

### Keep the auth service as the only door

- The player types their name and password on the website (the play page or the Account page), never into Luanti itself. The auth service checks the password (stored as a slow, salted hash, such as scrypt, which Node has built in) and gives the browser the same session cookie a wallet sign-in gives.
- The game password comes from the auth service, exactly as for wallet players (a fresh one for each entry since patch 1062). So the play page gets the game password from the auth service after either kind of sign-in, and the game itself needs almost no change: it already lets in registered names.
- This avoids the trap of two passwords (the one the player chose and the one the game knows). Luanti only ever sees the derived one.
- For a later desktop Luanti client (if the game's port is opened and the server listed publicly), the Account page could show the character's game password so it can be typed into desktop Luanti. To decide then.

### Linking a wallet to a password character

- Signed in with a password, the player presses "Link a wallet" on the Account page and signs the sign-in message with their wallet. The auth service adds the address to the character's registry entry.
- From then on the wallet signs them in too, and every land that wallet holds is theirs in the game, with all the castle-level abilities.
- One wallet, one character: a wallet already bound to another character cannot be linked (unless that character is given up, perhaps later).
- Wallet characters can add a password too (the same page, the other way round), useful on a computer without the wallet.

### What changes with a wallet

| | Guest | Password character | With a linked wallet |
| --- | --- | --- | --- |
| Explore, ride, use henges | yes | yes | yes |
| Keep inventory, character level, progress | this browser only | yes, on any computer | yes |
| Adventures and parties | to decide | yes | yes |
| Build on crofts (common land) | no | to decide (see Abuse) | yes |
| Hold lands, castle abilities, reveal, upgrade | no | no | yes |

### Turning a guest into a character

- A guest who likes the game should be able to keep what they have: "Keep this character" on the play page asks for a name and password and turns the guest's progress (inventory, levels) into the new character. Technically: register the new name, then copy the guest's player data to it once (the game does this when the new character first joins, from a request file, as other auth-to-game hand-offs do now).

## Lost passwords

- No email is asked for, so there is no reset by email. Options:
  - A wallet linked: sign in with the wallet and set a new password. The best recovery, and a reason to link one.
  - No wallet: a recovery code shown once at registration ("write this down"), which sets a new password. Simple and needs nothing stored but its hash.
  - Optional email for recovery only, later, if players ask. It brings privacy duties (below), so not at first.
  - The admin can always reset a password by hand.

## Abuse

Password accounts are free to make, unlike wallet sign-in (which already costs a little effort), so:

- **Registration limits:** a few new characters per IP address per day; Cloudflare's free Turnstile check on the registration form (orthoverse.land is already behind Cloudflare), which stops scripts without puzzles for real people.
- **Names:** the same rules as wallet names (letters, digits, - and _, no "Guest" prefix), plus a short list of reserved and offensive names, and the admin can rename.
- **Crofts:** common land today allows any wallet player to build. For password characters, choose: (a) the same as wallet players, relying on rollback for griefing; (b) only after some time or a character level (for example after an hour of play or reaching level 2), so throwaway accounts cannot grief at once (suggested); (c) never.
- **Bans:** a ban on a name; and a ban on the wallet, which also covers any character that wallet links to later.

## Privacy

- Stored: name, password hash, recovery code hash, linked address if any, dates. No email, no real names. The site's privacy note (planned in the launch checklist) should say so.
- A way to delete a character on request (name freed after a while, wallet unlinked).

## Pieces

- Auth service: registration, password sign-in, password change, recovery code, link wallet, add password, rate limits and Turnstile, guest-to-character hand-off.
- Play page and Account page: the forms; "Keep this character" for guests; "Link a wallet" and "Add a password".
- Game: nothing for sign-in itself (registered names already join); the guest-to-character copy; croft building rules for password characters.
- Tests: as for wallet sign-in (the auth test suite), plus a password and wallet linking round trip.

Size: medium, mostly in the auth service and the pages. It can come before the dungeon work: it helps the playtest (testers without wallets get real characters) and the launch.

## Decisions for Keir

1. Password characters at all (this plan assumes yes) and before or after the launch (suggest before: it widens the playtest).
2. Crofts for password characters: same as wallets, after some play (suggested), or never.
3. Lost password recovery: recovery code (suggested), wallet only, or email.
4. Guests: keep them alongside password characters (suggest yes: "just look around" with no form at all is still worth having), and whether guests may do adventures.
5. Turnstile on registration (suggest yes).
