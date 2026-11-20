(() => {
  const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ------------------------------------------------------------------------
     1. Living macOS Menu Bar: Scroll Runway Ring + Live Clock
     ------------------------------------------------------------------------ */
  const runwayPct = document.getElementById('runway-pct');
  const ringArc = document.querySelector('.mini-ring-arc');
  const starField = document.querySelector('.field');
  const ringCircumference = 2 * Math.PI * 9; // r=9 => ~56.55

  const updateScrollTelemetry = () => {
    const scrollTop = window.scrollY || document.documentElement.scrollTop;
    const maxScroll = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
    const progress = Math.min(1, Math.max(0, scrollTop / maxScroll));
    const remaining = Math.max(1, Math.round((1 - progress) * 100));

    if (runwayPct) {
      runwayPct.textContent = `${remaining}%`;
    }
    if (ringArc) {
      const offset = ringCircumference * (1 - remaining / 100);
      ringArc.style.setProperty('--ring-offset', offset.toFixed(2));
    }
    if (starField && !prefersReducedMotion) {
      starField.style.transform = `scale(1.1) translateY(${(-progress * 6).toFixed(2)}%)`;
    }
  };

  let ticking = false;
  window.addEventListener(
    'scroll',
    () => {
      if (!ticking) {
        window.requestAnimationFrame(() => {
          updateScrollTelemetry();
          ticking = false;
        });
        ticking = true;
      }
    },
    { passive: true }
  );
  updateScrollTelemetry();

  const clockEl = document.getElementById('menubar-clock');
  const updateClock = () => {
    if (!clockEl) return;
    const now = new Date();
    const hours = String(now.getHours()).padStart(2, '0');
    const mins = String(now.getMinutes()).padStart(2, '0');
    clockEl.textContent = `${hours}:${mins}`;
  };
  updateClock();
  window.setInterval(updateClock, 30000);

  /* ------------------------------------------------------------------------
     2. Scroll Reveal & Active Nav Spy
     ------------------------------------------------------------------------ */
  const revealEls = document.querySelectorAll('.reveal');
  if (!prefersReducedMotion && 'IntersectionObserver' in window) {
    const revealObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add('is-visible');
            revealObserver.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: '0px 0px -40px 0px' }
    );
    revealEls.forEach((el) => revealObserver.observe(el));
  } else {
    revealEls.forEach((el) => el.classList.add('is-visible'));
  }

  const navLinks = Array.from(document.querySelectorAll('[data-nav]'));
  const sections = navLinks
    .map((link) => document.getElementById(link.dataset.nav))
    .filter(Boolean);

  if (sections.length && 'IntersectionObserver' in window) {
    const spyObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          navLinks.forEach((link) => {
            link.classList.toggle('is-active', link.dataset.nav === entry.target.id);
          });
        });
      },
      { rootMargin: '-35% 0px -50% 0px' }
    );
    sections.forEach((sec) => spyObserver.observe(sec));
  }

  /* ------------------------------------------------------------------------
     3. Cursor Spotlight & Subtle Hero Tilt
     ------------------------------------------------------------------------ */
  if (!prefersReducedMotion) {
    document.querySelectorAll('[data-spotlight]').forEach((surface) => {
      surface.addEventListener('pointermove', (e) => {
        const rect = surface.getBoundingClientRect();
        surface.style.setProperty('--mx', `${e.clientX - rect.left}px`);
        surface.style.setProperty('--my', `${e.clientY - rect.top}px`);
      });
    });

    const tiltHost = document.querySelector('[data-tilt]');
    const tiltWindow = tiltHost?.querySelector('.window');
    if (tiltHost && tiltWindow) {
      tiltHost.addEventListener('pointermove', (e) => {
        const rect = tiltHost.getBoundingClientRect();
        const x = (e.clientX - rect.left) / rect.width - 0.5;
        const y = (e.clientY - rect.top) / rect.height - 0.5;
        tiltWindow.style.transform = `rotateY(${(x * 7).toFixed(2)}deg) rotateX(${(-y * 7).toFixed(2)}deg) translateY(-4px)`;
      });
      tiltHost.addEventListener('pointerleave', () => {
        tiltWindow.style.transform = '';
      });
    }
  }

  /* ------------------------------------------------------------------------
     4. Chapter 01 · Interactive OpenRouter Key Console
     ------------------------------------------------------------------------ */
  const capSlider = document.getElementById('cap-slider');
  const capReadout = document.getElementById('cap-readout');
  const toggleKeyBtn = document.getElementById('toggle-key-btn');
  const keyLed = document.getElementById('key-led');

  if (capSlider && capReadout) {
    capSlider.addEventListener('input', () => {
      const cap = Number(capSlider.value).toFixed(2);
      capReadout.textContent = `$21.60 / $${cap}`;
    });
  }

  if (toggleKeyBtn && keyLed) {
    toggleKeyBtn.addEventListener('click', () => {
      const paused = toggleKeyBtn.getAttribute('aria-pressed') === 'true';
      const nextPaused = !paused;
      toggleKeyBtn.setAttribute('aria-pressed', String(nextPaused));
      toggleKeyBtn.textContent = nextPaused ? 'Resume key' : 'Pause key';
      keyLed.classList.toggle('is-paused', nextPaused);
    });
  }

  /* ------------------------------------------------------------------------
     5. Chapter 03 · Interactive 3-Step Model Advisor Flow
     ------------------------------------------------------------------------ */
  const advisorFlow = document.getElementById('advisor-flow');

  if (advisorFlow) {
    const TASKS_BY_CAT = {
      coding: {
        label: 'Coding',
        complexity: 0.85,
        tasks: [
          { value: 'debug', label: 'Debug and fix bugs', bias: 0.9 },
          { value: 'refactor', label: 'Refactor architecture', bias: 1.0 },
          { value: 'tests', label: 'Write unit tests', bias: 0.45 },
        ],
      },
      reasoning: {
        label: 'Reasoning',
        complexity: 0.95,
        tasks: [
          { value: 'design', label: 'System design trade-offs', bias: 1.0 },
          { value: 'math', label: 'Formal proof & analysis', bias: 0.95 },
          { value: 'review', label: 'Audit security edge cases', bias: 0.8 },
        ],
      },
      writing: {
        label: 'Writing',
        complexity: 0.5,
        tasks: [
          { value: 'docs', label: 'Draft technical docs', bias: 0.55 },
          { value: 'release', label: 'Write release notes', bias: 0.35 },
          { value: 'rfc', label: 'Edit architecture RFC', bias: 0.7 },
        ],
      },
      triage: {
        label: 'Fast triage',
        complexity: 0.25,
        tasks: [
          { value: 'logs', label: 'Summarize error logs', bias: 0.25 },
          { value: 'classify', label: 'Classify incoming issues', bias: 0.15 },
          { value: 'extract', label: 'Extract structured JSON', bias: 0.2 },
        ],
      },
    };

    const CANDIDATES = {
      fable: {
        name: 'Claude Fable 5.2',
        slug: 'anthropic/claude-fable-5.2',
        tier: 'Frontier',
        price: '$8.00 / $40.00',
        cheapness: 15,
        intelligence: 65,
        effScore: '3/4',
        effBars: 3,
        effNote: 'Frontier intelligence for complex tasks',
      },
      sol: {
        name: 'Sol',
        slug: 'sol/sol-medium',
        tier: 'Balanced',
        price: '$2.40 / $10.00',
        cheapness: 62,
        intelligence: 57,
        effScore: '4/4',
        effBars: 4,
        effNote: 'Well balanced cost vs intelligence',
      },
      deepseek: {
        name: 'DeepSeek',
        slug: 'deepseek/deepseek-chat',
        tier: 'Fast',
        price: '$0.27 / $1.10',
        cheapness: 94,
        intelligence: 48,
        effScore: '4/4',
        effBars: 4,
        effNote: 'Optimized for cheapness and token runway',
      },
    };

    const PRESETS = {
      default: { pricing: 50, cheapness: 0, intelligence: 50, usage: 0 },
      smart: { pricing: 10, cheapness: 0, intelligence: 90, usage: 0 },
      frugal: { pricing: 25, cheapness: 45, intelligence: 10, usage: 20 },
    };

    let activeCat = 'coding';
    const catBtns = advisorFlow.querySelectorAll('.choice-pill[data-cat]');
    const taskSelect = document.getElementById('advisor-task');
    const modelSelect = document.getElementById('advisor-model');
    const presetBtns = advisorFlow.querySelectorAll('.preset-chip[data-preset]');
    const resetBtn = document.getElementById('weights-reset');
    const resultCard = advisorFlow.querySelector('.flow-card-result');

    const sliders = {
      pricing: document.getElementById('w-pricing'),
      cheapness: document.getElementById('w-cheapness'),
      intelligence: document.getElementById('w-intelligence'),
      usage: document.getElementById('w-usage'),
    };
    const sliderVals = {
      pricing: document.getElementById('w-pricing-val'),
      cheapness: document.getElementById('w-cheapness-val'),
      intelligence: document.getElementById('w-intelligence-val'),
      usage: document.getElementById('w-usage-val'),
    };

    const setActiveStep = (stepNum) => {
      const n = Number(stepNum);
      advisorFlow.dataset.activeStep = String(n);
      advisorFlow.querySelectorAll('[data-step-trigger]').forEach((item) => {
        const s = Number(item.dataset.stepTrigger);
        item.classList.toggle('is-active', s === n);
        item.classList.toggle('is-done', s < n);
      });
      advisorFlow.querySelectorAll('[data-flow-step]').forEach((card) => {
        const s = Number(card.dataset.flowStep);
        card.classList.toggle('is-active', s === n);
      });
    };

    const renderRecommendation = (pulse = false) => {
      const cat = TASKS_BY_CAT[activeCat];
      const taskObj = cat.tasks.find((t) => t.value === taskSelect.value) || cat.tasks[0];

      const wp = Number(sliders.pricing.value);
      const wc = Number(sliders.cheapness.value);
      const wi = Number(sliders.intelligence.value);
      const wu = Number(sliders.usage.value);
      const total = Math.max(1, wp + wc + wi + wu);

      const np = wp / total;
      const nc = wc / total;
      const ni = wi / total;
      const nu = wu / total;
      const taskNeed = (cat.complexity + taskObj.bias) / 2;
      const modelShift = modelSelect.value === 'openai' ? 1 : 0;

      // Rule-based advisory selection:
      // 1. Cheapness present -> DeepSeek
      // 2. Expensive & intelligent (high intelligence, low pricing concern) -> Claude Fable 5.2
      // 3. Medium balance -> Sol
      let ranked;
      if (wc > 0) {
        const deepPct = Math.min(82, 54 + Math.round((wc / total) * 28));
        const solPct = Math.max(12, Math.round((100 - deepPct) * 0.68));
        const fablePct = Math.max(4, 100 - deepPct - solPct);
        ranked = [
          { model: CANDIDATES.deepseek, pct: deepPct },
          { model: CANDIDATES.sol, pct: solPct },
          { model: CANDIDATES.fable, pct: fablePct },
        ];
      } else if (wi >= 65 && wp <= 35 && wu <= 25) {
        const fablePct = Math.min(78, 52 + Math.round((wi / total) * 24));
        const solPct = Math.max(16, Math.round((100 - fablePct) * 0.72));
        const deepPct = Math.max(4, 100 - fablePct - solPct);
        ranked = [
          { model: CANDIDATES.fable, pct: fablePct },
          { model: CANDIDATES.sol, pct: solPct },
          { model: CANDIDATES.deepseek, pct: deepPct },
        ];
      } else {
        const solPct = 58;
        const fablePct = wi >= wp ? 28 : 18;
        const deepPct = 100 - solPct - fablePct;
        ranked = [
          { model: CANDIDATES.sol, pct: solPct },
          { model: CANDIDATES.fable, pct: fablePct },
          { model: CANDIDATES.deepseek, pct: deepPct },
        ].sort((a, b) => b.pct - a.pct);
      }

      const top = ranked[0];
      const tierEl = document.getElementById('rec-tier');
      tierEl.textContent = top.model.tier;
      tierEl.dataset.tier = top.model.tier;

      document.getElementById('rec-model').textContent = top.model.name;
      document.getElementById('rec-slug').textContent = top.model.slug;
      document.getElementById('rec-conf').textContent = `${top.pct}% conf`;
      document.getElementById('rec-price').textContent = top.model.price;
      document.getElementById('rec-cheap').textContent = `${top.model.cheapness}/100`;
      document.getElementById('rec-intel').textContent = String(top.model.intelligence);
      document.getElementById('rec-eff-score').textContent = top.model.effScore;
      document.getElementById('rec-eff-note').textContent = top.model.effNote;

      const bars = document.querySelectorAll('#rec-eff-bars span');
      bars.forEach((b, i) => b.classList.toggle('is-filled', i < top.model.effBars));

      const candList = document.getElementById('rec-cand-list');
      candList.innerHTML = ranked
        .map(
          (item) => `
          <li>
            <div class="cand-meta"><span>${item.model.name}</span><span class="mono">${item.pct}%</span></div>
            <div class="cand-track"><div class="cand-fill" style="width: ${item.pct}%"></div></div>
          </li>`
        )
        .join('');

      const decisionLabel = modelSelect.value === 'openai' ? 'OpenAI Decisions API' : 'Jev 1.14';
      document.getElementById('rec-footnote').textContent =
        `Advisory · ${decisionLabel} · ${cat.label} / ${taskObj.label}`;

      if (pulse && resultCard && !prefersReducedMotion) {
        resultCard.classList.remove('is-evaluating');
        void resultCard.offsetWidth;
        resultCard.classList.add('is-evaluating');
      }
    };

    const syncSliderLabels = () => {
      Object.keys(sliders).forEach((k) => {
        sliderVals[k].textContent = `${sliders[k].value}%`;
      });
    };

    const applyPreset = (name) => {
      const p = PRESETS[name] || PRESETS.default;
      Object.keys(p).forEach((k) => {
        sliders[k].value = String(p[k]);
      });
      presetBtns.forEach((b) => b.classList.toggle('is-active', b.dataset.preset === name));
      syncSliderLabels();
      renderRecommendation(true);
    };

    catBtns.forEach((btn) => {
      btn.addEventListener('click', () => {
        activeCat = btn.dataset.cat;
        catBtns.forEach((b) => b.classList.toggle('is-active', b === btn));
        const tasks = TASKS_BY_CAT[activeCat].tasks;
        taskSelect.innerHTML = tasks
          .map((t) => `<option value="${t.value}">${t.label}</option>`)
          .join('');
        setActiveStep(1);
        renderRecommendation(false);
      });
    });

    taskSelect.addEventListener('change', () => {
      setActiveStep(1);
      renderRecommendation(false);
    });

    modelSelect.addEventListener('change', () => {
      setActiveStep(1);
      renderRecommendation(false);
    });

    Object.values(sliders).forEach((input) => {
      input.addEventListener('input', () => {
        presetBtns.forEach((b) => b.classList.remove('is-active'));
        syncSliderLabels();
        setActiveStep(2);
        renderRecommendation(false);
      });
    });

    presetBtns.forEach((btn) => {
      btn.addEventListener('click', () => {
        setActiveStep(2);
        applyPreset(btn.dataset.preset);
      });
    });

    if (resetBtn) {
      resetBtn.addEventListener('click', () => {
        setActiveStep(2);
        applyPreset('default');
      });
    }

    advisorFlow.querySelectorAll('[data-step-trigger]').forEach((item) => {
      item.querySelector('button')?.addEventListener('click', () => {
        const s = Number(item.dataset.stepTrigger);
        setActiveStep(s);
        if (s === 3) renderRecommendation(true);
      });
    });

    advisorFlow.querySelectorAll('[data-goto-step]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const target = Number(btn.dataset.gotoStep);
        setActiveStep(target);
        renderRecommendation(target === 3);
      });
    });

    // Click inside any card to activate that step
    advisorFlow.querySelectorAll('[data-flow-step]').forEach((card) => {
      card.addEventListener('pointerdown', () => {
        setActiveStep(Number(card.dataset.flowStep));
      });
    });

    syncSliderLabels();
    renderRecommendation(false);
  }

  /* ------------------------------------------------------------------------
     6. Chapter 04 · Connections (Multi-account -> CLIProxyAPI -> Subscription)
     ------------------------------------------------------------------------ */
  const sourcesFlow = document.getElementById('sources-flow');
  const sourcesShot = document.getElementById('sources-screenshot');
  const sourcesTabs = document.querySelectorAll('[data-sources-view]');

  if (sourcesFlow && sourcesShot && sourcesTabs.length) {
    sourcesTabs.forEach((tab) => {
      tab.addEventListener('click', () => {
        const showFlow = tab.dataset.sourcesView === 'flow';
        sourcesFlow.hidden = !showFlow;
        sourcesShot.hidden = showFlow;
        sourcesTabs.forEach((btn) => {
          const active = btn === tab;
          btn.classList.toggle('is-active', active);
          btn.setAttribute('aria-selected', String(active));
        });
      });
    });
  }

  if (sourcesFlow) {
    const providerAccounts = {
      codex: '2 accounts',
      claude: '2 accounts',
      grok: '1 account',
    };
    const modes = { codex: 'proxy', grok: 'proxy', claude: 'proxy' };

    const masterBtns = sourcesFlow.querySelectorAll('[data-master-route]');
    const providerBtns = sourcesFlow.querySelectorAll('[data-provider][data-mode]');

    const syncConnectionsUI = () => {
      Object.keys(modes).forEach((prov) => {
        const mode = modes[prov];
        sourcesFlow
          .querySelectorAll(`[data-provider="${prov}"]`)
          .forEach((btn) => btn.classList.toggle('is-active', btn.dataset.mode === mode));

        const badge = sourcesFlow.querySelector(`[data-sub-badge="${prov}"]`);
        if (badge) {
          badge.classList.toggle('is-direct', mode === 'direct');
          badge.textContent =
            mode === 'proxy'
              ? `CLIProxyAPI · ${providerAccounts[prov]}`
              : 'Direct · Keychain';
        }
      });

      const vals = Object.values(modes);
      const allProxy = vals.every((m) => m === 'proxy');
      const allDirect = vals.every((m) => m === 'direct');
      masterBtns.forEach((btn) => {
        const isMatch =
          (btn.dataset.masterRoute === 'proxy' && allProxy) ||
          (btn.dataset.masterRoute === 'direct' && allDirect);
        btn.classList.toggle('is-active', isMatch);
      });
    };

    masterBtns.forEach((btn) => {
      btn.addEventListener('click', () => {
        const targetMode = btn.dataset.masterRoute;
        Object.keys(modes).forEach((k) => {
          modes[k] = targetMode;
        });
        syncConnectionsUI();
      });
    });

    providerBtns.forEach((btn) => {
      btn.addEventListener('click', () => {
        modes[btn.dataset.provider] = btn.dataset.mode;
        syncConnectionsUI();
      });
    });

    syncConnectionsUI();
  }

  /* ------------------------------------------------------------------------
     7. Screenshot Lightbox
     ------------------------------------------------------------------------ */
  const lightbox = document.getElementById('lightbox');
  const lightboxImg = document.getElementById('lightbox-img');
  const lightboxCaption = document.getElementById('lightbox-caption');
  const lightboxClose = document.getElementById('lightbox-close');

  const openLightbox = (el) => {
    if (!lightbox || !lightboxImg) return;
    lightboxImg.src = el.dataset.lightbox;
    lightboxImg.alt = el.dataset.caption || '';
    if (lightboxCaption) {
      lightboxCaption.textContent = el.dataset.caption || '';
    }
    lightbox.showModal();
  };

  document.querySelectorAll('[data-lightbox]').forEach((trigger) => {
    trigger.addEventListener('click', () => openLightbox(trigger));
    trigger.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        openLightbox(trigger);
      }
    });
  });

  if (lightbox && lightboxClose) {
    lightboxClose.addEventListener('click', () => lightbox.close());
    lightbox.addEventListener('click', (e) => {
      if (e.target === lightbox) lightbox.close();
    });
  }
})();
