// ── Auth state ───────────────────────────────────────────────────────────────

let authToken = localStorage.getItem('lp_token');
let currentUsername = localStorage.getItem('lp_username');
let currentIsAdmin  = localStorage.getItem('lp_isAdmin') === 'true';

let gear    = [];
let trips   = [];
let catalog = [];
let bundles = [];
let currentView    = 'gear';
let currentTripId  = null;
let currentPackIdx = 0;

// ── API helper ───────────────────────────────────────────────────────────────

async function api(path, options = {}) {
  let res;
  try {
    res = await fetch(`/api${path}`, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        ...(authToken ? { Authorization: `Bearer ${authToken}` } : {}),
        ...(options.headers || {}),
      },
      body: options.body ? JSON.stringify(options.body) : undefined,
    });
  } catch {
    throw new Error("You're offline — connect to save changes");
  }
  if (res.status === 401) { logout(); return null; }
  if (res.status === 403) return null;
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: 'Request failed' }));
    throw new Error(err.error || 'Request failed');
  }
  return res.json();
}

// ── Auth screens ─────────────────────────────────────────────────────────────

const landingScreen = document.getElementById('landing-screen');
const authScreen    = document.getElementById('auth-screen');
const appEl         = document.getElementById('app');
const offlineBanner = document.getElementById('offline-banner');

function setOffline(offline) {
  offlineBanner?.classList.toggle('hidden', !offline);
}
window.addEventListener('online',  () => { setOffline(false); loadAll(); });
window.addEventListener('offline', () => setOffline(true));
setOffline(!navigator.onLine);

function showApp() {
  landingScreen.classList.add('hidden');
  authScreen.classList.add('hidden');
  appEl.classList.remove('hidden');
  const uname = currentUsername || '';
  document.getElementById('header-username').textContent = uname;
  document.getElementById('user-dropdown-name').textContent = uname;
  document.getElementById('user-avatar-circle').textContent = uname.charAt(0).toUpperCase();
  const roleEl = document.getElementById('user-dropdown-role');
  if (currentIsAdmin) roleEl.classList.remove('hidden');
  else roleEl.classList.add('hidden');
  loadAll();
}

function showLanding() {
  landingScreen.classList.remove('hidden');
  authScreen.classList.add('hidden');
  appEl.classList.add('hidden');
}

function showAuth(defaultTab = 'login') {
  landingScreen.classList.add('hidden');
  authScreen.classList.remove('hidden');
  appEl.classList.add('hidden');
  // Reset all forms to step 1
  ['login', 'register'].forEach(tab => {
    const step1 = document.getElementById(`${tab}-step1`);
    const step2 = document.getElementById(`${tab}-step2`);
    if (step1) step1.classList.remove('hidden');
    if (step2) step2.classList.add('hidden');
    const errEl1 = document.getElementById(`${tab}-error`);
    const errEl2 = document.getElementById(`${tab}-code-error`);
    if (errEl1) errEl1.classList.add('hidden');
    if (errEl2) errEl2.classList.add('hidden');
  });
  // Switch to the requested tab
  document.querySelectorAll('.auth-tab').forEach(t => {
    t.classList.toggle('active', t.dataset.tab === defaultTab);
  });
  document.querySelectorAll('.auth-form').forEach(f => {
    f.classList.toggle('hidden', f.id !== `form-${defaultTab}`);
  });
}

async function loadAll() {
  try {
    const [gearData, tripsData, catalogData, bundlesData] = await Promise.all([
      api('/gear'),
      api('/trips'),
      api('/catalog'),
      api('/bundles'),
    ]);
    if (!gearData || !tripsData || !catalogData || !bundlesData) return;
    gear    = gearData.map(normalizeGear);
    trips   = tripsData.map(normalizeTrip);
    catalog = catalogData.map(c => ({ ...c, id: c._id ?? c.id }));
    bundles = bundlesData.map(normalizeBundle);
    renderGear();
    renderBundles();
    renderTripList();
    if (currentIsAdmin) loadPendingCount();
  } catch {
    // Offline with no cache yet — show empty state gracefully
    renderGear();
    renderBundles();
    renderTripList();
  }
}

// Normalise Mongo _id -> id for the frontend
function normalizeGear(g)   { return { ...g, id: g._id ?? g.id }; }
function normalizeBundle(b) {
  return {
    ...b,
    id: String(b._id ?? b.id),
    items: (b.items || []).map(i => ({ gearId: String(i.gearId), qty: i.qty ?? 1 })),
  };
}
function normalizeTrip(t)  {
  const base = { ...t, id: t._id ?? t.id };
  base.archived     = base.archived ?? false;
  base.frozenGear    = base.frozenGear    ? base.frozenGear.map(g => ({ ...g, id: g._id ?? g.id })) : null;
  base.frozenBundles = base.frozenBundles ? base.frozenBundles.map(b => ({
    ...b,
    id: b._id ?? b.id,
    items: (b.items || []).map(i => ({ ...i, gearId: i.gearId?._id ?? i.gearId })),
  })) : null;
  if (!base.packs || base.packs.length === 0) {
    const legacy = (base.pack || []).map(p => ({ ...p, gearId: p.gearId?._id ?? p.gearId }));
    base.packs = [{ name: 'Pack 1', items: legacy }];
  } else {
    base.packs = base.packs.map(pk => ({
      ...pk,
      cubes: (pk.cubes || []).map(c => ({ ...c, id: String(c._id ?? c.id) })),
      items: (pk.items || []).map(p => ({ ...p, gearId: p.gearId?._id ?? p.gearId })),
      bundleRefs: (pk.bundleRefs || []).map(br => ({
        ...br,
        bundleId: String(br.bundleId),
        checkedItems: (br.checkedItems || []).map(String),
        itemTypes: (br.itemTypes || []).map(it => ({ gearId: String(it.gearId), type: it.type || 'base' })),
        expanded: br.expanded ?? false,
        cubeId: br.cubeId || null,
      })),
    }));
  }
  return base;
}

if (authToken) { showApp(); } else { showLanding(); }

// Landing page buttons
document.getElementById('lp-btn-signin').addEventListener('click', () => showAuth('login'));
document.getElementById('lp-btn-signin2').addEventListener('click', () => showAuth('login'));
document.getElementById('lp-btn-getstarted').addEventListener('click', () => showAuth('register'));
document.getElementById('lp-btn-getstarted2').addEventListener('click', () => showAuth('register'));

// Auth tab switching
document.querySelectorAll('.auth-tab').forEach(tab => {
  tab.addEventListener('click', () => {
    document.querySelectorAll('.auth-tab').forEach(t => t.classList.toggle('active', t === tab));
    document.querySelectorAll('.auth-form').forEach(f => f.classList.add('hidden'));
    document.getElementById(`form-${tab.dataset.tab}`).classList.remove('hidden');
  });
});

// ── Username validation ───────────────────────────────────────────────────────
const USERNAME_RE = /^[a-z0-9_-]{3,30}$/;
function validateUsername(value) {
  if (!USERNAME_RE.test(value.trim().toLowerCase()))
    return 'Username must be 3–30 characters: letters, numbers, hyphens and underscores only';
  return null;
}

// ── OTP auth helpers ─────────────────────────────────────────────────────────

function setupOtpForm(tab) {
  // tab = 'login' | 'register'
  const form     = document.getElementById(`form-${tab}`);
  const step1    = document.getElementById(`${tab}-step1`);
  const step2    = document.getElementById(`${tab}-step2`);
  const errEl1   = document.getElementById(`${tab}-error`);
  const errEl2   = document.getElementById(`${tab}-code-error`);
  const hintEl   = document.getElementById(`${tab}-hint`);
  const backBtn  = document.getElementById(`${tab}-back`);

  let pendingUsername = '';

  form.addEventListener('submit', async e => {
    e.preventDefault();
    const fd = new FormData(form);

    // Step 1 → send code
    if (!step1.classList.contains('hidden')) {
      errEl1.classList.add('hidden');
      const btn = step1.querySelector('button[type=submit]');
      btn.disabled = true;
      btn.textContent = 'Sending…';
      try {
        const isLogin = tab === 'login';
        if (!isLogin) {
          const usernameErr = validateUsername(fd.get('username') || '');
          if (usernameErr) { errEl1.textContent = usernameErr; errEl1.classList.remove('hidden'); return; }
        }
        const body = isLogin
          ? { login: fd.get('login') }
          : { username: fd.get('username'), email: fd.get('email') };
        const data = await api('/auth/request-otp', { method: 'POST', body });
        if (!data) return;
        pendingUsername = data.username || fd.get('username')?.trim() || '';
        hintEl.textContent = `Code sent to ${data.maskedEmail} — check your inbox.`;
        step1.classList.add('hidden');
        step2.classList.remove('hidden');
        step2.querySelector('input[name=code]').value = '';
        step2.querySelector('input[name=code]').focus();
      } catch (err) {
        errEl1.textContent = err.message;
        errEl1.classList.remove('hidden');
      } finally {
        btn.disabled = false;
        btn.textContent = 'Send code';
      }
      return;
    }

    // Step 2 → verify code
    errEl2.classList.add('hidden');
    const btn = step2.querySelector('button[type=submit]');
    btn.disabled = true;
    btn.textContent = 'Verifying…';
    try {
      const data = await api('/auth/verify-otp', {
        method: 'POST',
        body: { username: pendingUsername, code: fd.get('code').trim() },
      });
      if (!data) return;
      authToken       = data.token;
      currentUsername = data.username;
      currentIsAdmin  = !!data.isAdmin;
      localStorage.setItem('lp_token',    authToken);
      localStorage.setItem('lp_username', currentUsername);
      localStorage.setItem('lp_isAdmin',  currentIsAdmin);
      showApp();
    } catch (err) {
      errEl2.textContent = err.message;
      errEl2.classList.remove('hidden');
    } finally {
      btn.disabled = false;
      btn.textContent = tab === 'login' ? 'Sign in' : 'Create account';
    }
  });

  backBtn.addEventListener('click', () => {
    step2.classList.add('hidden');
    step1.classList.remove('hidden');
    errEl2.classList.add('hidden');
    step1.querySelector('input[name=username]').focus();
  });
}

setupOtpForm('login');
setupOtpForm('register');

function logout() {
  authToken = null;
  currentUsername = null;
  currentIsAdmin  = false;
  localStorage.removeItem('lp_token');
  localStorage.removeItem('lp_username');
  localStorage.removeItem('lp_isAdmin');
  gear = []; trips = []; catalog = [];
  showLanding();
}
// ── User menu dropdown ───────────────────────────────────────────────────────
const userMenuBtn      = document.getElementById('btn-user-menu');
const userDropdown     = document.getElementById('user-dropdown');

