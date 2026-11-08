// The Orthoverse: what every page shares. Load /css/site.css and this script,
// put <div id="ov-header"></div> (class "over" to lie over a picture) and
// <div id="ov-footer"></div> where they belong, and it draws:
//
//   - the header: the logo (home), Map, Adventures, Account, Play, and the sign-in
//     control (Sign in, or your player name with a menu);
//   - the footer;
//   - the sign-in panel: a name and password, or a wallet (choose an
//     account, sign, and the first time choose a player name); making a new
//     character with a name and password, with its recovery code; setting a
//     new password with the recovery code.
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

  // ------------------------------------------------------------------
  // Phones and tablets: the Orthoverse needs a computer. Decided before the
  // page is drawn (this script loads in the head), so the page never shows;
  // a card takes its place. iPads call themselves Macs: a Mac with a touch
  // screen is one. "I am on a computer" (or ?anyway=1) is remembered.
  const COMPUTER_KEY = 'ov-computer';
  OV.isPhone = (() => {
    try {
      if (new URLSearchParams(location.search).has('anyway')) localStorage.setItem(COMPUTER_KEY, '1');
      if (localStorage.getItem(COMPUTER_KEY) === '1') return false;
    } catch (e) { /* no storage: ask each time */ }
    const ua = navigator.userAgent || '';
    if (navigator.userAgentData && navigator.userAgentData.mobile) return true;
    if (/Android|iPhone|iPad|iPod|Mobile|Silk|Kindle|Opera Mini|IEMobile/i.test(ua)) return true;
    return /Macintosh/.test(ua) && navigator.maxTouchPoints > 1;
  })();
  if (OV.isPhone) document.documentElement.classList.add('ov-is-phone');

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
  // The Turnstile site key (or null), from the auth service, once
  let config = null;
  const getConfig = async () => {
    if (!config) { try { config = await OV.api('GET', '/auth/config'); } catch (e) { config = { turnstile: null }; } }
    return config;
  };
  const input = (id, attrs = {}) => el('input', { id, class: 'ov-in', autocomplete: 'off', autocapitalize: 'off',
    spellcheck: 'false', ...attrs });

  function buildDialog() {
    const msg = el('div', { class: 'ov-msg', role: 'status' });
    const close = el('button', { class: 'ov-close', type: 'button', 'aria-label': 'Close', onclick: () => dialog.close() }, '×');
    const go = (step) => () => OV.signIn(step);
    const linkBtn = (text, onclick) => el('button', { class: 'ov-link', type: 'button', onclick }, text);

    // Step 1: sign in, with a name and password or a wallet
    const lName = input('ov-l-name', { maxlength: '19', autocomplete: 'username' });
    const lPass = input('ov-l-pass', { type: 'password', maxlength: '128', autocomplete: 'current-password' });
    const lBtn = el('button', { class: 'ov-btn go', type: 'submit' }, 'Sign in');
    const noWallet = el('p', { class: 'ov-quiet' }, 'No wallet in this browser. A wallet (such as MetaMask) lets you hold lands; ' +
      'without one you can still have a character, or explore as a guest.');
    const signBtn = el('button', { class: 'ov-btn', type: 'button', onclick: signIn }, 'Sign in with a wallet');
    const step1 = el('section', {},
      el('h2', {}, 'Sign in'),
      el('form', { novalidate: true, onsubmit: login },
        el('label', { for: 'ov-l-name' }, 'Player name'), lName,
        el('label', { for: 'ov-l-pass', style: 'margin-top:10px' }, 'Password'), lPass,
        el('div', { class: 'ov-row' }, lBtn, linkBtn('Forgot your password?', go('recover')))),
      el('p', { style: 'margin-top:16px' }, 'New here? ', linkBtn('Make a character', go('register')),
        ' with a name and password. You can link a wallet to it later.'),
      el('hr', { class: 'ov-hr' }),
      el('p', {}, 'Or sign in with your Ethereum wallet. It costs nothing: your wallet signs a message that proves the address is yours. ' +
        'Holders build on their own lands.'),
      noWallet, el('div', { class: 'ov-row' }, signBtn));

    // Step 2: a player name, the first time a wallet signs in
    const name = input('ov-name', { maxlength: '19' });
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
      el('p', {}, 'Your wallet shared several addresses. Use:'), list);

    // A new character with a name and password
    const rName = input('ov-r-name', { maxlength: '19', autocomplete: 'username' });
    const rPass = input('ov-r-pass', { type: 'password', maxlength: '128', autocomplete: 'new-password' });
    const rPass2 = input('ov-r-pass2', { type: 'password', maxlength: '128', autocomplete: 'new-password' });
    const robot = el('div', { class: 'ov-robot' });
    const rBtn = el('button', { class: 'ov-btn go', type: 'submit' }, 'Make my character');
    const stepRegister = el('form', { novalidate: true, hidden: true, onsubmit: register },
      el('h2', {}, 'Make a character'),
      el('p', {}, 'Your name in the game and on the site. Your character keeps what you carry and what you achieve, ' +
        'on any computer. A wallet can be linked to it later, to hold lands.'),
      el('label', { for: 'ov-r-name' }, 'Player name: 3 to 19 letters, digits, - and _'), rName,
      el('label', { for: 'ov-r-pass', style: 'margin-top:10px' }, 'Password: at least 8 characters'), rPass,
      el('label', { for: 'ov-r-pass2', style: 'margin-top:10px' }, 'The password again'), rPass2,
      robot,
      el('div', { class: 'ov-row' }, rBtn, linkBtn('Back to sign in', go('signin'))));

    // A new password with the recovery code
    const cName = input('ov-c-name', { maxlength: '19', autocomplete: 'username' });
    const cCode = input('ov-c-code', { maxlength: '24', placeholder: 'XXXX-XXXX-XXXX-XXXX' });
    const cPass = input('ov-c-pass', { type: 'password', maxlength: '128', autocomplete: 'new-password' });
    const cBtn = el('button', { class: 'ov-btn go', type: 'submit' }, 'Set the new password');
    const stepRecover = el('form', { novalidate: true, hidden: true, onsubmit: recover },
      el('h2', {}, 'Forgot your password?'),
      el('p', {}, 'Use the recovery code you were given when you made your character. If your character has a wallet, ' +
        'you can also sign in with the wallet and set a new password on the Account page.'),
      el('label', { for: 'ov-c-name' }, 'Player name'), cName,
      el('label', { for: 'ov-c-code', style: 'margin-top:10px' }, 'Recovery code'), cCode,
      el('label', { for: 'ov-c-pass', style: 'margin-top:10px' }, 'New password: at least 8 characters'), cPass,
      el('div', { class: 'ov-row' }, cBtn, linkBtn('Back to sign in', go('signin'))));

    // The recovery code, shown once
    const codeBox = el('p', { class: 'ov-code' });
    const copied = el('span', { class: 'ov-quiet' });
    const stepCode = el('section', { hidden: true },
      el('h2', {}, 'Your recovery code'),
      el('p', {}, 'Write this down and keep it somewhere safe. If you forget your password, it is the only way back ' +
        'into your character (unless you link a wallet). It is shown only now.'),
      codeBox,
      el('div', { class: 'ov-row' },
        el('button', { class: 'ov-btn', type: 'button', onclick: async () => {
          try { await navigator.clipboard.writeText(codeBox.textContent); copied.textContent = 'Copied.'; } catch (e) { copied.textContent = 'Select it and copy it by hand.'; }
        } }, 'Copy'),
        el('button', { class: 'ov-btn go', type: 'button', onclick: () => dialog.close() }, 'I have written it down'),
        copied));

    dialog = el('dialog', { class: 'ov-dialog', 'aria-label': 'Sign in' },
      el('div', { class: 'ov-d-in' }, close, step1, stepPick, step2, stepRegister, stepRecover, stepCode, msg));
    // The recovery code must not be lost by closing the panel by accident
    dialog.addEventListener('cancel', e => { if (!stepCode.hidden) e.preventDefault(); });
    document.body.append(dialog);
    Object.assign(dialog, { closeBtn: close, msg, step1, stepPick, list, step2, noWallet, signBtn, name, nameBtn,
      lName, lPass, lBtn, stepRegister, rName, rPass, rPass2, robot, rBtn,
      stepRecover, cName, cCode, cPass, cBtn, stepCode, codeBox, copied });
  }
  function say(text, bad) { dialog.msg.textContent = text || ''; dialog.msg.className = 'ov-msg' + (bad ? ' bad' : ''); }

  // Cloudflare Turnstile on the registration form, when the site uses it.
  // Its script comes from Cloudflare, which a cross-origin isolated page (the
  // play page) cannot load: there, registration is sent to the Account page.
  let robotToken = null, robotWidget = null;
  async function robotCheck() {
    const c = await getConfig();
    dialog.robot.innerHTML = '';
    robotToken = null;
    if (!c.turnstile) return true;
    if (window.crossOriginIsolated) {
      dialog.robot.append(el('p', {}, 'Make your character on the ', el('a', { href: '/account/#new' }, 'Account page'),
        ', then come back here to play.'));
      return false;
    }
    if (!window.turnstile) {
      await new Promise((resolve, reject) => {
        const sc = el('script', { src: 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit', async: true });
        sc.onload = resolve; sc.onerror = () => reject(new Error('The check that you are not a robot could not be loaded.'));
        document.head.append(sc);
      });
    }
    robotWidget = window.turnstile.render(dialog.robot, { sitekey: c.turnstile, theme: 'dark',
      callback: t => { robotToken = t; }, 'expired-callback': () => { robotToken = null; } });
    return true;
  }

  // Open the panel at a step: 'signin', 'register', 'recover', or the one
  // that is due (sign in, or choose a name)
  OV.signIn = async (step) => {
    if (!dialog) buildDialog();
    if (typeof step !== 'string') step = OV.me && OV.me.signedIn && !OV.me.name ? 'name' : 'signin';
    dialog.step1.hidden = step !== 'signin';
    dialog.stepPick.hidden = true;
    dialog.step2.hidden = step !== 'name';
    dialog.stepRegister.hidden = step !== 'register';
    dialog.stepRecover.hidden = step !== 'recover';
    dialog.stepCode.hidden = true;
    dialog.closeBtn.hidden = false;
    dialog.noWallet.hidden = W.present();
    dialog.signBtn.hidden = !W.present();
    say('');
    if (!dialog.open) dialog.showModal();
    if (step === 'name') dialog.name.focus();
    if (step === 'signin') dialog.lName.focus();
    if (step === 'recover') dialog.cName.focus();
    if (step === 'register') {
      dialog.rName.focus();
      dialog.rBtn.disabled = false;
      try { dialog.rBtn.disabled = !await robotCheck(); } catch (e) { say(e.message, true); }
    }
  };

  // After a sign-in that gave a recovery code: show it, once
  function showCode(code) {
    dialog.step1.hidden = dialog.stepRegister.hidden = dialog.stepRecover.hidden = dialog.step2.hidden = true;
    dialog.codeBox.textContent = code;
    dialog.copied.textContent = '';
    dialog.stepCode.hidden = false;
    dialog.closeBtn.hidden = true;   // only "I have written it down" closes it
    say('');
  }
  OV.showRecoveryCode = code => { if (!dialog) buildDialog(); if (!dialog.open) dialog.showModal(); showCode(code); };

  async function busy(btn, fn) {
    btn.disabled = true;
    try { await fn(); } catch (e) { say(e.message || String(e), true); } finally { btn.disabled = false; }
  }

  function login(ev) {
    ev.preventDefault();
    const name = dialog.lName.value.trim(), password = dialog.lPass.value;
    if (!name || !password) return say('Enter your player name and password.', true);
    busy(dialog.lBtn, async () => {
      OV.set(await OV.api('POST', '/auth/login', { name, password }));
      dialog.lPass.value = '';
      dialog.close();
    });
  }

  function register(ev) {
    ev.preventDefault();
    const name = dialog.rName.value.trim(), password = dialog.rPass.value;
    if (!NAME_RE.test(name)) return say('Player names are 3 to 19 letters, digits, - and _, with no spaces.', true);
    if (/^guest/i.test(name)) return say('Names starting with "Guest" are kept for guests.', true);
    if (password.length < 8) return say('Passwords are at least 8 characters.', true);
    if (password !== dialog.rPass2.value) return say('The two passwords are not the same.', true);
    if (config && config.turnstile && !robotToken) return say('Wait for the check that you are not a robot to finish.', true);
    busy(dialog.rBtn, async () => {
      try {
        const me = await OV.api('POST', '/auth/register', { name, password, turnstile: robotToken });
        dialog.rPass.value = dialog.rPass2.value = '';
        OV.set(me);
        showCode(me.recoveryCode);
      } finally {
        if (robotWidget !== null && window.turnstile) { try { window.turnstile.reset(robotWidget); } catch (e) { /* next time */ } }
        robotToken = null;
      }
    });
  }

  function recover(ev) {
    ev.preventDefault();
    const name = dialog.cName.value.trim(), code = dialog.cCode.value.trim(), password = dialog.cPass.value;
    if (!name || !code) return say('Enter your player name and recovery code.', true);
    if (password.length < 8) return say('Passwords are at least 8 characters.', true);
    busy(dialog.cBtn, async () => {
      const me = await OV.api('POST', '/auth/recover', { name, code, password });
      dialog.cPass.value = dialog.cCode.value = '';
      OV.set(me);
      showCode(me.recoveryCode);
    });
  }

  // Several addresses: one button each, resolving with the one chosen
  function pickAddress(addresses, selected) {
    return new Promise(resolve => {
      dialog.list.innerHTML = '';
      for (const a of addresses) {
        const isSel = selected && a.toLowerCase() === selected.toLowerCase();
        dialog.list.append(el('button', { class: 'ov-btn' + (isSel ? ' go' : ''), type: 'button', title: a,
          style: 'text-align:left;font:15px/1.4 var(--body-font);word-break:break-all',
          onclick: () => resolve(a) }, a, isSel ? el('br') : null, isSel ? '(selected in your wallet)' : null));
      }
      dialog.step1.hidden = true;
      dialog.stepPick.hidden = false;
      say('');
    });
  }

  // A wallet address and its signature on a fresh sign-in message
  async function walletSignature(direct) {
    let address = typeof direct === 'string' ? direct : null;
    if (!address) {
      // The account selected in the wallet first, then the others shared
      const selected = await W.current();
      let shared = await W.accounts();
      if (!shared.length) throw new Error('The wallet did not share an account.');
      if (selected) shared = [selected, ...shared.filter(a => a.toLowerCase() !== selected.toLowerCase())];
      address = shared.length > 1 ? await pickAddress(shared, selected) : shared[0];
    }
    dialog.stepPick.hidden = true;
    say('Sign the message in your wallet…');
    const n = await OV.api('GET', '/auth/nonce?address=' + encodeURIComponent(address));
    const signature = await window.ethereum.request({ method: 'personal_sign', params: [W.hex(n.message), address] });
    return { nonce: n.nonce, signature };
  }

  async function signIn(direct) {
    dialog.signBtn.disabled = true;
    say('Check your wallet…');
    try {
      OV.set(await OV.api('POST', '/auth/verify', await walletSignature(direct)));
      if (OV.me.name) { dialog.close(); return; }
      OV.signIn('name');   // first time: on to the name
    } catch (e) {
      say(W.declined(e) ? 'Your wallet did not sign. Try again when you are ready.' : (e.message || String(e)), true);
      dialog.step1.hidden = false;
    } finally {
      dialog.signBtn.disabled = false;
    }
  }

  // Link a wallet to the signed-in password character. Resolves when done;
  // throws with a message for the page to show.
  OV.linkWallet = async () => {
    if (!W.present()) throw new Error('No wallet in this browser.');
    if (!dialog) buildDialog();
    dialog.step1.hidden = dialog.step2.hidden = dialog.stepRegister.hidden = dialog.stepRecover.hidden = dialog.stepCode.hidden = true;
    say('Check your wallet…');
    if (!dialog.open) dialog.showModal();
    try {
      OV.set(await OV.api('POST', '/auth/link', await walletSignature()));
      dialog.close();
    } catch (e) {
      dialog.close();
      throw new Error(W.declined(e) ? 'Your wallet did not sign.' : (e.message || String(e)));
    }
  };

  async function chooseName(ev) {
    ev.preventDefault();
    const name = dialog.name.value.trim();
    if (!NAME_RE.test(name)) return say('Player names are 3 to 19 letters, digits, - and _, with no spaces.', true);
    if (/^guest/i.test(name)) return say('Names starting with "Guest" are kept for guests.', true);
    busy(dialog.nameBtn, async () => {
      OV.set(await OV.api('POST', '/auth/name', { name }));
      dialog.close();
    });
  }

  // Sign in with one particular address (the one selected in the wallet)
  OV.signInAs = address => {
    if (!dialog) buildDialog();
    dialog.step1.hidden = true;
    dialog.stepPick.hidden = true;
    dialog.step2.hidden = true;
    say('');
    if (!dialog.open) dialog.showModal();
    signIn(address).then(() => { if (dialog.open && !dialog.step2.hidden) return; dialog.step1.hidden = false; });
  };

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
      el('nav', { 'aria-label': 'Site' }, link('/map/', 'Map'), link('/adventures/', 'Adventures'), link('/account/', 'Account'),
        el('a', { class: 'ov-btn go', href: '/play/', 'aria-current': here.startsWith('/play/') ? 'page' : false }, 'Play')),
      burger, who);
    slot.replaceWith(bar);
    drawWho();
  }

  // The wallet has another account selected than the one signed in: say so,
  // and offer to sign in with it (MetaMask lists the selected account first)
  let notice = null;
  async function checkWalletAccount() {
    if (notice) { notice.remove(); notice = null; }
    const me = OV.me;
    if (!bar || !me || !me.signedIn || !me.address || me.signedInWith !== 'wallet' || !W.present()) return;
    const selected = await W.current();
    if (!selected || selected.toLowerCase() === me.address.toLowerCase()) return;
    notice = el('div', { class: 'ov-notice', role: 'status' },
      'Your wallet has ' + W.short(selected) + ' selected, but you are signed in as ' +
        (me.name || W.short(me.address)) + ' (' + W.short(me.address) + '). ',
      el('button', { class: 'ov-btn', type: 'button', onclick: () => OV.signInAs(selected) }, 'Sign in as ' + W.short(selected)));
    bar.after(notice);
  }
  if (window.ethereum && window.ethereum.on) window.ethereum.on('accountsChanged', () => checkWalletAccount());

  function drawWho() {
    checkWalletAccount();
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
      el('p', {}, me.signedInWith === 'wallet' ? 'Signed in with ' + me.address
        : 'Signed in with your password' + (me.address ? ' (wallet ' + W.short(me.address) + ')' : '')),
      el('a', { href: '/account/' }, me.address ? 'Account: your lands' : 'Account'),
      el('button', { class: 'ov-link', type: 'button', onclick: OV.signOut }, 'Sign out'));
    const btn = el('button', { class: 'ov-btn signed', type: 'button', 'aria-haspopup': 'true', 'aria-expanded': 'false',
      onclick: () => { menu.hidden = !menu.hidden; btn.setAttribute('aria-expanded', String(!menu.hidden)); } }, me.name + ' ▾');
    who.append(btn, menu);
  }

  function drawFooter(slot) {
    const foot = el('footer', { class: 'ov-foot' }, el('div', { class: 'ov-foot-in' },
      el('nav', { 'aria-label': 'Footer' }, el('a', { href: '/' }, 'Home'), el('a', { href: '/map/' }, 'Map'), el('a', { href: '/adventures/' }, 'Adventures'),
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
    document.querySelectorAll('.ov-bar, .ov-foot, .ov-notice').forEach(n => n.remove());
    who = bar = null;
  };

  document.addEventListener('click', e => {
    if (who && !who.contains(e.target)) { const m = who.querySelector('.ov-menu'); if (m) m.hidden = true; }
  });

  function phoneCard() {
    const link = location.origin + '/play/';
    const copied = el('p', { class: 'ov-copied', 'aria-live': 'polite' });
    const send = el('button', { class: 'ov-btn go', type: 'button', onclick: async () => {
      try {
        if (navigator.share) { await navigator.share({ title: 'The Orthoverse', text: 'Play the Orthoverse on my computer', url: link }); return; }
        await navigator.clipboard.writeText(link);
        copied.textContent = 'Link copied: ' + link;
      } catch (e) {
        if (!(e && e.name === 'AbortError')) copied.textContent = 'The link is ' + link;
      }
    } }, 'Send this link to your computer');
    const card = el('main', { class: 'ov-phone-card' },
      el('img', { class: 'ov-phone-logo', src: '/img/logo.png', width: '498', height: '105', alt: 'The Orthoverse' }),
      el('div', { class: 'ov-phone-in' },
        el('img', { src: '/img/computer.png', width: '64', height: '52', alt: 'A computer showing a castle on a green hill' }),
        el('h1', {}, 'The Orthoverse needs a computer'),
        el('p', {}, 'The Orthoverse is a world you walk in your browser, on a desktop or laptop with a recent Chrome, ' +
          'Edge or Firefox, a keyboard and a mouse. Phones and tablets cannot run it.'),
        send, copied),
      el('a', { class: 'ov-anyway', href: '#', onclick: (e) => {
        e.preventDefault();
        try { localStorage.setItem(COMPUTER_KEY, '1'); } catch (err) { /* then by the address */ }
        location.search = location.search ? location.search + '&anyway=1' : '?anyway=1';
      } }, 'I am on a computer: let me in'));
    document.body.prepend(card);
  }

  const start = () => {
    if (OV.isPhone) phoneCard();
    OV.mount();
    OV.refresh();
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
