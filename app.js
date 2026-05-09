// ── Auth state ───────────────────────────────────────────────────────────────

let authToken = localStorage.getItem('lp_token');
let currentUsername = localStorage.getItem('lp_username');
let currentIsAdmin  = localStorage.getItem('lp_isAdmin') === 'true';

let gear    = [];
let trips   = [];
let catalog = [];
let currentView    = 'gear';
let currentTripId  = null;
let currentPackIdx = 0;

// ── API helper ───────────────────────────────────────────────────────────────

async function api(path, options = {}) {
  const res = await fetch(`/api${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(authToken ? { Authorization: `Bearer ${authToken}` } : {}),
      ...(options.headers || {}),
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
  });
  if (res.status === 401) { logout(); return null; }
  if (res.status === 403) return null;
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: 'Request failed' }));
    throw new Error(err.error || 'Request failed');
  }
  return res.json();
}

// ── Auth screens ─────────────────────────────────────────────────────────────

const authScreen = document.getElementById('auth-screen');
const appEl      = document.getElementById('app');

function showApp() {
  authScreen.classList.add('hidden');
  appEl.classList.remove('hidden');
  document.getElementById('header-username').textContent = currentUsername;
  loadAll();
}

function showAuth() {
  authScreen.classList.remove('hidden');
  appEl.classList.add('hidden');
}

async function loadAll() {
  const [gearData, tripsData, catalogData] = await Promise.all([
    api('/gear'),
    api('/trips'),
    api('/catalog'),
  ]);
  if (!gearData || !tripsData || !catalogData) return;
  gear    = gearData.map(normalizeGear);
  trips   = tripsData.map(normalizeTrip);
  catalog = catalogData.map(c => ({ ...c, id: c._id ?? c.id }));
  renderGear();
  renderTripList();
  if (currentIsAdmin) loadPendingCount();
}

// Normalise Mongo _id -> id for the frontend
function normalizeGear(g)  { return { ...g, id: g._id ?? g.id }; }
function normalizeTrip(t)  {
  const base = { ...t, id: t._id ?? t.id };
  if (!base.packs || base.packs.length === 0) {
    const legacy = (base.pack || []).map(p => ({ ...p, gearId: p.gearId?._id ?? p.gearId }));
    base.packs = [{ name: 'Pack 1', items: legacy }];
  } else {
    base.packs = base.packs.map(pk => ({
      ...pk,
      cubes: (pk.cubes || []).map(c => ({ ...c, id: String(c._id ?? c.id) })),
      items: (pk.items || []).map(p => ({ ...p, gearId: p.gearId?._id ?? p.gearId })),
    }));
  }
  return base;
}

if (authToken) { showApp(); } else { showAuth(); }

// Auth tab switching
document.querySelectorAll('.auth-tab').forEach(tab => {
  tab.addEventListener('click', () => {
    document.querySelectorAll('.auth-tab').forEach(t => t.classList.toggle('active', t === tab));
    document.querySelectorAll('.auth-form').forEach(f => f.classList.add('hidden'));
    document.getElementById(`form-${tab.dataset.tab}`).classList.remove('hidden');
  });
});

// Login
document.getElementById('form-login').addEventListener('submit', async e => {
  e.preventDefault();
  const fd = new FormData(e.target);
  const errEl = document.getElementById('login-error');
  errEl.classList.add('hidden');
  try {
    const data = await api('/auth/login', {
      method: 'POST',
      body: { username: fd.get('username'), password: fd.get('password') },
    });
    if (!data) return;
    authToken = data.token;
    currentUsername = data.username;
    currentIsAdmin  = !!data.isAdmin;
    localStorage.setItem('lp_token', authToken);
    localStorage.setItem('lp_username', currentUsername);
    localStorage.setItem('lp_isAdmin', currentIsAdmin);
    showApp();
  } catch (err) {
    errEl.textContent = err.message;
    errEl.classList.remove('hidden');
  }
});

// Register
document.getElementById('form-register').addEventListener('submit', async e => {
  e.preventDefault();
  const fd = new FormData(e.target);
  const errEl = document.getElementById('register-error');
  errEl.classList.add('hidden');
  if (fd.get('password') !== fd.get('confirm')) {
    errEl.textContent = 'Passwords do not match';
    errEl.classList.remove('hidden');
    return;
  }
  try {
    const data = await api('/auth/register', {
      method: 'POST',
      body: { username: fd.get('username'), password: fd.get('password') },
    });
    if (!data) return;
    authToken = data.token;
    currentUsername = data.username;
    currentIsAdmin  = !!data.isAdmin;
    localStorage.setItem('lp_token', authToken);
    localStorage.setItem('lp_username', currentUsername);
    localStorage.setItem('lp_isAdmin', currentIsAdmin);
    showApp();
  } catch (err) {
    errEl.textContent = err.message;
    errEl.classList.remove('hidden');
  }
});

function logout() {
  authToken = null;
  currentUsername = null;
  currentIsAdmin  = false;
  localStorage.removeItem('lp_token');
  localStorage.removeItem('lp_username');
  localStorage.removeItem('lp_isAdmin');
  gear = []; trips = []; catalog = [];
  showAuth();
}
document.getElementById('btn-logout').addEventListener('click', logout);

// ── Navigation ───────────────────────────────────────────────────────────────

document.querySelectorAll('.nav-btn').forEach(btn => {
  btn.addEventListener('click', () => switchView(btn.dataset.view));
});

function switchView(view) {
  currentView = view;
  document.querySelectorAll('.nav-btn').forEach(b => b.classList.toggle('active', b.dataset.view === view));
  document.querySelectorAll('.view').forEach(s => s.classList.toggle('active', s.id === `view-${view}`));
  if (view === 'gear')    renderGear();
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
const brandFilter   = document.getElementById('gear-brand-filter');
const catDatalist   = document.getElementById('category-list');
const brandDatalist = document.getElementById('brand-list');

document.getElementById('btn-add-item').addEventListener('click', () => openItemModal());
gearSearch.addEventListener('input', renderGear);
catFilter.addEventListener('change', renderGear);
brandFilter.addEventListener('change', renderGear);

function categories() {
  return [...new Set(gear.map(g => g.category).filter(Boolean))].sort();
}

function brands() {
  return [...new Set(gear.map(g => g.brand).filter(Boolean))].sort();
}

function refreshCategoryUI() {
  const cats = categories();
  catDatalist.innerHTML = cats.map(c => `<option value="${esc(c)}">`).join('');
  const current = catFilter.value;
  catFilter.innerHTML = `<option value="">All categories</option>` +
    cats.map(c => `<option value="${esc(c)}" ${c === current ? 'selected' : ''}>${esc(c)}</option>`).join('');

  const bs = brands();
  brandDatalist.innerHTML = bs.map(b => `<option value="${esc(b)}">`).join('');
  const curBrand = brandFilter.value;
  brandFilter.innerHTML = `<option value="">All brands</option>` +
    bs.map(b => `<option value="${esc(b)}" ${b === curBrand ? 'selected' : ''}>${esc(b)}</option>`).join('');
}

function renderGear() {
  refreshCategoryUI();
  const q      = gearSearch.value.toLowerCase();
  const cat    = catFilter.value;
  const brand  = brandFilter.value;
  const filtered = gear.filter(g =>
    (!q     || g.name.toLowerCase().includes(q) || (g.brand || '').toLowerCase().includes(q) || (g.notes || '').toLowerCase().includes(q)) &&
    (!cat   || g.category === cat) &&
    (!brand || g.brand === brand)
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
            <th>Name</th><th>Brand</th><th>Weight (g)</th><th>Qty</th><th>Notes</th><th></th>
          </tr>
        </thead>
        <tbody>
          ${items.map(g => `
            <tr>
              <td><strong>${esc(g.name)}</strong></td>
              <td>${esc(g.brand) || '—'}</td>
              <td>${g.weight != null && g.weight !== '' ? g.weight : '—'}</td>
              <td>${g.qty ?? 1}</td>
              <td><span class="note-text" title="${esc(g.notes || '')}">${esc(g.notes || '') || '—'}</span></td>
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

function showTripList() {
  tripListPanel.classList.remove('hidden');
  tripDetailPanel.classList.add('hidden');
  currentTripId = null;
}

function renderTripList() {
  tripsEmpty.style.display = trips.length ? 'none' : 'block';
  tripListEl.innerHTML = trips.map(t => {
    const itemCount = (t.packs || []).reduce((sum, pk) => sum + (pk.items || []).length, 0);
    const meta = [t.destination, formatDateRange(t.startDate, t.endDate)].filter(Boolean).join(' · ');
    return `
      <li>
        <div class="trip-card" data-trip="${t.id}">
          <div class="trip-card-info">
            <h4>${esc(t.name)}</h4>
            ${meta ? `<div class="meta">${esc(meta)}</div>` : ''}
          </div>
          <span class="trip-card-badge">${itemCount} item${itemCount !== 1 ? 's' : ''}</span>
        </div>
      </li>`;
  }).join('');
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
      updated = normalizeTrip(await api(`/trips/${id}`, { method: 'PUT', body: { ...payload, packs: existing?.packs || [] } }));
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
  const packs = trip.packs || [];
  if (currentPackIdx >= packs.length) currentPackIdx = Math.max(0, packs.length - 1);
  renderPackSection(trip);
  renderPicker();
}

function renderPackSection(trip) {
  const packs = trip.packs || [];

  packTabsArea.innerHTML = `
    <div class="pack-tabs">
      ${packs.map((pk, i) => `
        <button class="pack-tab${i === currentPackIdx ? ' active' : ''}" data-tab="${i}">
          ${esc(pk.name || `Pack ${i + 1}`)}
          ${packs.length > 1 ? `<span class="pack-tab-del" data-del-pack="${i}" title="Remove pack">×</span>` : ''}
        </button>
      `).join('')}
      <button class="pack-tab pack-tab-new" data-new-pack>+ Pack</button>
    </div>`;

  const pack = packs[currentPackIdx];
  if (!pack) { packBodyArea.innerHTML = ''; return; }

  const items = pack.items || [];
  let totalWeight = 0;
  items.forEach(p => {
    const g = gear.find(g => g.id === p.gearId);
    if (g?.weight) totalWeight += g.weight * p.qty;
  });
  const statsText = items.length
    ? `${items.length} item type${items.length !== 1 ? 's' : ''} · ${formatWeight(totalWeight)} total`
    : '';

  const cubes    = pack.cubes || [];
  const hasCubes = cubes.length > 0;

  function renderItem(p) {
    const g = gear.find(g => g.id === p.gearId);
    if (!g) return '';
    const lineWeight = g.weight != null ? formatWeight(g.weight * p.qty) : null;
    return `
      <li class="pack-item">
        <div class="pack-item-info">
          <div class="pack-item-name">${esc(g.name)}</div>
          <div class="pack-item-meta">${[g.category, lineWeight].filter(Boolean).join(' · ') || '—'}</div>
        </div>
        <div class="pack-item-qty">
          <button data-qty-dec="${g.id}">−</button>
          <span>${p.qty}</span>
          <button data-qty-inc="${g.id}">+</button>
        </div>
        ${hasCubes ? `
          <select class="cube-select" data-cube-assign="${g.id}">
            <option value="">No cube</option>
            ${cubes.map(c => `<option value="${c.id}" ${p.cubeId === c.id ? 'selected' : ''}>${esc(c.name)}</option>`).join('')}
          </select>` : ''}
        <button class="pack-item-remove" data-remove="${g.id}" title="Remove">✕</button>
      </li>`;
  }

  const ungrouped = items.filter(p => !p.cubeId || !cubes.find(c => c.id === p.cubeId));

  packBodyArea.innerHTML = `
    <div class="pack-name-row">
      <span class="pack-name-label">${esc(pack.name || `Pack ${currentPackIdx + 1}`)}</span>
      <button class="btn-link" data-rename-pack>Rename</button>
    </div>
    ${statsText ? `<p class="pack-stats">${statsText}</p>` : ''}

    ${cubes.map(c => {
      const cubeItems = items.filter(p => p.cubeId === c.id);
      return `
        <div class="cube-block">
          <div class="cube-header">
            <span class="cube-name">${esc(c.name)}</span>
            <button class="btn-link" data-rename-cube="${c.id}">Rename</button>
            <button class="cube-del" data-del-cube="${c.id}" title="Remove cube">×</button>
          </div>
          <ul class="pack-list">${cubeItems.map(renderItem).join('')}</ul>
          ${!cubeItems.length ? '<p class="cube-empty">Empty — assign items using the dropdown on each item.</p>' : ''}
        </div>`;
    }).join('')}

    ${ungrouped.length || !hasCubes ? `
      <div class="cube-block cube-ungrouped">
        ${hasCubes ? '<div class="cube-header"><span class="cube-name">Ungrouped</span></div>' : ''}
        <ul class="pack-list">${ungrouped.map(renderItem).join('')}</ul>
        ${!items.length ? '<p class="empty-msg">No items in this pack yet.</p>' : ''}
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

  const incId       = e.target.closest('[data-qty-inc]')?.dataset.qtyInc;
  const decId       = e.target.closest('[data-qty-dec]')?.dataset.qtyDec;
  const remId       = e.target.closest('[data-remove]')?.dataset.remove;
  const isRenamePack = e.target.closest('[data-rename-pack]');
  const renameCubeId = e.target.closest('[data-rename-cube]')?.dataset.renameCube;
  const delCubeId    = e.target.closest('[data-del-cube]')?.dataset.delCube;
  const isNewCube    = e.target.closest('[data-new-cube]');

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
});

packBodyArea.addEventListener('change', e => {
  const assignEl = e.target.closest('[data-cube-assign]');
  if (!assignEl) return;
  const trip = trips.find(t => t.id === currentTripId);
  if (!trip) return;
  const pack = trip.packs[currentPackIdx];
  if (!pack) return;
  const p = pack.items.find(p => p.gearId === assignEl.dataset.cubeAssign);
  if (p) {
    p.cubeId = assignEl.value || null;
    savePack(trip);
  }
});

function renderPicker() {
  const trip = trips.find(t => t.id === currentTripId);
  if (!trip) return;
  const q = pickerSearch.value.toLowerCase();
  const filtered = gear.filter(g =>
    !q || g.name.toLowerCase().includes(q) || (g.category || '').toLowerCase().includes(q)
  );
  const pack = trip.packs[currentPackIdx];
  const inPack = new Set((pack?.items || []).map(p => p.gearId));
  pickerList.innerHTML = filtered.map(g => {
    const already = inPack.has(g.id);
    return `
      <li class="picker-item">
        <div class="picker-item-name">${esc(g.name)}</div>
        <div class="picker-item-meta">${[g.category, g.weight != null ? `${g.weight}g` : null].filter(Boolean).join(' · ') || ''}</div>
        <button class="picker-item-add ${already ? 'in-pack' : ''}"
                data-add="${g.id}" ${already ? 'disabled' : ''}>
          ${already ? 'Added' : '+ Add'}
        </button>
      </li>`;
  }).join('');
  if (!filtered.length)
    pickerList.innerHTML = '<li style="padding:0.5rem;color:var(--text-muted);font-size:0.85rem">No gear found.</li>';
}

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

function openCatalogEditModal(item) {
  const form = document.getElementById('form-catalog-edit');
  form.reset();
  form.name.value     = item.name;
  form.brand.value    = item.brand || '';
  form.category.value = item.category || '';
  form.weight.value   = item.weight ?? '';
  form.notes.value    = item.notes || '';
  form.id.value       = item._id ?? item.id;
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
      },
    });
    if (!updated) return;
    // Update local arrays
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
          <tr><th>Name</th><th>Brand</th><th>Weight (g)</th><th>Notes</th><th></th></tr>
        </thead>
        <tbody>
          ${items.map(c => `
            <tr>
              <td><strong>${esc(c.name)}</strong></td>
              <td>${esc(c.brand) || '—'}</td>
              <td>${c.weight != null ? c.weight : '—'}</td>
              <td><span class="note-text" title="${esc(c.notes || '')}">${esc(c.notes || '') || '—'}</span></td>
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
  const catalogId    = e.target.closest('[data-catalog-id]')?.dataset.catalogId;
  const editId       = e.target.closest('[data-catalog-edit]')?.dataset.catalogEdit;
  const deleteId     = e.target.closest('[data-catalog-delete]')?.dataset.catalogDelete;

  if (catalogId) {
    const item = catalog.find(c => (c._id ?? c.id) === catalogId || c.id === catalogId);
    if (!item) return;
    try {
      const created = normalizeGear(await api('/gear', {
        method: 'POST',
        body: { name: item.name, brand: item.brand || '', category: item.category, weight: item.weight, qty: 1, notes: item.notes || '' },
      }));
      gear.push(created);
      e.target.textContent = 'Added!';
      e.target.disabled = true;
      setTimeout(() => { e.target.textContent = '+ My Gear'; e.target.disabled = false; }, 2000);
    } catch (err) { alert(err.message); }
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