function toggleUserMenu(e) {
  e.stopPropagation();
  const open = !userDropdown.classList.contains('hidden');
  userDropdown.classList.toggle('hidden', open);
  userMenuBtn.setAttribute('aria-expanded', String(!open));
}

function closeUserMenu() {
  userDropdown.classList.add('hidden');
  userMenuBtn.setAttribute('aria-expanded', 'false');
}

userMenuBtn.addEventListener('click', toggleUserMenu);

document.addEventListener('click', e => {
  if (!document.getElementById('user-menu').contains(e.target)) closeUserMenu();
});

document.addEventListener('keydown', e => {
  if (e.key === 'Escape') { closeUserMenu(); closeSettings(); }
});

// ── Settings modal ───────────────────────────────────────────────────────────
const settingsOverlay = document.getElementById('settings-overlay');

async function openSettings() {
  closeUserMenu();
  const uname = currentUsername || '';
  document.getElementById('settings-avatar').textContent = uname.charAt(0).toUpperCase();
  document.getElementById('settings-username-display').textContent = uname;
  document.getElementById('settings-email-display').textContent = '';
  const badge = document.getElementById('settings-admin-badge');
  if (currentIsAdmin) badge.classList.remove('hidden');
  else badge.classList.add('hidden');
  // Reset change fields
  document.getElementById('settings-new-username').value = '';
  document.getElementById('settings-new-email').value = '';
  ['settings-username-msg', 'settings-email-msg'].forEach(id => {
    const el = document.getElementById(id);
    el.classList.add('hidden');
    el.className = 'settings-field-msg hidden';
  });
  settingsOverlay.classList.remove('hidden');
  document.getElementById('btn-close-settings').focus();
  // Load current email
  try {
    const me = await api('/auth/me');
    if (me?.email) {
      document.getElementById('settings-email-display').textContent = me.email;
      document.getElementById('settings-new-email').placeholder = me.email;
    }
    if (me?.username) {
      document.getElementById('settings-new-username').placeholder = me.username;
    }
  } catch (_) {}
}

function closeSettings() {
  settingsOverlay.classList.add('hidden');
}

function showFieldMsg(id, text, isError) {
  const el = document.getElementById(id);
  el.textContent = text;
  el.className = `settings-field-msg ${isError ? 'error' : 'success'}`;
  el.classList.remove('hidden');
}

document.getElementById('btn-change-username').addEventListener('click', async () => {
  const input = document.getElementById('settings-new-username');
  const newUsername = input.value.trim();
  if (!newUsername) return;
  const usernameErr = validateUsername(newUsername);
  if (usernameErr) { showFieldMsg('settings-username-msg', usernameErr, true); return; }
  const btn = document.getElementById('btn-change-username');
  btn.disabled = true;
  try {
    const data = await api('/auth/username', { method: 'PUT', body: { newUsername } });
    if (!data) return;
    authToken       = data.token;
    currentUsername = data.username;
    currentIsAdmin  = !!data.isAdmin;
    localStorage.setItem('lp_token',    authToken);
    localStorage.setItem('lp_username', currentUsername);
    localStorage.setItem('lp_isAdmin',  currentIsAdmin);
    document.getElementById('settings-username-display').textContent = currentUsername;
    document.getElementById('settings-avatar').textContent = currentUsername.charAt(0).toUpperCase();
    document.getElementById('header-username').textContent = currentUsername;
    input.value = '';
    input.placeholder = currentUsername;
    document.getElementById('settings-new-username').placeholder = currentUsername;
    showFieldMsg('settings-username-msg', `Username updated to "${currentUsername}"`, false);
  } catch (err) {
    showFieldMsg('settings-username-msg', err.message, true);
  } finally {
    btn.disabled = false;
  }
});

document.getElementById('btn-change-email').addEventListener('click', async () => {
  const input = document.getElementById('settings-new-email');
  const newEmail = input.value.trim();
  if (!newEmail) return;
  const btn = document.getElementById('btn-change-email');
  btn.disabled = true;
  try {
    const data = await api('/auth/email', { method: 'PUT', body: { newEmail } });
    input.value = '';
    if (data?.email) {
      document.getElementById('settings-email-display').textContent = data.email;
      input.placeholder = data.email;
    }
    showFieldMsg('settings-email-msg', 'Email updated', false);
  } catch (err) {
    showFieldMsg('settings-email-msg', err.message, true);
  } finally {
    btn.disabled = false;
  }
});

document.getElementById('btn-open-settings').addEventListener('click', openSettings);
document.getElementById('btn-close-settings').addEventListener('click', closeSettings);
document.getElementById('btn-settings-logout').addEventListener('click', () => { closeSettings(); logout(); });

settingsOverlay.addEventListener('click', e => {
  if (e.target === settingsOverlay) closeSettings();
});

// ── Weight chart popup ───────────────────────────────────────────────────────
const weightChartPopup   = document.getElementById('weight-chart-popup');
const weightChartContent = document.getElementById('weight-chart-content');
document.getElementById('weight-chart-close').addEventListener('click', () => weightChartPopup.classList.add('hidden'));
document.addEventListener('click', e => {
  if (!weightChartPopup.contains(e.target) && !e.target.closest('[data-weight-chart]'))
    weightChartPopup.classList.add('hidden');
});

const CHART_COLORS = ['#2d6a4f','#5b8dd9','#e07b39','#9b59b6','#e74c3c','#16a085','#d4a017','#2980b9'];

function buildWeightChart(byCategory) {
  const segments = Object.entries(byCategory)
    .filter(([, v]) => v > 0)
    .sort((a, b) => b[1] - a[1])
    .map(([label, value], i) => ({ label, value, color: CHART_COLORS[i % CHART_COLORS.length] }));
  const total = segments.reduce((s, x) => s + x.value, 0);
  if (!total) return '<p style="color:var(--text-muted);text-align:center;padding:1rem 0">No weighted items.</p>';

  const cx = 70, cy = 70, r = 58;
  let paths = '';
  let angle = -Math.PI / 2;
  if (segments.length === 1) {
    paths = `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${segments[0].color}"/>`;
  } else {
    for (const seg of segments) {
      const sweep = (seg.value / total) * 2 * Math.PI;
      const x1 = cx + r * Math.cos(angle);
      const y1 = cy + r * Math.sin(angle);
      angle += sweep;
      const x2 = cx + r * Math.cos(angle);
      const y2 = cy + r * Math.sin(angle);
      paths += `<path d="M${cx},${cy} L${x1.toFixed(2)},${y1.toFixed(2)} A${r},${r} 0 ${sweep > Math.PI ? 1 : 0} 1 ${x2.toFixed(2)},${y2.toFixed(2)} Z" fill="${seg.color}"/>`;
    }
  }

  const legend = segments.map(s => `
    <div class="chart-legend-row">
      <span class="chart-legend-dot" style="background:${s.color}"></span>
      <span class="chart-legend-label">${esc(s.label)}</span>
      <span class="chart-legend-value">${formatWeight(s.value)}</span>
    </div>`).join('');

  return `
    <svg viewBox="0 0 140 140" width="140" height="140" style="display:block;margin:0 auto">${paths}</svg>
    <div class="chart-legend">${legend}</div>`;
}

// ── Gear info card popup ──────────────────────────────────────────────────────
const notePopup     = document.getElementById('note-popup');
const notePopupName = document.getElementById('note-popup-name');
const notePopupMeta = document.getElementById('note-popup-meta');
const notePopupStats    = document.getElementById('note-popup-stats');
const notePopupNotes    = document.getElementById('note-popup-notes');
const notePopupVariants = document.getElementById('note-popup-variants');
const notePopupVariantsList = document.getElementById('note-popup-variants-list');

document.getElementById('note-popup-close').addEventListener('click', () => notePopup.classList.add('hidden'));

function openGearCard(trigger) {
  const name     = trigger.dataset.itemName    || '';
  const brand    = trigger.dataset.itemBrand   || '';
  const category = trigger.dataset.itemCategory || '';
  const weight   = trigger.dataset.itemWeight;
  const qty      = trigger.dataset.itemQty;
  const note     = trigger.dataset.note        || '';

  // Header
  notePopupName.textContent = name;
  const metaParts = [brand, category].filter(Boolean);
  notePopupMeta.textContent = metaParts.join(' · ');
  notePopupMeta.style.display = metaParts.length ? '' : 'none';

  // Stat pills
  const stats = [];
  if (weight !== '' && weight != null) stats.push({ label: 'Weight', value: `${weight}g` });
  if (qty)                              stats.push({ label: 'Qty',    value: qty });
  notePopupStats.innerHTML = stats.map(s =>
    `<div class="note-popup-stat">
       <span class="note-popup-stat-label">${s.label}</span>
       <span class="note-popup-stat-value">${esc(String(s.value))}</span>
     </div>`
  ).join('');

  // Notes
  notePopupNotes.textContent = note;

  // Variants — use direct catalog ID if present, else look up by name
  const catId    = trigger.dataset.catalogId;
  const baseName = name.replace(/\s*\([^)]*\)\s*$/, '').trim().toLowerCase();
  const catMatch = catId
    ? catalog.find(c => c._id === catId)
    : catalog.find(c =>
        c.name.toLowerCase() === baseName &&
        (!brand || c.brand.toLowerCase() === brand.toLowerCase())
      ) || catalog.find(c => c.name.toLowerCase() === baseName);

  if (catMatch?.variants?.length) {
    notePopupVariantsList.innerHTML = catMatch.variants.map(v =>
      `<div class="note-popup-variant-row">
         <span>${esc(v.name)}</span>
         <span class="note-popup-variant-weight">${v.weight != null ? v.weight + 'g' : '—'}</span>
       </div>`
    ).join('');
    notePopupVariants.classList.remove('hidden');
  } else {
    notePopupVariants.classList.add('hidden');
  }

  notePopup.classList.remove('hidden');
}

document.addEventListener('click', e => {
  const trigger = e.target.closest('.item-name-link');
  if (trigger) { openGearCard(trigger); return; }
  // legacy note-icon-btn (used in trip pack views)
  const iconBtn = e.target.closest('.note-icon-btn');
  if (iconBtn) {
    notePopupName.textContent = iconBtn.dataset.itemName || '';
    notePopupMeta.textContent = [iconBtn.dataset.itemBrand, iconBtn.dataset.itemWeight ? iconBtn.dataset.itemWeight + 'g' : ''].filter(Boolean).join(' · ');
    notePopupMeta.style.display = notePopupMeta.textContent ? '' : 'none';
    notePopupStats.innerHTML = '';
    notePopupNotes.textContent = iconBtn.dataset.note || '';
    notePopupVariants.classList.add('hidden');
    notePopup.classList.remove('hidden');
    return;
  }
  if (!notePopup.contains(e.target)) notePopup.classList.add('hidden');
});

