// The Orthoverse: what every page shares. Load /css/site.css and this script,
// put <div id="ov-header"></div> (class "over" to lie over a picture) and
// <div id="ov-footer"></div> where they belong, and it draws:
//
//   - the header: the logo (home), Map, Account, Play, and the sign-in
//     control (Sign in, or your player name with a menu);
//   - the footer;
//   - the sign-in panel: choose a wallet account, sign, and the first time
//     choose a player name (needed for the game, asked straight away).
//
// Signing in belongs to the whole site: the auth service's session cookie
// (path /auth) works on every page. Pages listen for who is signed in with
// OV.on(fn), and use OV.wallet for the wallet itself.
(() => {
  'use strict';
  const OV = window.OV = window.OV || {};
  const CONTRACT = '0x118aeD2606D02C2545C6D7D2d1021e567cc08922';
  const NAME_RE = /^[A-Za-z0-9_-]{3,19}$/;
  OV.CONTRACT = CONTRACT;

  const el = (tag, attrs = {}, ...kids) => {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (k === 'class') e.className = v;
      else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
      else if (v !== false && v != null) e.setAttribute(k, v === true ? '' : v);
    }
    for (const k of kids) if (k != null) e.append(k);
    return e;
  };
  OV.el = el;

  // ------------------------------------------------------------------
  // The auth service

  OV.api = async (method, path, body) => {
    const res = await fetch(path, { method, credentials: 'same-origin',
      headers: body ? { 'content-type': 'application/json' } : {}, body: body ? JSON.stringify(body) : undefined });
    let data = {};
    try { data = await res.json(); } catch (e) { /* not JSON */ }
    if (!res.ok) throw new Error(data.error || ('The site answered ' + res.status + '.'));
    return data;
  };

  // Who is signed in: { signedIn, address, name, lands, canVisit, ... }
  OV.me = null;
  const listeners = [];
  OV.on = fn => { listeners.push(fn); if (OV.me) fn(OV.me); };
  function changed() {
    for (const fn of listeners) { try { fn(OV.me); } catch (e) { console.error(e); } }
    drawWho();
  }
  OV.set = me => { OV.me = me; changed(); };
  OV.refresh = async () => {
    try { OV.me = await OV.api('GET', '/auth/me'); } catch (e) { OV.me = { signedIn: false }; }
    changed();
    return OV.me;
  };

  // ------------------------------------------------------------------
  // The wallet (MetaMask and the like)

  const W = OV.wallet = {};
  W.MAINNET = '0x1';
  W.present = () => !!window.ethereum;
  W.hex = text => '0x' + Array.from(new TextEncoder().encode(text), b => b.toString(16).padStart(2, '0')).join('');
  W.pad = h => String(h).replace(/^0x/, '').toLowerCase().padStart(64, '0');
  W.short = a => a ? a.slice(0, 6) + '…' + a.slice(-4) : '';
  W.eth = wei => (Number(wei) / 1e18).toFixed(6).replace(/0+$/, '').replace(/\.$/, '') + ' ETH';
  W.call = data => window.ethereum.request({ method: 'eth_call', params: [{ to: CONTRACT, data }, 'latest'] });
  W.onMainnet = async () => {
    try { return (await window.ethereum.request({ method: 'eth_chainId' })) === W.MAINNET; } catch (e) { return false; }
  };
  W.toMainnet = () => window.ethereum.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: W.MAINNET }] });
  W.current = async () => {
    try { const a = await window.ethereum.request({ method: 'eth_accounts' }); return a && a[0] || null; } catch (e) { return null; }
  };
  // The accounts the wallet shares with the site. Asking for the accounts
  // permission again makes the wallet show its account picker every time.
  // MetaMask keeps every address already connected to the site ticked there
  // and returns them all, so with several the sign-in panel asks which one.
  // Wallets without the permission request fall back to the connected ones.
  W.accounts = async () => {
    try {
      const perms = await window.ethereum.request({ method: 'wallet_requestPermissions', params: [{ eth_accounts: {} }] });
      const caveat = (perms || []).flatMap(p => p.caveats || []).find(c => c.type === 'restrictReturnedAccounts');
      if (caveat && caveat.value && caveat.value.length) return [...new Set(caveat.value)];
    } catch (e) {
      if (e && e.code === 4001) throw e;
    }
    const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
    return accounts || [];
  };
  // One account (for paying): the signed-in address when the wallet shares
  // it, else the one selected in the wallet, else whichever it offers
  W.choose = async () => {
    let shared = [];
    try { shared = await window.ethereum.request({ method: 'eth_accounts' }) || []; } catch (e) { /* none yet */ }
    const mine = OV.me && OV.me.signedIn && OV.me.address;
    const match = mine && shared.find(a => a.toLowerCase() === mine.toLowerCase());
    if (match) return match;
    if (shared[0]) return shared[0];
    return (await W.accounts())[0];
  };
  W.declined = e => !!(e && (e.code === 4001 || /reject|denied|cancel/i.test(e.message || '')));
  W.error = e => {
    if (W.declined(e)) return 'You cancelled it in your wallet.';
    if (e && /insufficient funds/i.test(e.message || '')) return 'The wallet does not have enough ETH for this and its gas.';
    return (e && (e.data && e.data.message || e.message)) || 'The wallet gave no reason.';
  };
  // Send a transaction to the contract and wait until it is mined. `say`
  // gets progress messages (text, and an Etherscan link once sent). Returns
  // the receipt; throws on refusal or failure.
  W.send = async ({ from, data, value }, say = () => {}) => {
    say('Confirm in your wallet…');
    const tx = await window.ethereum.request({ method: 'eth_sendTransaction',
      params: [{ from, to: CONTRACT, data, value: '0x' + BigInt(value).toString(16) }] });
    say('Sent. Waiting for it to be mined (usually under a minute).', 'https://etherscan.io/tx/' + tx);
    for (let i = 0; i < 180; i++) {
      await new Promise(r => setTimeout(r, 5000));
      let receipt = null;
      try { receipt = await window.ethereum.request({ method: 'eth_getTransactionReceipt', params: [tx] }); } catch (e) { /* again */ }
      if (receipt) {
        if (receipt.status !== '0x1') throw new Error('The transaction failed on the chain; nothing changed and only the gas was spent.');
        return receipt;
      }
    }
    throw new Error('It is taking a long time to be mined; check it on Etherscan.');
  };

  // ------------------------------------------------------------------
  // Signing in

  let dialog = null;
  function buildDialog() {
    const msg = el('div', { class: 'ov-msg', role: 'status' });
    const close = el('button', { class: 'ov-close', type: 'button', 'aria-label': 'Close', onclick: () => dialog.close() }, '×');
    // Step 1: the wallet
    const noWallet = el('div', {},
      el('p', {}, 'No wallet found in this browser. Install MetaMask (or a similar wallet) and reload this page.'),
      el('p', { class: 'ov-quiet' }, 'Without a wallet you can still explore the Orthoverse as a guest.'),
      el('a', { class: 'ov-btn', href: '/play/' }, 'Play as a guest'));
    const signBtn = el('button', { class: 'ov-btn go', type: 'button', onclick: signIn }, 'Choose account and sign');
    const step1 = el('section', {},
      el('h2', {}, 'Sign in'),
      el('p', {}, 'Sign in with your Ethereum wallet. It costs nothing: your wallet signs a message that proves the address is yours.'),
      el('p', { class: 'ov-quiet' }, 'Any wallet may mine and build on the crofts, the common lands. Holders also build on their own lands.'),
      noWallet, el('div', { class: 'ov-row' }, signBtn));
    // Step 2: a player name, the first time
    const name = el('input', { id: 'ov-name', maxlength: '19', autocomplete: 'off', autocapitalize: 'off', spellcheck: 'false' });
    const nameBtn = el('button', { class: 'ov-btn go', type: 'submit' }, 'Take this name');
    const step2 = el('form', { novalidate: true, onsubmit: chooseName },
      el('h2', {}, 'Choose your player name'),
      el('p', {}, 'This is your name in the game and on the site. It stays with this wallet for good.'),
      el('label', { for: 'ov-name' }, '3 to 19 letters, digits, - and _'),
      name, el('div', { class: 'ov-row' }, nameBtn));
    // Step 1b: which address, when the wallet shares several
    const list = el('div', { style: 'display:grid;gap:8px' });
    const stepPick = el('section', { hidden: true },
      el('h2', {}, 'Which address?'),
      el('p', {}, 'Your wallet shared several addresses. Sign in with:'), list);
    dialog = el('dialog', { class: 'ov-dialog', 'aria-label': 'Sign in' },
      el('div', { class: 'ov-d-in' }, close, step1, stepPick, step2, msg));
    document.body.append(dialog);
    Object.assign(dialog, { msg, step1, stepPick, list, step2, noWallet, signBtn, name, nameBtn });
  }
  function say(text, bad) { dialog.msg.textContent = text || ''; dialog.msg.className = 'ov-msg' + (bad ? ' bad' : ''); }

  // Open the panel at the step that is due: sign in, or choose a name
  OV.signIn = () => {
    if (!dialog) buildDialog();
    const needName = OV.me && OV.me.signedIn && !OV.me.name;
    dialog.step1.hidden = needName;
    dialog.stepPick.hidden = true;
    dialog.step2.hidden = !needName;
    dialog.noWallet.hidden = W.present();
    dialog.signBtn.hidden = !W.present();
    say('');
    if (!dialog.open) dialog.showModal();
    if (needName) dialog.name.focus();
  };

  // Several addresses: one button each, resolving with the one chosen
  function pickAddress(addresses) {
    return new Promise(resolve => {
      dialog.list.innerHTML = '';
      for (const a of addresses) {
        dialog.list.append(el('button', { class: 'ov-btn', type: 'button', title: a,
          style: 'text-align:left;font:15px/1.4 var(--body-font);word-break:break-all',
          onclick: () => resolve(a) }, a));
      }
      dialog.step1.hidden = true;
      dialog.stepPick.hidden = false;
      say('');
    });
  }

  async function signIn() {
    dialog.signBtn.disabled = true;
    say('Check your wallet…');
    try {
      const shared = await W.accounts();
      if (!shared.length) throw new Error('The wallet did not share an account.');
      const address = shared.length > 1 ? await pickAddress(shared) : shared[0];
      dialog.stepPick.hidden = true;
      say('Sign the message in your wallet…');
      const n = await OV.api('GET', '/auth/nonce?address=' + encodeURIComponent(address));
      const signature = await window.ethereum.request({ method: 'personal_sign', params: [W.hex(n.message), address] });
      OV.set(await OV.api('POST', '/auth/verify', { nonce: n.nonce, signature }));
      if (OV.me.name) { dialog.close(); return; }
      OV.signIn();   // first time: on to the name
    } catch (e) {
      say(W.declined(e) ? 'Your wallet did not sign. Try again when you are ready.' : (e.message || String(e)), true);
    } finally {
      dialog.signBtn.disabled = false;
    }
  }

  async function chooseName(ev) {
    ev.preventDefault();
    const name = dialog.name.value.trim();
    if (!NAME_RE.test(name)) return say('Player names are 3 to 19 letters, digits, - and _, with no spaces.', true);
    if (/^guest/i.test(name)) return say('Names starting with "Guest" are kept for guests.', true);
    dialog.nameBtn.disabled = true;
    try {
      OV.set(await OV.api('POST', '/auth/name', { name }));
      dialog.close();
    } catch (e) {
      say(e.message, true);
    } finally {
      dialog.nameBtn.disabled = false;
    }
  }

  OV.signOut = async () => {
    try { await OV.api('POST', '/auth/logout', {}); } catch (e) { /* signed out anyway */ }
    OV.set({ signedIn: false });
  };

  // ------------------------------------------------------------------
  // Header and footer

  let who = null, bar = null;
  const here = location.pathname.replace(/index\.html$/, '');

  function link(href, text) {
    return el('a', { href, 'aria-current': here.startsWith(href) && href !== '/' ? 'page' : false }, text);
  }

  function drawHeader(slot) {
    bar = el('div', { class: 'ov-bar' + (slot.classList.contains('over') ? ' over' : ''), role: 'banner' });
    who = el('div', { class: 'ov-who' });
    const burger = el('button', { class: 'ov-btn ov-burger', type: 'button', 'aria-label': 'Menu', 'aria-expanded': 'false',
      onclick: () => { bar.classList.toggle('open'); burger.setAttribute('aria-expanded', String(bar.classList.contains('open'))); } }, '≡');
    bar.append(
      el('a', { class: 'ov-logo', href: '/' }, el('img', { src: '/img/logo.png', width: '498', height: '105', alt: 'The Orthoverse, home' })),
      el('nav', { 'aria-label': 'Site' }, link('/map/', 'Map'), link('/account/', 'Account'),
        el('a', { class: 'ov-btn go', href: '/play/', 'aria-current': here.startsWith('/play/') ? 'page' : false }, 'Play')),
      burger, who);
    slot.replaceWith(bar);
    drawWho();
  }

  function drawWho() {
    if (!who) return;
    who.innerHTML = '';
    const me = OV.me;
    if (!me) return;
    if (!me.signedIn) {
      who.append(el('button', { class: 'ov-btn', type: 'button', onclick: OV.signIn }, 'Sign in'));
      return;
    }
    if (!me.name) {
      who.append(el('button', { class: 'ov-btn gold', type: 'button', onclick: OV.signIn }, 'Choose your name'));
      return;
    }
    const menu = el('div', { class: 'ov-menu', hidden: true },
      el('p', {}, 'Signed in with ' + me.address),
      el('a', { href: '/account/' }, 'Account: your lands'),
      el('button', { class: 'ov-link', type: 'button', onclick: OV.signOut }, 'Sign out'));
    const btn = el('button', { class: 'ov-btn', type: 'button', 'aria-haspopup': 'true', 'aria-expanded': 'false',
      onclick: () => { menu.hidden = !menu.hidden; btn.setAttribute('aria-expanded', String(!menu.hidden)); } }, me.name + ' ▾');
    who.append(btn, menu);
  }

  function drawFooter(slot) {
    const foot = el('footer', { class: 'ov-foot' }, el('div', { class: 'ov-foot-in' },
      el('nav', { 'aria-label': 'Footer' }, el('a', { href: '/' }, 'Home'), el('a', { href: '/map/' }, 'Map'),
        el('a', { href: '/account/' }, 'Account'), el('a', { href: '/play/' }, 'Play')),
      el('p', { style: 'margin:0' }, 'Runs on ', el('a', { href: 'https://www.luanti.org' }, 'Luanti'),
        ', the open-source block game engine, with Minetest Game. Lands are tokens of the ',
        el('a', { href: 'https://etherscan.io/address/' + CONTRACT }, 'Orthoverse contract'), ' on Ethereum.'),
      el('p', { class: 'ov-doom', style: 'margin:0' }, 'The Orthoverse: doomed since 2022')));
    slot.replaceWith(foot);
  }

  // Draw what the page has room for; again after a page replaces its body
  OV.mount = () => {
    const h = document.getElementById('ov-header');
    if (h) drawHeader(h);
    const f = document.getElementById('ov-footer');
    if (f) drawFooter(f);
  };
  // Remove the header and footer (the game takes the whole window)
  OV.unmount = () => {
    document.querySelectorAll('.ov-bar, .ov-foot').forEach(n => n.remove());
    who = bar = null;
  };

  document.addEventListener('click', e => {
    if (who && !who.contains(e.target)) { const m = who.querySelector('.ov-menu'); if (m) m.hidden = true; }
  });

  const start = () => { OV.mount(); OV.refresh(); };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
