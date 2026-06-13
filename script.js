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
  const spells = new Map();
  raw.split('\n').forEach(line => {
    const t = line.trim();
    if (!t || t.startsWith('#')) return;
    const parts = t.split('\t');
    if (parts.length < 2) return;
    const lvl = parseInt(parts[0]);
    if (isNaN(lvl)) return;
    spells.set(parts[1].trim().toLowerCase(), lvl);
  });
  return spells;
}

const ALLOWED_EXPANSIONS = ['EQ', 'Kunark', 'Velious', 'Luclin', 'LDoN', 'LoY', 'PoP', 'Gates', 'Omens'];

function buildChips(master) {
  const available = new Set(master.map(s => s.expansion));
  const exps = ALLOWED_EXPANSIONS.filter(e => available.has(e));
  const prev = { ...expansions };
  expansions = {};
  const defaultTrue = new Set(['EQ', 'Kunark', 'Velious', 'Luclin', 'LDoN']);
  exps.forEach(e => expansions[e] = (e in prev) ? prev[e] : defaultTrue.has(e));
  renderChips();
}

const EXP_NAMES = { EQ: 'Classic' };

function renderChips() {
  const c = document.getElementById('expChips');
  const exps = Object.keys(expansions);
  if (!exps.length) { c.innerHTML = '<span class="empty-exp">Select a class above to see expansions</span>'; return; }
  c.innerHTML = exps.map(e =>
    `<span class="chip ${expansions[e] ? 'active' : ''}" onclick="toggleExp('${e}')"><span class="dot"></span>${EXP_NAMES[e] || e}</span>`
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

function sortExps(exps) {
  return [...exps].sort((a, b) => {
    const ia = ALLOWED_EXPANSIONS.indexOf(a);
    const ib = ALLOWED_EXPANSIONS.indexOf(b);
    return (ia === -1 ? 999 : ia) - (ib === -1 ? 999 : ib);
  });
}

function renderGrouped(spells, containerId) {
  const el = document.getElementById(containerId);
  if (!spells.length) { el.innerHTML = '<p class="no-issues">None.</p>'; return; }
  const groups = groupByExp(spells);
  el.innerHTML = sortExps(Object.keys(groups)).map(exp => `
    <div class="exp-group">
      <div class="exp-group-name">${exp}</div>
      ${groups[exp].map(s => `<div class="spell-row"><span class="spell-lvl">${s.level}</span><span class="spell-name"><a href="https://everquest.allakhazam.com/search.html?q=${s.name.replace(/ /g, '+')}" target="_blank" rel="noopener">${s.name}</a></span></div>`).join('')}
    </div>`).join('');
}

function runComparison() {
  hideError();
  const charRaw = document.getElementById('charInput').value.trim();
  if (!loadedMaster.length) { showError('Select a class first to load the master spell list.'); return; }
  if (!charRaw) { showError('Upload your character spell file on the right.'); return; }

  const charLevel = parseInt(document.getElementById('charLevel').value);
  if (isNaN(charLevel) || charLevel < 1 || charLevel > 70) { showError('Enter a character level between 1 and 70.'); return; }

  const charSpells = parseChar(charRaw);
  const selected = new Set(Object.keys(expansions).filter(e => expansions[e]));
  if (!selected.size) { showError('Select at least one expansion to check.'); return; }

  const filtered = loadedMaster.filter(s => selected.has(s.expansion) && s.level <= charLevel);
  const filteredKeys = new Set(filtered.map(s => s.key));
  const charFiltered = new Map();
  for (const [key, lvl] of charSpells) {
    if (lvl <= charLevel) charFiltered.set(key, lvl);
  }
  const missing = filtered.filter(s => !charFiltered.has(s.key));
  const extra = [...charFiltered.keys()].filter(k => !filteredKeys.has(k)).map(k => ({ key: k, name: k, expansion: 'Unknown', level: 0 }));
  const matched = filtered.filter(s => charFiltered.has(s.key));

  document.getElementById('statMaster').textContent = filtered.length;
  document.getElementById('statChar').textContent = charFiltered.size;
  document.getElementById('statMissing').textContent = missing.length;
  document.getElementById('missingCount').textContent = missing.length;
  document.getElementById('extraCount').textContent = extra.length;
  document.getElementById('matchCount').textContent = matched.length;

  renderGrouped(missing, 'missingList');

  const extraEl = document.getElementById('extraList');
  if (!extra.length) { extraEl.innerHTML = '<p class="no-issues">No unrecognised spells.</p>'; }
  else { extraEl.innerHTML = extra.map(s => `<div class="spell-row"><span class="spell-name"><a href="https://everquest.allakhazam.com/search.html?q=${s.name.replace(/ /g, '+')}" target="_blank" rel="noopener">${s.name}</a></span></div>`).join(''); }

  const toggle = document.getElementById('matchToggle');
  const content = document.getElementById('matchContent');
  document.getElementById('matchList').innerHTML = '';
  if (matched.length) {
    toggle.style.display = 'inline';
    toggle.textContent = 'Show matched spells';
    content.classList.remove('open');
    const groups = groupByExp(matched);
    content.innerHTML = sortExps(Object.keys(groups)).map(exp => `
      <div class="exp-group">
        <div class="exp-group-name">${exp}</div>
        ${groups[exp].map(s => `<div class="spell-row"><span class="spell-lvl">${s.level}</span><span class="spell-name"><a href="https://everquest.allakhazam.com/search.html?q=${s.name.replace(/ /g, '+')}" target="_blank" rel="noopener">${s.name}</a></span></div>`).join('')}
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

function setupFileInput() {
  const zone = document.getElementById('dropZone');
  const input = document.getElementById('fileInput');

  zone.addEventListener('click', () => input.click());

  zone.addEventListener('dragover', e => {
    e.preventDefault();
    zone.classList.add('dragover');
  });

  zone.addEventListener('dragleave', () => {
    zone.classList.remove('dragover');
  });

  zone.addEventListener('drop', e => {
    e.preventDefault();
    zone.classList.remove('dragover');
    const file = e.dataTransfer.files[0];
    if (file) handleFile(file);
  });

  input.addEventListener('change', () => {
    const file = input.files[0];
    if (file) handleFile(file);
  });
}

function handleFile(file) {
  const reader = new FileReader();
  reader.onload = e => {
    const text = e.target.result;
    document.getElementById('charInput').value = text;
    const count = parseChar(text).size;
    document.getElementById('dropContent').style.display = 'none';
    document.getElementById('dropFileInfo').style.display = 'block';
    document.getElementById('dropZone').classList.add('has-file');
    document.getElementById('dropFilename').textContent = file.name;
    document.getElementById('dropSpellCount').textContent = `${count} spells loaded`;
  };
  reader.readAsText(file);
}

function clearFile() {
  document.getElementById('charInput').value = '';
  document.getElementById('dropContent').style.display = '';
  document.getElementById('dropFileInfo').style.display = 'none';
  document.getElementById('dropZone').classList.remove('has-file');
  document.getElementById('fileInput').value = '';
}

setupFileInput();