// ── Navigation ───────────────────────────────────────────────────────────────

document.querySelectorAll('.nav-btn').forEach(btn => {
  btn.addEventListener('click', () => switchView(btn.dataset.view));
});

function switchView(view) {
  currentView = view;
  document.querySelectorAll('.nav-btn').forEach(b => b.classList.toggle('active', b.dataset.view === view));
  document.querySelectorAll('.view').forEach(s => s.classList.toggle('active', s.id === `view-${view}`));
  if (view === 'gear')    { renderGear(); renderBundles(); }
  if (view === 'trips')   { showTripList(); renderTripList(); }
  if (view === 'catalog') renderCatalog();
}

// ── Modal ────────────────────────────────────────────────────────────────────

const overlay          = document.getElementById('modal-overlay');
const modalItem        = document.getElementById('modal-item');
const modalTrip        = document.getElementById('modal-trip');
const modalSuggest     = document.getElementById('modal-suggest');
const modalCatalogEdit = document.getElementById('modal-catalog-edit');

function openModal(el) {
  overlay.classList.remove('hidden');
  el.classList.remove('hidden');
  el.setAttribute('open', '');
}
function closeModal() {
  overlay.classList.add('hidden');
  [modalItem, modalTrip, modalSuggest, modalCatalogEdit].forEach(m => { m.classList.add('hidden'); m.removeAttribute('open'); });
}
overlay.addEventListener('click', e => { if (e.target === overlay) closeModal(); });
document.querySelectorAll('[data-close-modal]').forEach(b => b.addEventListener('click', closeModal));

// ── Gear Locker ──────────────────────────────────────────────────────────────

const gearContainer = document.getElementById('gear-container');
const gearEmpty     = document.getElementById('gear-empty');
const gearSearch    = document.getElementById('gear-search');
const catFilter     = document.getElementById('gear-category-filter');
const catDatalist   = document.getElementById('category-list');
const brandDatalist = document.getElementById('brand-list');

document.getElementById('btn-add-item').addEventListener('click', () => openItemModal());
gearSearch.addEventListener('input', renderGear);
catFilter.addEventListener('change', renderGear);

function categories() {
  return [...new Set(gear.map(g => g.category).filter(Boolean))].sort();
}

function refreshCategoryUI() {
  const cats = categories();
  catDatalist.innerHTML = cats.map(c => `<option value="${esc(c)}">`).join('');
  const current = catFilter.value;
  catFilter.innerHTML = `<option value="">All categories</option>` +
    cats.map(c => `<option value="${esc(c)}" ${c === current ? 'selected' : ''}>${esc(c)}</option>`).join('');
  const brands = [...new Set(gear.map(g => g.brand).filter(Boolean))].sort();
  brandDatalist.innerHTML = brands.map(b => `<option value="${esc(b)}">`).join('');
}

