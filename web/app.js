// Small enhancements: screen viewer tabs, the sensitivity demo, accent switching,
// release details from downloads/release.json, and the checksum copy button.
(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];

  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch { /* storage blocked */ } },
  };

  function swap(img, src, alt) {
    if (img.getAttribute('src') === src) return;
    img.classList.add('swapping');
    const next = new Image();
    next.onload = next.onerror = () => {
      img.src = src;
      if (alt) img.alt = alt;
      img.classList.remove('swapping');
    };
    next.src = src;
  }

  // Screen viewer
  const captions = {
    overview: 'The Overview rolls storage, clutter, threats and scan age into one health score, with a fix next to each.',
    cleaner: 'Cleaner measures every cache, keeps recent files, and previews the total before anything is deleted.',
    disk: 'Disk maps a drive in seconds: biggest folders as a treemap, space by file type, and the largest files.',
    health: 'Drive health shows each drive\'s life left, temperature, hours and errors, a Good, Caution or Bad verdict, and its wear over time.',
    shield: 'Shield lists each finding with the evidence behind its score, plus Quarantine, Ask Defender and It\'s safe.',
    customize: 'Customize changes accent, depth, density, corners, glow and motion live, along with every scan and clean rule.',
  };
  const tabs = $$('.tabs [role="tab"]');
  function selectTab(tab) {
    tabs.forEach(t => {
      const on = t === tab;
      t.setAttribute('aria-selected', String(on));
      t.tabIndex = on ? 0 : -1;
    });
    const name = tab.dataset.shot;
    $('#viewer-panel').setAttribute('aria-labelledby', tab.id);
    swap($('#viewer-img'), `/assets/${name}.png`, `Fiend's ${tab.textContent} screen.`);
    $('#viewer-caption').textContent = captions[name];
  }
  tabs.forEach((t, i) => {
    t.tabIndex = i === 0 ? 0 : -1;
    t.addEventListener('click', () => selectTab(t));
    t.addEventListener('keydown', e => {
      const d = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
      if (!d) return;
      e.preventDefault();
      const n = tabs[(i + d + tabs.length) % tabs.length];
      n.focus();
      selectTab(n);
    });
  });

  // Sensitivity demo
  const labels = { 50: 'Relaxed', 30: 'Balanced', 15: 'Paranoid' };
  function setThreshold(btn) {
    const t = Number(btn.dataset.threshold);
    $$('.seg [role="radio"]').forEach(b => b.setAttribute('aria-checked', String(b === btn)));
    $('#marker').style.left = `${t}%`;
    $('#marker-label').textContent = t;
    const items = $$('#samples li');
    let shown = 0;
    items.forEach(li => {
      const on = Number(li.dataset.score) >= t && Number(li.dataset.score) > 0;
      li.classList.toggle('on', on);
      li.classList.toggle('off', !on);
      if (on) shown++;
    });
    $('#samples-note').textContent = `${labels[t]} reports ${shown} of these ${items.length} files (score ${t} or more).`;
  }
  $$('.seg [role="radio"]').forEach(b => b.addEventListener('click', () => setThreshold(b)));
  const initial = $('.seg [aria-checked="true"]');
  if (initial) setThreshold(initial);

  // Accent switcher
  const accents = { hellfire: '#FF3B4E', ember: '#FF7A2F', toxic: '#7CE85A', spectral: '#A77BFF', ice: '#4CC9F0' };
  const darkText = new Set(['toxic', 'ice', 'ember']);
  function setAccent(name, remember) {
    if (!accents[name]) return;
    document.documentElement.style.setProperty('--accent', accents[name]);
    document.documentElement.style.setProperty('--on-accent', darkText.has(name) ? '#0B0A10' : '#FFFFFF');
    $$('.swatches [role="radio"]').forEach(b => b.setAttribute('aria-checked', String(b.dataset.accent === name)));
    const label = name[0].toUpperCase() + name.slice(1);
    swap($('#accent-img'), name === 'hellfire' ? '/assets/overview.png' : `/assets/overview-${name}.png`, `Fiend's Overview screen in the ${label} accent.`);
    if (remember) store.set('fiend-accent', name);
  }
  $$('.swatches [role="radio"]').forEach(b => b.addEventListener('click', () => setAccent(b.dataset.accent, true)));
  const saved = store.get('fiend-accent');
  if (saved && saved !== 'hellfire') setAccent(saved, false);

  // Release details (written by scripts/build.ps1)
  fetch('/downloads/release.json', { cache: 'no-cache' })
    .then(r => (r.ok ? r.json() : null))
    .then(rel => {
      if (!rel || !rel.installer || !rel.zip) return;
      // Keys look like "version" or "installer.sha256" / "zip.href".
      const values = { version: rel.version, built: rel.built };
      for (const kind of ['installer', 'zip']) {
        const pack = rel[kind];
        Object.assign(values, {
          [`${kind}.href`]: `/downloads/${pack.file}`,
          [`${kind}.file`]: pack.file,
          [`${kind}.sha256`]: pack.sha256,
          [`${kind}.shortHash`]: `${pack.sha256.slice(0, 8)}…${pack.sha256.slice(-8)}`,
          [`${kind}.sizeLabel`]: `${(pack.size / 1048576).toFixed(1)} MB`,
        });
      }
      $$('[data-release]').forEach(el => {
        const key = el.dataset.release;
        if (!values[key]) return;
        if (key.endsWith('.href')) el.href = values[key];
        else el.textContent = values[key];
      });
    })
    .catch(() => { /* keep the values baked into the page */ });

  // Copy checksum
  $$('[data-copy]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const el = document.getElementById(btn.dataset.copy);
      try {
        await navigator.clipboard.writeText(el.textContent.trim());
        btn.textContent = 'Copied';
      } catch {
        const range = document.createRange();
        range.selectNodeContents(el);
        const sel = getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
        btn.textContent = 'Press Ctrl+C';
      }
      setTimeout(() => { btn.textContent = 'Copy'; }, 1800);
    });
  });
})();
