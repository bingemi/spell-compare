let expansions = {};
let loadedMaster = [];

const CLASS_NAMES = {
  BER: 'Berserker', BRD: 'Bard', BST: 'Beastlord', CLR: 'Cleric',
  DRU: 'Druid', ENC: 'Enchanter', MAG: 'Magician', MNK: 'Monk',
  NEC: 'Necromancer', PAL: 'Paladin', RNG: 'Ranger', ROG: 'Rogue',
  SHD: 'Shadow Knight', SHM: 'Shaman', WAR: 'Warrior', WIZ: 'Wizard'
};

function parseMaster(raw) {
  const spells = [];
  raw.split('\n').forEach(line => {
    const t = line.trim();
    if (!t || t.startsWith('#')) return;
    const parts = t.split('\t');
    if (parts.length < 3) return;
    const lvl = parseInt(parts[0]);
    if (isNaN(lvl)) return;
    spells.push({ level: lvl, name: parts[1].trim(), key: parts[1].trim().toLowerCase(), expansion: parts[2].trim() });
  });
  return spells;
}

function parseChar(raw) {
  const spells = new Set();
  raw.split('\n').forEach(line => {
    const t = line.trim();
    if (!t || t.startsWith('#')) return;
    const parts = t.split('\t');
    if (parts.length < 2) return;
    spells.add(parts[1].trim().toLowerCase());
  });
  return spells;
}

function buildChips(master) {
  const exps = [...new Set(master.map(s => s.expansion))].sort();
  const prev = { ...expansions };
  expansions = {};
  exps.forEach(e => expansions[e] = (e in prev) ? prev[e] : true);
  renderChips();
}

function renderChips() {
  const c = document.getElementById('expChips');
  const exps = Object.keys(expansions);
  if (!exps.length) { c.innerHTML = '<span class="empty-exp">Select a class above to see expansions</span>'; return; }
  c.innerHTML = exps.map(e =>
    `<span class="chip ${expansions[e] ? 'active' : ''}" onclick="toggleExp('${e}')"><span class="dot"></span>${e}</span>`
  ).join('');
}

function toggleExp(e) { expansions[e] = !expansions[e]; renderChips(); }
function setAll(v) { Object.keys(expansions).forEach(e => expansions[e] = v); renderChips(); }

document.getElementById('classSelect').addEventListener('change', function () {
  const cls = this.value;
  const info = document.getElementById('loadedInfo');
  if (!cls) {
    loadedMaster = [];
    expansions = {};
    renderChips();
    info.textContent = 'Select a class to load its spell list.';
    return;
  }
  info.textContent = 'Loading...';
  fetch(`spell-reference/${cls}_spells.txt`)
    .then(r => {
      if (!r.ok) throw new Error('File not found');
      return r.text();
    })
    .then(text => {
      loadedMaster = parseMaster(text);
      info.textContent = `Loaded ${loadedMaster.length} spells for ${CLASS_NAMES[cls]}.`;
      if (loadedMaster.length) buildChips(loadedMaster);
    })
    .catch(() => {
      loadedMaster = [];
      expansions = {};
      renderChips();
      info.textContent = 'Failed to load spell list. Make sure spell-reference/ is accessible.';
    });
});

function showError(msg) { const el = document.getElementById('errorMsg'); el.textContent = msg; el.style.display = 'block'; }
function hideError() { document.getElementById('errorMsg').style.display = 'none'; }

function groupByExp(spells) {
  const groups = {};
  spells.forEach(s => { if (!groups[s.expansion]) groups[s.expansion] = []; groups[s.expansion].push(s); });
  Object.values(groups).forEach(g => g.sort((a, b) => a.level - b.level));
  return groups;
}

function renderGrouped(spells, containerId) {
  const el = document.getElementById(containerId);
  if (!spells.length) { el.innerHTML = '<p class="no-issues">None.</p>'; return; }
  const groups = groupByExp(spells);
  el.innerHTML = Object.keys(groups).sort().map(exp => `
    <div class="exp-group">
      <div class="exp-group-name">${exp}</div>
      ${groups[exp].map(s => `<div class="spell-row"><span class="spell-lvl">${s.level}</span><span class="spell-name">${s.name}</span></div>`).join('')}
    </div>`).join('');
}

function runComparison() {
  hideError();
  const charRaw = document.getElementById('charInput').value.trim();
  if (!loadedMaster.length) { showError('Select a class first to load the master spell list.'); return; }
  if (!charRaw) { showError('Paste your character spell list on the right.'); return; }

  const charSpells = parseChar(charRaw);
  const selected = new Set(Object.keys(expansions).filter(e => expansions[e]));
  if (!selected.size) { showError('Select at least one expansion to check.'); return; }

  const filtered = loadedMaster.filter(s => selected.has(s.expansion));
  const filteredKeys = new Set(filtered.map(s => s.key));
  const missing = filtered.filter(s => !charSpells.has(s.key));
  const extra = [...charSpells].filter(k => !filteredKeys.has(k)).map(k => ({ key: k, name: k, expansion: 'Unknown', level: 0 }));
  const matched = filtered.filter(s => charSpells.has(s.key));

  document.getElementById('statMaster').textContent = filtered.length;
  document.getElementById('statChar').textContent = charSpells.size;
  document.getElementById('statMissing').textContent = missing.length;
  document.getElementById('missingCount').textContent = missing.length;
  document.getElementById('extraCount').textContent = extra.length;
  document.getElementById('matchCount').textContent = matched.length;

  renderGrouped(missing, 'missingList');

  const extraEl = document.getElementById('extraList');
  if (!extra.length) { extraEl.innerHTML = '<p class="no-issues">No unrecognised spells.</p>'; }
  else { extraEl.innerHTML = extra.map(s => `<div class="spell-row"><span class="spell-name">${s.name}</span></div>`).join(''); }

  const toggle = document.getElementById('matchToggle');
  const content = document.getElementById('matchContent');
  document.getElementById('matchList').innerHTML = '';
  if (matched.length) {
    toggle.style.display = 'inline';
    toggle.textContent = 'Show matched spells';
    content.classList.remove('open');
    const groups = groupByExp(matched);
    content.innerHTML = Object.keys(groups).sort().map(exp => `
      <div class="exp-group">
        <div class="exp-group-name">${exp}</div>
        ${groups[exp].map(s => `<div class="spell-row"><span class="spell-lvl">${s.level}</span><span class="spell-name">${s.name}</span></div>`).join('')}
      </div>`).join('');
  } else {
    toggle.style.display = 'none';
    document.getElementById('matchList').innerHTML = '<p class="no-issues">No matches found.</p>';
  }

  document.getElementById('results').style.display = 'block';
  document.getElementById('results').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function toggleMatched() {
  const content = document.getElementById('matchContent');
  const toggle = document.getElementById('matchToggle');
  const open = content.classList.toggle('open');
  toggle.textContent = open ? 'Hide matched spells' : 'Show matched spells';
}