function renderGear() {
  refreshCategoryUI();
  const q   = gearSearch.value.toLowerCase();
  const cat = catFilter.value;
  const filtered = gear.filter(g =>
    (!q   || g.name.toLowerCase().includes(q) || (g.notes || '').toLowerCase().includes(q)) &&
    (!cat || g.category === cat)
  );
  gearEmpty.style.display = filtered.length ? 'none' : 'block';
  gearContainer.style.display = filtered.length ? '' : 'none';

  // Group by category; items with no category go under 'Uncategorised' at the end
  const groups = new Map();
  filtered.forEach(g => {
    const key = g.category?.trim() || '';
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(g);
  });
  const sorted = [...groups.entries()].sort(([a], [b]) => {
    if (!a) return 1;
    if (!b) return -1;
    return a.localeCompare(b);
  });

  gearContainer.innerHTML = sorted.map(([label, items]) => `
    <div class="gear-block">
      <div class="gear-block-header">
        <span class="gear-block-title">${esc(label) || 'Uncategorised'}</span>
        <span class="gear-block-count">${items.length} item${items.length !== 1 ? 's' : ''}</span>
      </div>
      <table class="gear-table">
        <thead>
          <tr>
            <th style="width:100%">Name</th><th style="text-align:right;white-space:nowrap">Qty</th><th></th>
          </tr>
        </thead>
        <tbody>
          ${items.map(g => `
            <tr>
              <td>
                <strong class="item-name-link"
                  data-gear-id="${g.id}"
                  data-item-name="${esc(g.name)}"
                  data-item-brand="${esc(g.brand || '')}"
                  data-item-category="${esc(g.category || '')}"
                  data-item-weight="${g.weight != null ? g.weight : ''}"
                  data-item-qty="${g.qty ?? 1}"
                  data-note="${esc(g.notes || '')}"
                >${esc(g.name)}</strong>
                ${(g.brand || g.weight != null) ? `<div class="item-brand">${[g.brand, g.weight != null && g.weight !== '' ? `${g.weight}g` : null].filter(Boolean).join(' · ')}</div>` : ''}
              </td>
              <td style="text-align:right">${g.qty ?? 1}</td>
              <td class="col-actions">
                <button data-edit="${g.id}">Edit</button>
                <button data-delete="${g.id}" class="del">Delete</button>
              </td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `).join('');
}

gearContainer.addEventListener('click', e => {
  const editId   = e.target.closest('[data-edit]')?.dataset.edit;
  const deleteId = e.target.closest('[data-delete]')?.dataset.delete;
  if (editId)   openItemModal(gear.find(g => g.id === editId));
  if (deleteId) deleteItem(deleteId);
});

function openItemModal(item = null) {
  const form = document.getElementById('form-item');
  form.reset();
  document.getElementById('modal-item-title').textContent = item ? 'Edit Item' : 'Add Item';
  if (item) {
    form.name.value     = item.name;
    form.brand.value    = item.brand || '';
    form.category.value = item.category || '';
    form.weight.value   = item.weight ?? '';
    form.qty.value      = item.qty ?? 1;
    form.notes.value    = item.notes || '';
    form.id.value       = item.id;
  } else {
    form.id.value = '';
  }
  openModal(modalItem);
}

document.getElementById('form-item').addEventListener('submit', async e => {
  e.preventDefault();
  const fd = new FormData(e.target);
  const id = fd.get('id');
  const payload = {
    name:     fd.get('name').trim(),
    brand:    fd.get('brand').trim(),
    category: fd.get('category').trim(),
    weight:   fd.get('weight') !== '' ? parseFloat(fd.get('weight')) : null,
    qty:      parseInt(fd.get('qty')) || 1,
    notes:    fd.get('notes').trim(),
  };
  try {
    let updated;
    if (id) {
      updated = normalizeGear(await api(`/gear/${id}`, { method: 'PUT', body: payload }));
      const idx = gear.findIndex(g => g.id === id);
      if (idx >= 0) gear[idx] = updated;
    } else {
      updated = normalizeGear(await api('/gear', { method: 'POST', body: payload }));
      gear.push(updated);
    }
    closeModal();
    renderGear();
  } catch (err) { alert(err.message); }
});

async function deleteItem(id) {
  if (!confirm('Delete this item from your gear locker?')) return;
  try {
    await api(`/gear/${id}`, { method: 'DELETE' });
    gear = gear.filter(g => g.id !== id);
    trips.forEach(t => {
      (t.packs || []).forEach(pk => { pk.items = (pk.items || []).filter(p => p.gearId !== id); });
    });
    renderGear();
    if (currentTripId) renderTripDetail();
  } catch (err) { alert(err.message); }
}

// ── Bundles ──────────────────────────────────────────────────────────────────

const bundleContainer  = document.getElementById('bundle-container');
const bundlesEmpty     = document.getElementById('bundles-empty');
const expandedBundles  = new Set();

document.getElementById('btn-new-bundle').addEventListener('click', async () => {
  const name = prompt('Bundle name:');
  if (!name?.trim()) return;
  try {
    const b = normalizeBundle(await api('/bundles', { method: 'POST', body: { name: name.trim() } }));
    bundles.push(b);
    renderBundles();
  } catch (err) { alert(err.message); }
});

function renderBundles() {
  bundlesEmpty.style.display    = bundles.length ? 'none' : 'block';
  bundleContainer.style.display = bundles.length ? '' : 'none';

  bundleContainer.innerHTML = bundles.map(b => {
    const resolved = b.items
      .map(item => ({ item, g: gear.find(g => g.id === item.gearId) }))
      .filter(x => x.g);
    const totalWeight = resolved.reduce((sum, { item, g }) => sum + (g.weight ?? 0) * item.qty, 0);
    const exp = expandedBundles.has(b.id);
    return `
      <div class="bundle-block${exp ? ' expanded' : ''}">
        <div class="bundle-block-header" data-toggle-bundle="${b.id}">
          <span class="bundle-chevron">${exp ? '▾' : '▸'}</span>
          <span class="bundle-block-title">${esc(b.name)}</span>
          <span class="bundle-block-count">${resolved.length} item${resolved.length !== 1 ? 's' : ''}${totalWeight ? ` · ${formatWeight(totalWeight)}` : ''}</span>
          <div class="bundle-block-actions">
            <button class="btn-link" data-rename-bundle="${b.id}">Rename</button>
            <button class="bundle-del" data-delete-bundle="${b.id}" title="Delete bundle">×</button>
          </div>
        </div>
        ${exp ? `
        <ul class="bundle-item-list">
          ${resolved.map(({ item, g }) => `
            <li class="bundle-item">
              <div class="bundle-item-info">
                <span class="bundle-item-name">${esc(g.name)}</span>
                ${(g.brand || g.weight != null) ? `<span class="bundle-item-meta">${[g.brand, g.weight != null ? g.weight + 'g' : null].filter(Boolean).join(' · ')}</span>` : ''}
              </div>
              <div class="pack-item-qty">
                <button data-bqty-dec="${b.id}" data-bgear="${g.id}">−</button>
                <span>${item.qty}</span>
                <button data-bqty-inc="${b.id}" data-bgear="${g.id}">+</button>
              </div>
              <button class="pack-item-remove" data-bremove="${b.id}" data-bgear="${g.id}" title="Remove">✕</button>
            </li>`).join('')}
        </ul>
        <div class="bundle-add-gear">
          <input type="text" class="bundle-search" data-bundle-id="${b.id}" placeholder="Search gear to add…" autocomplete="off" />
          <ul class="bundle-search-results" data-bundle-results="${b.id}"></ul>
        </div>` : ''}
      </div>`;
  }).join('');
}

bundleContainer.addEventListener('click', async e => {
  const toggleId  = !e.target.closest('[data-rename-bundle],[data-delete-bundle]')
                      ? e.target.closest('[data-toggle-bundle]')?.dataset.toggleBundle
                      : null;
  const renameId  = e.target.closest('[data-rename-bundle]')?.dataset.renameBundle;
  const deleteId  = e.target.closest('[data-delete-bundle]')?.dataset.deleteBundle;
  const incEl     = e.target.closest('[data-bqty-inc]');
  const decEl     = e.target.closest('[data-bqty-dec]');
  const removeEl  = e.target.closest('[data-bremove]');
  const addEl     = e.target.closest('[data-badd]');

  if (toggleId) {
    expandedBundles.has(toggleId) ? expandedBundles.delete(toggleId) : expandedBundles.add(toggleId);
    renderBundles();
    return;
  }

  if (renameId) {
    const b = bundles.find(b => b.id === renameId);
    const name = prompt('Bundle name:', b?.name || '');
    if (!name?.trim() || !b) return;
    b.name = name.trim();
    await saveBundle(b);
  }
  if (deleteId && confirm('Delete this bundle?')) {
    try {
      await api(`/bundles/${deleteId}`, { method: 'DELETE' });
      bundles = bundles.filter(b => b.id !== deleteId);
      renderBundles();
    } catch (err) { alert(err.message); }
  }
  if (incEl) {
    const b = bundles.find(b => b.id === incEl.dataset.bqtyInc);
    const item = b?.items.find(i => i.gearId === incEl.dataset.bgear);
    if (item) { item.qty++; await saveBundle(b); }
  }
  if (decEl) {
    const b = bundles.find(b => b.id === decEl.dataset.bqtyDec);
    const item = b?.items.find(i => i.gearId === decEl.dataset.bgear);
    if (item) { item.qty = Math.max(1, item.qty - 1); await saveBundle(b); }
  }
  if (removeEl) {
    const b = bundles.find(b => b.id === removeEl.dataset.bremove);
    if (b) { b.items = b.items.filter(i => i.gearId !== removeEl.dataset.bgear); await saveBundle(b); }
  }
  if (addEl) {
    const b = bundles.find(b => b.id === addEl.dataset.badd);
    if (b && !b.items.find(i => i.gearId === addEl.dataset.bgear)) {
      b.items.push({ gearId: addEl.dataset.bgear, qty: 1 });
      await saveBundle(b);
    }
  }
});

bundleContainer.addEventListener('input', e => {
  const input = e.target.closest('.bundle-search');
  if (!input) return;
  const bid     = input.dataset.bundleId;
  const b       = bundles.find(b => b.id === bid);
  const results = bundleContainer.querySelector(`[data-bundle-results="${bid}"]`);
  if (!b || !results) return;
  const q = input.value.toLowerCase().trim();
  if (!q) { results.innerHTML = ''; return; }
  const inBundle = new Set(b.items.map(i => i.gearId));
  const matches  = gear
    .filter(g => !inBundle.has(g.id) &&
      (g.name.toLowerCase().includes(q) || (g.brand || '').toLowerCase().includes(q) || (g.category || '').toLowerCase().includes(q)))
    .slice(0, 8);
  results.innerHTML = matches.length
    ? matches.map(g => `
        <li class="bundle-result-item">
          <div class="bundle-result-info">
            <span class="bundle-result-name">${esc(g.name)}</span>
            ${(g.brand || g.weight != null) ? `<span class="bundle-result-meta">${[g.brand, g.weight != null ? g.weight + 'g' : null].filter(Boolean).join(' · ')}</span>` : ''}
          </div>
          <button class="picker-item-add" data-badd="${bid}" data-bgear="${g.id}">+</button>
        </li>`).join('')
    : '<li style="padding:0.3rem 0.4rem;font-size:0.82rem;color:var(--text-muted)">No gear found.</li>';
});

async function saveBundle(b) {
  try {
    const updated = normalizeBundle(await api(`/bundles/${b.id}`, { method: 'PUT', body: { name: b.name, items: b.items } }));
    const idx = bundles.findIndex(x => x.id === b.id);
    if (idx >= 0) bundles[idx] = updated;
    renderBundles();
  } catch (err) { alert(err.message); }
}

// ── Trips ────────────────────────────────────────────────────────────────────

const tripListEl      = document.getElementById('trip-list');
const tripsEmpty      = document.getElementById('trips-empty');
const tripListPanel   = document.getElementById('trip-list-panel');
const tripDetailPanel = document.getElementById('trip-detail-panel');

document.getElementById('btn-add-trip').addEventListener('click', () => openTripModal());
document.getElementById('btn-back-trips').addEventListener('click', showTripList);
document.getElementById('btn-edit-trip').addEventListener('click', () => {
  const t = trips.find(t => t.id === currentTripId);
  if (t) openTripModal(t);
});
document.getElementById('btn-delete-trip').addEventListener('click', async () => {
  if (!confirm('Delete this trip?')) return;
  try {
    await api(`/trips/${currentTripId}`, { method: 'DELETE' });
    trips = trips.filter(t => t.id !== currentTripId);
    showTripList();
    renderTripList();
  } catch (err) { alert(err.message); }
});

document.getElementById('btn-archive-trip').addEventListener('click', async () => {
  const trip = trips.find(t => t.id === currentTripId);
  if (!trip) return;
  const isArchived = trip.archived;
  if (!isArchived && !confirm('Archive this trip? Gear data will be frozen as-is.')) return;
  try {
    let payload;
    if (isArchived) {
      // Unarchive: clear frozen data
      payload = { ...trip, archived: false, frozenGear: null, frozenBundles: null };
    } else {
      // Archive: snapshot current gear + bundles referenced by this trip
      const packGearIds = new Set((trip.packs || []).flatMap(pk => (pk.items || []).map(i => i.gearId)));
      const bundleIds   = new Set((trip.packs || []).flatMap(pk => (pk.bundleRefs || []).map(br => br.bundleId)));
      const frozenBundles = bundles.filter(b => bundleIds.has(b.id));
      const bundleGearIds = new Set(frozenBundles.flatMap(b => b.items.map(i => i.gearId)));
      const allGearIds = new Set([...packGearIds, ...bundleGearIds]);
      const frozenGear = gear.filter(g => allGearIds.has(g.id));
      payload = { ...trip, archived: true, frozenGear, frozenBundles };
    }
    const updated = normalizeTrip(await api(`/trips/${currentTripId}`, { method: 'PUT', body: payload }));
    const idx = trips.findIndex(t => t.id === currentTripId);
    if (idx >= 0) trips[idx] = updated;
    renderTripList();
    renderTripDetail();
  } catch (err) { alert(err.message); }
});

function showTripList() {
  tripListPanel.classList.remove('hidden');
  tripDetailPanel.classList.add('hidden');
  currentTripId = null;
}

function renderTripCard(t) {
  const itemCount = (t.packs || []).reduce((sum, pk) => sum + (pk.items || []).length, 0);
  const meta = [t.destination, formatDateRange(t.startDate, t.endDate)].filter(Boolean).join(' · ');
  return `
    <li>
      <div class="trip-card${t.archived ? ' trip-card-archived' : ''}" data-trip="${t.id}">
        <div class="trip-card-info">
          <h4>${esc(t.name)}${t.archived ? ' <span class="trip-archived-badge">Completed</span>' : ''}</h4>
          ${meta ? `<div class="meta">${esc(meta)}</div>` : ''}
        </div>
        <span class="trip-card-badge">${itemCount} item${itemCount !== 1 ? 's' : ''}</span>
      </div>
    </li>`;
}

function renderTripList() {
  const upcoming  = trips.filter(t => !t.archived);
  const completed = trips.filter(t =>  t.archived);
  const hasAny = upcoming.length + completed.length > 0;
  tripsEmpty.style.display = hasAny ? 'none' : 'block';
  let html = '';
  if (upcoming.length) {
    html += `<li class="trip-section-header">Upcoming Trips</li>`;
    html += upcoming.map(renderTripCard).join('');
  }
  if (completed.length) {
    html += `<li class="trip-section-header">Completed Trips</li>`;
    html += completed.map(renderTripCard).join('');
  }
  tripListEl.innerHTML = html;
}

tripListEl.addEventListener('click', e => {
  const card = e.target.closest('[data-trip]');
  if (card) showTripDetail(card.dataset.trip);
});

function openTripModal(trip = null) {
  const form = document.getElementById('form-trip');
  form.reset();
  document.getElementById('modal-trip-title').textContent = trip ? 'Edit Trip' : 'New Trip';
  if (trip) {
    form.name.value        = trip.name;
    form.destination.value = trip.destination || '';
    form.startDate.value   = trip.startDate || '';
    form.endDate.value     = trip.endDate || '';
    form.notes.value       = trip.notes || '';
    form.id.value          = trip.id;
  } else {
    form.id.value = '';
  }
  openModal(modalTrip);
}

document.getElementById('form-trip').addEventListener('submit', async e => {
  e.preventDefault();
  const fd = new FormData(e.target);
  const id = fd.get('id');
  const payload = {
    name:        fd.get('name').trim(),
    destination: fd.get('destination').trim(),
    startDate:   fd.get('startDate'),
    endDate:     fd.get('endDate'),
    notes:       fd.get('notes').trim(),
  };
  try {
    let updated;
    if (id) {
      const existing = trips.find(t => t.id === id);
      updated = normalizeTrip(await api(`/trips/${id}`, { method: 'PUT', body: { ...payload, packs: existing?.packs || [], archived: existing?.archived ?? false, frozenGear: existing?.frozenGear ?? null, frozenBundles: existing?.frozenBundles ?? null } }));
      const idx = trips.findIndex(t => t.id === id);
      if (idx >= 0) trips[idx] = updated;
    } else {
      updated = normalizeTrip(await api('/trips', { method: 'POST', body: payload }));
      trips.push(updated);
    }
    closeModal();
    renderTripList();
    if (id && currentTripId === id) renderTripDetail();
    if (!id) showTripDetail(updated.id);
  } catch (err) { alert(err.message); }
});

// ── Trip detail / pack ───────────────────────────────────────────────────────

const pickerList   = document.getElementById('picker-list');
const pickerSearch = document.getElementById('picker-search');
const packTabsArea = document.getElementById('pack-tabs-area');
const packBodyArea = document.getElementById('pack-body-area');

pickerSearch.addEventListener('input', renderPicker);

function showTripDetail(id) {
  currentTripId  = id;
  currentPackIdx = 0;
  tripListPanel.classList.add('hidden');
  tripDetailPanel.classList.remove('hidden');
  renderTripDetail();
}

function renderTripDetail() {
  const trip = trips.find(t => t.id === currentTripId);
  if (!trip) return showTripList();
  document.getElementById('trip-detail-name').textContent = trip.name;
  const meta = [trip.destination, formatDateRange(trip.startDate, trip.endDate)].filter(Boolean).join(' · ');
  document.getElementById('trip-detail-meta').textContent = meta;
  const notesEl = document.getElementById('trip-detail-notes');
  notesEl.textContent = trip.notes || '';
  notesEl.classList.toggle('hidden', !trip.notes);
  // Toggle controls based on archived state
  const archiveBtn = document.getElementById('btn-archive-trip');
  const editBtn    = document.getElementById('btn-edit-trip');
  archiveBtn.textContent = trip.archived ? 'Unarchive' : 'Archive';
  editBtn.classList.toggle('hidden', !!trip.archived);
  // Archived banner
  let bannerEl = document.getElementById('trip-archived-banner');
  if (!bannerEl) {
    bannerEl = document.createElement('div');
    bannerEl.id = 'trip-archived-banner';
    bannerEl.className = 'trip-archived-banner';
    bannerEl.textContent = '📦 This trip is archived — gear is frozen at the time of completion.';
    const nameEl = document.getElementById('trip-detail-name');
    nameEl.parentNode.insertBefore(bannerEl, nameEl.nextSibling);
  }
  bannerEl.classList.toggle('hidden', !trip.archived);
  const packs = trip.packs || [];
  if (currentPackIdx >= packs.length) currentPackIdx = Math.max(0, packs.length - 1);
  renderPackSection(trip);
  renderPicker();
}

function renderPackSection(trip) {
  const packs    = trip.packs || [];
  const archived = !!trip.archived;
  // Use frozen snapshots for archived trips, live data otherwise
  const gearSrc    = archived && trip.frozenGear    ? trip.frozenGear    : gear;
  const bundleSrc  = archived && trip.frozenBundles ? trip.frozenBundles : bundles;

  packTabsArea.innerHTML = `
    <div class="pack-tabs">
      ${packs.map((pk, i) => `
        <button class="pack-tab${i === currentPackIdx ? ' active' : ''}" data-tab="${i}">
          ${esc(pk.name || `Pack ${i + 1}`)}
          ${!archived && packs.length > 1 ? `<span class="pack-tab-del" data-del-pack="${i}" title="Remove pack">×</span>` : ''}
        </button>
      `).join('')}
      ${!archived ? `<button class="pack-tab pack-tab-new" data-new-pack>+ Pack</button>` : ''}
    </div>`;

  const pack = packs[currentPackIdx];
  if (!pack) { packBodyArea.innerHTML = ''; return; }

  const items = pack.items || [];
  const bundleRefs = pack.bundleRefs || [];
  let baseWeight = 0, wornWeight = 0, consumableWeight = 0;
  items.forEach(p => {
    const g = gearSrc.find(g => g.id === p.gearId);
    if (!g?.weight) return;
    const w = g.weight * p.qty;
    if (p.type === 'worn') wornWeight += w;
    else if (p.type === 'consumable') consumableWeight += w;
    else baseWeight += w;
  });
  bundleRefs.forEach(br => {
    const b = bundleSrc.find(b => b.id === br.bundleId);
    if (!b) return;
    b.items.forEach(({ gearId, qty }) => {
      const g = gearSrc.find(g => g.id === gearId);
      if (!g?.weight) return;
      const w = g.weight * qty;
      const itemType = (br.itemTypes || []).find(t => t.gearId === gearId)?.type || 'base';
      if (itemType === 'worn') wornWeight += w;
      else if (itemType === 'consumable') consumableWeight += w;
      else baseWeight += w;
    });
  });
  const itemCheckedCount = items.filter(p => p.checked).length;
  const bundleCheckedCount = bundleRefs.reduce((sum, br) => {
    const b = bundleSrc.find(b => b.id === br.bundleId);
    return sum + (b?.items.filter(i => br.checkedItems.includes(i.gearId)).length || 0);
  }, 0);
  const bundleTotalCount = bundleRefs.reduce((sum, br) => {
    const b = bundleSrc.find(b => b.id === br.bundleId);
    return sum + (b?.items.length || 0);
  }, 0);
  const totalChecked = itemCheckedCount + bundleCheckedCount;
  const totalCount = items.length + bundleTotalCount;
  const statsText = totalCount ? `${totalChecked}/${totalCount} packed` : '';

  const cubes    = pack.cubes || [];
  const hasCubes = cubes.length > 0;

  function renderItem(p) {
    const g = gearSrc.find(g => g.id === p.gearId);
    if (!g) return '';
    const lineWeight = g.weight != null ? formatWeight(g.weight * p.qty) : null;
    const itemType = p.type || 'base';
    return `
      <li class="pack-item${p.checked ? ' pack-item-checked' : ''}"${!archived ? ` draggable="true" data-drag-id="${g.id}"` : ''}>
        ${!archived ? `<span class="drag-handle" title="Drag to cube">⠿</span>` : ''}
        <input type="checkbox" class="pack-check" data-check="${g.id}" ${p.checked ? 'checked' : ''} />
        <div class="pack-item-info">
          <div class="pack-item-name">${esc(g.name)}</div>
          <div class="pack-item-meta">${[g.category, lineWeight].filter(Boolean).join(' · ') || '—'}</div>
        </div>
        ${!archived ? `
        <div class="pack-item-qty">
          <button data-qty-dec="${g.id}">−</button>
          <span>${p.qty}</span>
          <button data-qty-inc="${g.id}">+</button>
        </div>
        <div class="item-type-toggle">
          <button class="item-type-btn${itemType === 'worn' ? ' active' : ''}" data-type-set="${g.id}" data-type="${itemType === 'worn' ? 'base' : 'worn'}" title="Worn"><svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"><path d="M5 2Q6.5 5 8 5Q9.5 5 11 2L14 4l-2 3-2-1v7H6V6L4 7 2 4z"/></svg></button>
          <button class="item-type-btn${itemType === 'consumable' ? ' active' : ''}" data-type-set="${g.id}" data-type="${itemType === 'consumable' ? 'base' : 'consumable'}" title="Consumable"><svg viewBox="0 0 16 16" width="13" height="13" fill="currentColor" stroke="none"><path d="M8 1.5L4 9.5a4 4 0 008 0z"/></svg></button>
        </div>
        <button class="pack-item-remove" data-remove="${g.id}" title="Remove">✕</button>` : `<span class="pack-item-qty-label">×${p.qty}</span>`}
      </li>`;
  }

  const ungrouped = items.filter(p => !p.cubeId || !cubes.find(c => c.id === p.cubeId));

  function renderBundleGroup(br) {
    const b = bundleSrc.find(b => b.id === br.bundleId);
    if (!b) return '';
    const bItems = b.items.filter(i => gearSrc.find(g => g.id === i.gearId));
    const bChecked = bItems.filter(i => br.checkedItems.includes(i.gearId)).length;
    const exp = br.expanded;
    return `
      <div class="pack-bundle-group${exp ? ' expanded' : ''}">
        <div class="pack-bundle-header" data-toggle-bundle="${b.id}"${!archived ? ` draggable="true" data-drag-bundle="${b.id}"` : ''}>
          ${!archived ? `<span class="drag-handle" title="Drag to cube">⠿</span>` : ''}
          <span class="pack-bundle-chevron">${exp ? '▾' : '▸'}</span>
          <span class="pack-bundle-name">${esc(b.name)}</span>
          <span class="pack-bundle-stats">${bChecked}/${bItems.length} packed</span>
          ${!archived ? `<button class="pack-bundle-remove" data-remove-bundle="${b.id}" title="Remove bundle">✕</button>` : ''}
        </div>
        ${exp ? `<ul class="pack-bundle-items">
          ${bItems.map(({ gearId, qty }) => {
            const g = gearSrc.find(g => g.id === gearId);
            if (!g) return '';
            const checked = br.checkedItems.includes(gearId);
            const lineWeight = g.weight != null ? formatWeight(g.weight * qty) : null;
            const itemType = (br.itemTypes || []).find(t => t.gearId === gearId)?.type || 'base';
            return `
              <li class="pack-item${checked ? ' pack-item-checked' : ''}">
                <input type="checkbox" class="pack-check" data-bundle-check="${gearId}" data-bundle-id="${b.id}" ${checked ? 'checked' : ''} />
                <div class="pack-item-info">
                  <div class="pack-item-name">${esc(g.name)}</div>
                  <div class="pack-item-meta">${[g.category, lineWeight].filter(Boolean).join(' · ') || '—'}</div>
                </div>
                ${qty > 1 ? `<span class="pack-bundle-qty">×${qty}</span>` : ''}
                ${!archived ? `<div class="item-type-toggle">
                  <button class="item-type-btn${itemType === 'worn' ? ' active' : ''}" data-bundle-type-set="${gearId}" data-bundle-id="${b.id}" data-type="${itemType === 'worn' ? 'base' : 'worn'}" title="Worn"><svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"><path d="M5 2Q6.5 5 8 5Q9.5 5 11 2L14 4l-2 3-2-1v7H6V6L4 7 2 4z"/></svg></button>
                  <button class="item-type-btn${itemType === 'consumable' ? ' active' : ''}" data-bundle-type-set="${gearId}" data-bundle-id="${b.id}" data-type="${itemType === 'consumable' ? 'base' : 'consumable'}" title="Consumable"><svg viewBox="0 0 16 16" width="13" height="13" fill="currentColor" stroke="none"><path d="M8 1.5L4 9.5a4 4 0 008 0z"/></svg></button>
                </div>` : ''}
              </li>`;
          }).join('')}
        </ul>` : ''}
      </div>`;
  }

  const ungroupedBundles = bundleRefs.filter(br => !br.cubeId || !cubes.find(c => c.id === br.cubeId));

  packBodyArea.innerHTML = `
    <div class="pack-name-row">
      <span class="pack-name-label">${esc(pack.name || `Pack ${currentPackIdx + 1}`)}</span>
      <button class="btn-link" data-rename-pack>Rename</button>
      ${totalCount ? `<button class="btn-link" data-reset-checklist>Reset</button>` : ''}
    </div>
    ${statsText ? `<p class="pack-stats">${statsText}</p>` : ''}
    ${baseWeight || wornWeight || consumableWeight ? `
    <div class="pack-weights">
      ${baseWeight ? `<span class="pack-weight-row"><span class="pack-weight-label">Base</span>${formatWeight(baseWeight)}</span>` : ''}
      ${wornWeight ? `<span class="pack-weight-row"><span class="pack-weight-label">Worn</span>${formatWeight(wornWeight)}</span>` : ''}
      ${consumableWeight ? `<span class="pack-weight-row"><span class="pack-weight-label">Consumable</span>${formatWeight(consumableWeight)}</span>` : ''}
      <button class="pack-chart-btn" data-weight-chart title="Weight breakdown"><svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><circle cx="8" cy="8" r="6"/><path d="M8 2v6l4 3"/></svg></button>
    </div>` : ''}

    ${cubes.map(c => {
      const cubeItems = items.filter(p => p.cubeId === c.id);
      const cubeBundles = bundleRefs.filter(br => br.cubeId === c.id);
      return `
        <div class="cube-block" data-drop-zone="${c.id}">
          <div class="cube-header">
            <span class="cube-name">${esc(c.name)}</span>
            <button class="btn-link" data-rename-cube="${c.id}">Rename</button>
            <button class="cube-del" data-del-cube="${c.id}" title="Remove cube">×</button>
          </div>
          ${cubeBundles.map(renderBundleGroup).join('')}
          <ul class="pack-list">${cubeItems.map(renderItem).join('')}</ul>
          ${!cubeItems.length && !cubeBundles.length ? '<p class="cube-empty">Drag items here to group them.</p>' : ''}
        </div>`;
    }).join('')}

    ${ungrouped.length || ungroupedBundles.length || !hasCubes ? `
      <div class="cube-block cube-ungrouped" data-drop-zone="ungrouped">
        ${hasCubes ? '<div class="cube-header"><span class="cube-name">Ungrouped</span></div>' : ''}
        ${ungroupedBundles.map(renderBundleGroup).join('')}
        <ul class="pack-list">${ungrouped.map(renderItem).join('')}</ul>
        ${!items.length && !bundleRefs.length ? '<p class="empty-msg">No items in this pack yet.</p>' : ''}
      </div>` : ''}

    <button class="btn-new-cube" data-new-cube>+ Add Cube</button>`;
}

async function savePack(trip) {
  try {
    const updated = normalizeTrip(await api(`/trips/${trip.id}`, { method: 'PUT', body: trip }));
    const idx = trips.findIndex(t => t.id === trip.id);
    if (idx >= 0) trips[idx] = updated;
    if (currentPackIdx >= updated.packs.length) currentPackIdx = Math.max(0, updated.packs.length - 1);
    renderPackSection(updated);
    renderPicker();
    renderTripList();
  } catch (err) { alert(err.message); }
}

packTabsArea.addEventListener('click', e => {
  const trip = trips.find(t => t.id === currentTripId);
  if (!trip) return;

  const tabIdx = e.target.closest('[data-tab]')?.dataset.tab;
  const delIdx = e.target.closest('[data-del-pack]')?.dataset.delPack;
  const isNew  = e.target.closest('[data-new-pack]');

  if (tabIdx !== undefined && !e.target.closest('[data-del-pack]')) {
    currentPackIdx = parseInt(tabIdx);
    renderPackSection(trip);
    renderPicker();
    return;
  }
  if (delIdx !== undefined) {
    const i = parseInt(delIdx);
    const pack = trip.packs[i];
    if (pack.items.length && !confirm(`Remove "${pack.name || `Pack ${i + 1}`}" and its ${pack.items.length} item(s)?`)) return;
    trip.packs.splice(i, 1);
    if (currentPackIdx >= trip.packs.length) currentPackIdx = trip.packs.length - 1;
    savePack(trip);
    return;
  }
  if (isNew) {
    trip.packs.push({ name: `Pack ${trip.packs.length + 1}`, items: [] });
    currentPackIdx = trip.packs.length - 1;
    savePack(trip);
  }
});

packBodyArea.addEventListener('click', e => {
  const trip = trips.find(t => t.id === currentTripId);
  if (!trip) return;
  const pack = trip.packs[currentPackIdx];
  if (!pack) return;

  const incId         = e.target.closest('[data-qty-inc]')?.dataset.qtyInc;
  const decId         = e.target.closest('[data-qty-dec]')?.dataset.qtyDec;
  const remId         = e.target.closest('[data-remove]')?.dataset.remove;
  const removeBundleId = e.target.closest('[data-remove-bundle]')?.dataset.removeBundle;
  const toggleBundleId = !removeBundleId ? e.target.closest('[data-toggle-bundle]')?.dataset.toggleBundle : null;
  const isRenamePack  = e.target.closest('[data-rename-pack]');
  const renameCubeId  = e.target.closest('[data-rename-cube]')?.dataset.renameCube;
  const delCubeId     = e.target.closest('[data-del-cube]')?.dataset.delCube;
  const isNewCube     = e.target.closest('[data-new-cube]');
  const typeBtn       = e.target.closest('[data-type-set]');

  if (incId) {
    const p = pack.items.find(p => p.gearId === incId);
    if (p) { p.qty++; savePack(trip); }
  }
  if (decId) {
    const idx = pack.items.findIndex(p => p.gearId === decId);
    if (idx >= 0) {
      pack.items[idx].qty--;
      if (pack.items[idx].qty <= 0) pack.items.splice(idx, 1);
      savePack(trip);
    }
  }
  if (remId) {
    pack.items = pack.items.filter(p => p.gearId !== remId);
    savePack(trip);
  }
  if (removeBundleId) {
    pack.bundleRefs = (pack.bundleRefs || []).filter(br => br.bundleId !== removeBundleId);
    savePack(trip);
  }
  if (toggleBundleId) {
    const br = (pack.bundleRefs || []).find(br => br.bundleId === toggleBundleId);
    if (br) { br.expanded = !br.expanded; renderPackSection(trip); }
  }
  if (isRenamePack) {
    const newName = prompt('Pack name:', pack.name || `Pack ${currentPackIdx + 1}`);
    if (newName === null) return;
    pack.name = newName.trim() || `Pack ${currentPackIdx + 1}`;
    savePack(trip);
  }
  if (renameCubeId) {
    const cube = pack.cubes.find(c => c.id === renameCubeId);
    if (!cube) return;
    const newName = prompt('Cube name:', cube.name);
    if (newName === null) return;
    cube.name = newName.trim() || cube.name;
    savePack(trip);
  }
  if (delCubeId) {
    const cube = pack.cubes.find(c => c.id === delCubeId);
    const cubeItems = pack.items.filter(p => p.cubeId === delCubeId);
    if (cubeItems.length && !confirm(`Remove cube "${cube?.name}"? Its ${cubeItems.length} item(s) will become ungrouped.`)) return;
    pack.cubes = pack.cubes.filter(c => c.id !== delCubeId);
    pack.items.forEach(p => { if (p.cubeId === delCubeId) p.cubeId = null; });
    savePack(trip);
  }
  if (isNewCube) {
    const name = prompt('Cube name:', `Cube ${(pack.cubes || []).length + 1}`);
    if (name === null) return;
    pack.cubes = pack.cubes || [];
    pack.cubes.push({ name: name.trim() || `Cube ${pack.cubes.length + 1}` });
    savePack(trip);
  }
  if (typeBtn) {
    const p = pack.items.find(p => p.gearId === typeBtn.dataset.typeSet);
    if (p) { p.type = typeBtn.dataset.type; savePack(trip); }
  }
  const bundleTypeBtn = e.target.closest('[data-bundle-type-set]');
  if (bundleTypeBtn) {
    const br = (pack.bundleRefs || []).find(br => br.bundleId === bundleTypeBtn.dataset.bundleId);
    if (br) {
      const gearId = bundleTypeBtn.dataset.bundleTypeSet;
      br.itemTypes = br.itemTypes || [];
      const existing = br.itemTypes.find(t => t.gearId === gearId);
      if (existing) existing.type = bundleTypeBtn.dataset.type;
      else br.itemTypes.push({ gearId, type: bundleTypeBtn.dataset.type });
      savePack(trip);
    }
  }
  const isReset = e.target.closest('[data-reset-checklist]');
  if (isReset) {
    pack.items.forEach(p => { p.checked = false; });
    (pack.bundleRefs || []).forEach(br => { br.checkedItems = []; });
    savePack(trip);
  }
  if (e.target.closest('[data-weight-chart]')) {
    const byCategory = {};
    pack.items.forEach(p => {
      const g = gear.find(g => g.id === p.gearId);
      if (!g?.weight) return;
      const cat = g.category || 'Uncategorized';
      byCategory[cat] = (byCategory[cat] || 0) + g.weight * p.qty;
    });
    (pack.bundleRefs || []).forEach(br => {
      const b = bundles.find(b => b.id === br.bundleId);
      if (!b) return;
      b.items.forEach(({ gearId, qty }) => {
        const g = gear.find(g => g.id === gearId);
        if (!g?.weight) return;
        const itemType = (br.itemTypes || []).find(t => t.gearId === gearId)?.type || 'base';
        if (itemType !== 'base') return;
        const cat = g.category || 'Uncategorized';
        byCategory[cat] = (byCategory[cat] || 0) + g.weight * qty;
      });
    });
    weightChartContent.innerHTML = buildWeightChart(byCategory);
    weightChartPopup.classList.remove('hidden');
  }
});

packBodyArea.addEventListener('change', e => {
  const trip = trips.find(t => t.id === currentTripId);
  if (!trip) return;
  const pack = trip.packs[currentPackIdx];
  if (!pack) return;

  const checkEl = e.target.closest('[data-check]');
  if (checkEl) {
    const p = pack.items.find(p => p.gearId === checkEl.dataset.check);
    if (p) {
      p.checked = checkEl.checked;
      savePack(trip);
    }
  }
  const bundleCheckEl = e.target.closest('[data-bundle-check]');
  if (bundleCheckEl) {
    const br = (pack.bundleRefs || []).find(br => br.bundleId === bundleCheckEl.dataset.bundleId);
    if (br) {
      const gearId = bundleCheckEl.dataset.bundleCheck;
      if (bundleCheckEl.checked) {
        if (!br.checkedItems.includes(gearId)) br.checkedItems.push(gearId);
      } else {
        br.checkedItems = br.checkedItems.filter(id => id !== gearId);
      }
      savePack(trip);
    }
  }
});

// ── Drag-and-drop cube assignment ─────────────────────────────────────────────

packBodyArea.addEventListener('dragstart', e => {
  const bundleHeader = e.target.closest('[data-drag-bundle]');
  if (bundleHeader) {
    e.dataTransfer.setData('text/plain', `bundle:${bundleHeader.dataset.dragBundle}`);
    e.dataTransfer.effectAllowed = 'move';
    bundleHeader.closest('.pack-bundle-group')?.classList.add('dragging');
    return;
  }
  const item = e.target.closest('.pack-item[draggable]');
  if (!item) return;
  e.dataTransfer.setData('text/plain', item.dataset.dragId);
  e.dataTransfer.effectAllowed = 'move';
  item.classList.add('dragging');
});

packBodyArea.addEventListener('dragend', e => {
  packBodyArea.querySelectorAll('.dragging').forEach(el => el.classList.remove('dragging'));
  packBodyArea.querySelectorAll('.drag-over').forEach(el => el.classList.remove('drag-over'));
});

packBodyArea.addEventListener('dragover', e => {
  const zone = e.target.closest('[data-drop-zone]');
  if (!zone) return;
  e.preventDefault();
  e.dataTransfer.dropEffect = 'move';
  packBodyArea.querySelectorAll('.drag-over').forEach(el => el !== zone && el.classList.remove('drag-over'));
  zone.classList.add('drag-over');
});

packBodyArea.addEventListener('dragleave', e => {
  const zone = e.target.closest('[data-drop-zone]');
  if (zone && !zone.contains(e.relatedTarget)) zone.classList.remove('drag-over');
});

packBodyArea.addEventListener('drop', e => {
  e.preventDefault();
  const zone = e.target.closest('[data-drop-zone]');
  if (!zone) return;
  zone.classList.remove('drag-over');
  const raw = e.dataTransfer.getData('text/plain');
  const trip = trips.find(t => t.id === currentTripId);
  if (!trip) return;
  const pack = trip.packs[currentPackIdx];
  if (!pack) return;
  const newCubeId = zone.dataset.dropZone === 'ungrouped' ? null : zone.dataset.dropZone;
  if (raw.startsWith('bundle:')) {
    const bundleId = raw.slice(7);
    const br = (pack.bundleRefs || []).find(br => br.bundleId === bundleId);
    if (br) { br.cubeId = newCubeId; savePack(trip); }
    return;
  }
  const p = pack.items.find(p => p.gearId === raw);
  if (!p) return;
  p.cubeId = newCubeId;
  savePack(trip);
});

function renderPickerBundles() {
  const section = document.getElementById('picker-bundles-section');
  if (!section) return;
  if (!bundles.length) { section.innerHTML = ''; return; }
  const trip = trips.find(t => t.id === currentTripId);
  const pack = trip?.packs[currentPackIdx];
  const addedBundleIds = new Set((pack?.bundleRefs || []).map(br => br.bundleId));
  section.innerHTML = `
    <h3>Bundles</h3>
    <ul class="picker-bundle-list">
      ${bundles.map(b => {
        const validItems = b.items.filter(i => gear.find(g => g.id === i.gearId));
        const already = addedBundleIds.has(b.id);
        return `
          <li class="picker-bundle-item">
            <div class="picker-bundle-info">
              <span class="picker-bundle-name">${esc(b.name)}</span>
              <span class="picker-bundle-count">${validItems.length} item${validItems.length !== 1 ? 's' : ''}</span>
            </div>
            <button class="picker-bundle-add${already ? ' in-pack' : ''}" data-add-bundle="${b.id}" ${already ? 'disabled' : ''}>${already ? '✓' : '+ Add'}</button>
          </li>`;
      }).join('')}
    </ul>
    <div class="picker-section-divider"></div>`;
}

function renderPicker() {
  const trip = trips.find(t => t.id === currentTripId);
  if (!trip) return;
  renderPickerBundles();
  const q = pickerSearch.value.toLowerCase();
  const filtered = gear.filter(g =>
    !q || g.name.toLowerCase().includes(q) || (g.category || '').toLowerCase().includes(q)
  );
  const pack = trip.packs[currentPackIdx];
  const inPack = new Set((pack?.items || []).map(p => p.gearId));

  const categories = [...new Set(filtered.map(g => g.category || 'Uncategorized'))].sort();

  if (!filtered.length) {
    pickerList.innerHTML = '<li style="padding:0.5rem;color:var(--text-muted);font-size:0.85rem">No gear found.</li>';
    return;
  }

  pickerList.innerHTML = categories.map(cat => {
    const items = filtered.filter(g => (g.category || 'Uncategorized') === cat);
    return `
      <li class="picker-category-group">
        <div class="picker-category-label">${esc(cat)}</div>
        <ul class="picker-category-items">
          ${items.map(g => {
            const already = inPack.has(g.id);
            const meta = [g.brand, g.weight != null ? `${g.weight}g` : null].filter(Boolean).join(' · ');
            return `
              <li class="picker-item">
                <div class="picker-item-name">${esc(g.name)}</div>
                ${meta ? `<div class="picker-item-meta">${meta}</div>` : ''}
                <button class="picker-item-add ${already ? 'in-pack' : ''}"
                        data-add="${g.id}" ${already ? 'disabled' : ''}>
                  ${already ? '✓' : '+'}
                </button>
              </li>`;
          }).join('')}
        </ul>
      </li>`;
  }).join('');
}

document.getElementById('picker-bundles-section').addEventListener('click', e => {
  const addBundleEl = e.target.closest('[data-add-bundle]');
  if (!addBundleEl) return;
  const b = bundles.find(b => b.id === addBundleEl.dataset.addBundle);
  if (!b) return;
  const trip = trips.find(t => t.id === currentTripId);
  if (!trip) return;
  const pack = trip.packs[currentPackIdx];
  if (!pack) return;
  pack.bundleRefs = pack.bundleRefs || [];
  if (!pack.bundleRefs.find(br => br.bundleId === b.id)) {
    pack.bundleRefs.push({ bundleId: b.id, expanded: false, checkedItems: [] });
    savePack(trip);
  }
});

pickerList.addEventListener('click', e => {
  const addId = e.target.closest('[data-add]')?.dataset.add;
  if (!addId) return;
  const trip = trips.find(t => t.id === currentTripId);
  if (!trip) return;
  const pack = trip.packs[currentPackIdx];
  if (!pack) return;
  if (!pack.items.find(p => p.gearId === addId)) {
    const g = gear.find(g => g.id === addId);
    pack.items.push({ gearId: addId, qty: g?.qty ?? 1 });
    savePack(trip);
  }
});

// ── Catalog ──────────────────────────────────────────────────────────────────

const catalogContainer    = document.getElementById('catalog-container');
const catalogEmpty        = document.getElementById('catalog-empty');
const catalogSearch       = document.getElementById('catalog-search');
const catalogCatFilter    = document.getElementById('catalog-category-filter');
const adminPendingPanel   = document.getElementById('admin-pending-panel');
const pendingList         = document.getElementById('pending-list');
const pendingCountBadge   = document.getElementById('pending-count-badge');

catalogSearch.addEventListener('input', renderCatalog);
catalogCatFilter.addEventListener('change', renderCatalog);
document.getElementById('btn-suggest-item').addEventListener('click', () => {
  document.getElementById('form-suggest').reset();
  openModal(modalSuggest);
});

document.getElementById('form-suggest').addEventListener('submit', async e => {
  e.preventDefault();
  const fd = new FormData(e.target);
  try {
    await api('/catalog/suggest', {
      method: 'POST',
      body: {
        name:     fd.get('name').trim(),
        brand:    fd.get('brand').trim(),
        category: fd.get('category').trim(),
        weight:   fd.get('weight') !== '' ? parseFloat(fd.get('weight')) : null,
        notes:    fd.get('notes').trim(),
      },
    });
    closeModal();
    alert('Thanks! Your suggestion has been submitted for review.');
  } catch (err) { alert(err.message); }
});

// ── Add catalog item to gear locker ─────────────────────────────────────────
async function addCatalogItemToGear(item, variant, btn) {
  const name   = variant ? `${item.name} (${variant.name})` : item.name;
  const weight = variant ? (variant.weight ?? item.weight) : item.weight;
  try {
    const created = normalizeGear(await api('/gear', {
      method: 'POST',
      body: { name, brand: item.brand || '', category: item.category, weight, qty: 1, notes: item.notes || '' },
    }));
    gear.push(created);
    if (btn) {
      const orig = btn.textContent;
      btn.textContent = 'Added!';
      btn.disabled = true;
      setTimeout(() => { btn.textContent = orig; btn.disabled = false; }, 2000);
    }
  } catch (err) { alert(err.message); }
}

// ── Variant picker ───────────────────────────────────────────────────────────
const variantOverlay = document.getElementById('variant-overlay');
let variantPickerItem = null;
let variantPickerBtn  = null;

function openVariantPicker(item, btn) {
  variantPickerItem = item;
  variantPickerBtn  = btn;
  document.getElementById('variant-modal-title').textContent = item.name;
  document.getElementById('variant-modal-brand').textContent = [item.brand, item.category].filter(Boolean).join(' · ');
  const list = document.getElementById('variant-list');
  list.innerHTML = item.variants.map((v, i) => `
    <label class="variant-option ${i === 0 ? 'selected' : ''}">
      <input type="radio" name="variant-pick" value="${i}" ${i === 0 ? 'checked' : ''} />
      <span class="variant-option-name">${esc(v.name)}</span>
      ${v.weight != null ? `<span class="variant-option-weight">${formatWeight(v.weight)}</span>` : ''}
    </label>
  `).join('');
  list.querySelectorAll('.variant-option').forEach(label => {
    label.querySelector('input').addEventListener('change', () => {
      list.querySelectorAll('.variant-option').forEach(l => l.classList.remove('selected'));
      label.classList.add('selected');
    });
  });
  variantOverlay.classList.remove('hidden');
}

function closeVariantPicker() {
  variantOverlay.classList.add('hidden');
  variantPickerItem = null;
  variantPickerBtn  = null;
}

document.getElementById('variant-modal-close').addEventListener('click', closeVariantPicker);
variantOverlay.addEventListener('click', e => { if (e.target === variantOverlay) closeVariantPicker(); });
document.getElementById('variant-add-btn').addEventListener('click', async () => {
  if (!variantPickerItem) return;
  const checked = document.querySelector('input[name="variant-pick"]:checked');
  const idx     = checked ? parseInt(checked.value) : 0;
  const variant = variantPickerItem.variants[idx];
  const item    = variantPickerItem;
  const btn     = variantPickerBtn;
  closeVariantPicker();
  await addCatalogItemToGear(item, variant, btn);
});

// ── Admin: edit catalog item ─────────────────────────────────────────────────
function renderVariantRows(variants = []) {
  const list = document.getElementById('form-variants-list');
  list.innerHTML = variants.map((v, i) => `
    <div class="variant-row" data-vi="${i}">
      <input type="text" class="variant-row-name" placeholder="Name (e.g. Large / 65L)" value="${esc(v.name)}" />
      <input type="number" class="variant-row-weight" placeholder="Weight (g)" min="0" step="0.1" value="${v.weight ?? ''}" />
      <button type="button" class="variant-row-remove" data-vi="${i}" aria-label="Remove">✕</button>
    </div>
  `).join('');
  list.querySelectorAll('.variant-row-remove').forEach(btn => {
    btn.addEventListener('click', () => {
      btn.closest('.variant-row').remove();
    });
  });
}

function collectVariants() {
  return [...document.querySelectorAll('#form-variants-list .variant-row')].map(row => ({
    name:   row.querySelector('.variant-row-name').value.trim(),
    weight: row.querySelector('.variant-row-weight').value !== '' ? parseFloat(row.querySelector('.variant-row-weight').value) : null,
  })).filter(v => v.name);
}

document.getElementById('btn-add-variant').addEventListener('click', () => {
  const list = document.getElementById('form-variants-list');
  const i    = list.children.length;
  const div  = document.createElement('div');
  div.className = 'variant-row';
  div.dataset.vi = i;
  div.innerHTML = `
    <input type="text" class="variant-row-name" placeholder="Name (e.g. Large / 65L)" />
    <input type="number" class="variant-row-weight" placeholder="Weight (g)" min="0" step="0.1" />
    <button type="button" class="variant-row-remove" aria-label="Remove">✕</button>
  `;
  div.querySelector('.variant-row-remove').addEventListener('click', () => div.remove());
  list.appendChild(div);
  div.querySelector('.variant-row-name').focus();
});

function openCatalogEditModal(item) {
  const form = document.getElementById('form-catalog-edit');
  form.reset();
  form.name.value     = item.name;
  form.brand.value    = item.brand || '';
  form.category.value = item.category || '';
  form.weight.value   = item.weight ?? '';
  form.notes.value    = item.notes || '';
  form.id.value       = item._id ?? item.id;
  renderVariantRows(item.variants || []);
  openModal(modalCatalogEdit);
}

document.getElementById('form-catalog-edit').addEventListener('submit', async e => {
  e.preventDefault();
  const fd = new FormData(e.target);
  const id = fd.get('id');
  try {
    const updated = await api(`/catalog/${id}`, {
      method: 'PUT',
      body: {
        name:     fd.get('name').trim(),
        brand:    fd.get('brand').trim(),
        category: fd.get('category').trim(),
        weight:   fd.get('weight') !== '' ? parseFloat(fd.get('weight')) : null,
        notes:    fd.get('notes').trim(),
        variants: collectVariants(),
      },
    });
    if (!updated) return;
    const ci = catalog.findIndex(c => (c._id ?? c.id) === id);
    if (ci >= 0) catalog[ci] = { ...updated, id: updated._id };
    closeModal();
    renderCatalog();
    loadPendingItems();
  } catch (err) { alert(err.message); }
});

function renderCatalog() {
  const q   = catalogSearch.value.toLowerCase();
  const cat = catalogCatFilter.value;

  const filtered = catalog.filter(c =>
    (!q   || c.name.toLowerCase().includes(q) || (c.brand || '').toLowerCase().includes(q) || (c.notes || '').toLowerCase().includes(q)) &&
    (!cat || c.category === cat)
  );

  // Refresh category filter options
  const cats = [...new Set(catalog.map(c => c.category).filter(Boolean))].sort();
  const cur  = catalogCatFilter.value;
  catalogCatFilter.innerHTML = `<option value="">All categories</option>` +
    cats.map(c => `<option value="${esc(c)}" ${c === cur ? 'selected' : ''}>${esc(c)}</option>`).join('');

  catalogEmpty.style.display    = filtered.length ? 'none' : 'block';
  catalogContainer.style.display = filtered.length ? '' : 'none';

  // Group by category
  const groups = new Map();
  filtered.forEach(c => {
    const key = c.category?.trim() || '';
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(c);
  });
  const sorted = [...groups.entries()].sort(([a], [b]) => {
    if (!a) return 1; if (!b) return -1; return a.localeCompare(b);
  });

  catalogContainer.innerHTML = sorted.map(([label, items]) => `
    <div class="gear-block">
      <div class="gear-block-header">
        <span class="gear-block-title">${esc(label) || 'Uncategorised'}</span>
        <span class="gear-block-count">${items.length} item${items.length !== 1 ? 's' : ''}</span>
      </div>
      <table class="gear-table">
        <thead>
          <tr><th>Name</th><th></th></tr>
        </thead>
        <tbody>
          ${items.map(c => `
            <tr>
              <td>
                <div style="display:flex;align-items:center;gap:0.4rem;flex-wrap:wrap">
                  <strong class="item-name-link"
                    data-item-name="${esc(c.name)}"
                    data-item-brand="${esc(c.brand || '')}"
                    data-item-category="${esc(c.category || '')}"
                    data-item-weight="${c.weight != null ? c.weight : ''}"
                    data-item-qty=""
                    data-note="${esc(c.notes || '')}"
                    data-catalog-id="${c._id}"
                  >${esc(c.name)}</strong>
                  ${(c.variants && c.variants.length > 0) ? `<span class="variant-count-badge">${c.variants.length} variant${c.variants.length !== 1 ? 's' : ''}</span>` : ''}
                </div>
                ${(c.brand || c.weight != null) ? `<div class="item-brand">${[c.brand, c.weight != null ? `${c.weight}g` : null].filter(Boolean).join(' · ')}</div>` : ''}
              </td>
              <td class="col-actions">
                <button class="btn-add-from-catalog" data-catalog-id="${c.id}">+ My Gear</button>
                ${currentIsAdmin ? `<button data-catalog-edit="${c._id ?? c.id}">Edit</button><button data-catalog-delete="${c._id ?? c.id}" class="del">Delete</button>` : ''}
              </td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `).join('');

  // Always probe — server confirms admin status, no stale cache issue
  loadPendingCount();
}

catalogContainer.addEventListener('click', async e => {
  // Don't trigger add-to-locker when the name link was clicked (opens info card instead)
  if (e.target.closest('.item-name-link')) return;

  const catalogId    = e.target.closest('[data-catalog-id]')?.dataset.catalogId;
  const editId       = e.target.closest('[data-catalog-edit]')?.dataset.catalogEdit;
  const deleteId     = e.target.closest('[data-catalog-delete]')?.dataset.catalogDelete;

  if (catalogId) {
    const item = catalog.find(c => (c._id ?? c.id) === catalogId || c.id === catalogId);
    if (!item) return;
    if (item.variants && item.variants.length > 0) {
      openVariantPicker(item, e.target);
    } else {
      await addCatalogItemToGear(item, null, e.target);
    }
  }

  if (editId) {
    const item = catalog.find(c => (c._id ?? c.id) === editId || c.id === editId);
    if (item) openCatalogEditModal(item);
  }

  if (deleteId && confirm('Remove this item from the catalog?')) {
    try {
      await api(`/catalog/${deleteId}`, { method: 'DELETE' });
      catalog = catalog.filter(c => (c._id ?? c.id) !== deleteId && c.id !== deleteId);
      renderCatalog();
    } catch (err) { alert(err.message); }
  }
});

// ── Admin: pending approvals ──────────────────────────────────────────────────

async function loadPendingCount() {
  try {
    const data = await api('/catalog/pending-count');
    if (!data) return;
    currentIsAdmin = true;
    localStorage.setItem('lp_isAdmin', 'true');
    adminPendingPanel.classList.remove('hidden');
    pendingCountBadge.textContent = data.count || '';
    pendingCountBadge.style.display = data.count ? '' : 'none';
    if (data.count > 0) loadPendingItems();
    else pendingList.innerHTML = '<p class="empty-msg" style="padding:1rem 0">No pending suggestions.</p>';
  } catch {
    adminPendingPanel.classList.add('hidden');
  }
}

async function loadPendingItems() {
  const items = await api('/catalog/pending');
  if (!items) return;
  if (!items.length) {
    pendingList.innerHTML = '<p class="empty-msg" style="padding:1rem">No pending suggestions.</p>';
    return;
  }
  pendingList.innerHTML = `
    <table class="gear-table">
      <thead><tr><th>Name</th><th>Brand</th><th>Category</th><th>Weight</th><th>Notes</th><th>Submitted by</th><th></th></tr></thead>
      <tbody>
        ${items.map(item => `
          <tr>
            <td><strong>${esc(item.name)}</strong></td>
            <td>${esc(item.brand) || '—'}</td>
            <td>${esc(item.category) || '—'}</td>
            <td>${item.weight != null ? item.weight + 'g' : '—'}</td>
            <td><span class="note-text">${esc(item.notes) || '—'}</span></td>
            <td>${esc(item.submittedBy?.username || '—')}</td>
            <td class="col-actions">
              <button data-pending-edit="${item._id}" data-item="${esc(JSON.stringify({_id:item._id,name:item.name,brand:item.brand,category:item.category,weight:item.weight,notes:item.notes}))}">Edit</button>
              <button data-approve="${item._id}">Approve</button>
              <button data-reject="${item._id}" class="del">Reject</button>
            </td>
          </tr>
        `).join('')}
      </tbody>
    </table>`;
}

pendingList.addEventListener('click', async e => {
  const pendingEditEl = e.target.closest('[data-pending-edit]');
  const approveId     = e.target.closest('[data-approve]')?.dataset.approve;
  const rejectId      = e.target.closest('[data-reject]')?.dataset.reject;

  if (pendingEditEl) {
    try { openCatalogEditModal(JSON.parse(pendingEditEl.dataset.item)); } catch {}
    return;
  }
  if (approveId) {
    const item = await api(`/catalog/${approveId}/approve`, { method: 'PUT' });
    if (item) {
      catalog.push({ ...item, id: item._id });
      renderCatalog();
    }
  }
  if (rejectId && confirm('Reject and delete this suggestion?')) {
    await api(`/catalog/${rejectId}`, { method: 'DELETE' });
    loadPendingItems();
    loadPendingCount();
  }
});

// ── Utilities ────────────────────────────────────────────────────────────────

function esc(str) {
  return String(str ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function formatWeight(g) {
  if (!g) return '';
  return g >= 1000 ? `${(g / 1000).toFixed(2)}kg` : `${Math.round(g)}g`;
}
function formatDateRange(start, end) {
  if (!start && !end) return '';
  const fmt = d => d ? new Date(d + 'T00:00:00').toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' }) : '';
  if (start && end) return `${fmt(start)} – ${fmt(end)}`;
  return fmt(start) || fmt(end);
}

// ── Service worker ────────────────────────────────────────────────────────────
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js');
}
