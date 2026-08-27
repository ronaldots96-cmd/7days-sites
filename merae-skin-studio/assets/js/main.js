(() => {
  'use strict';

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  const track = (eventName, details = {}) => {
    const payload = { event: eventName, page: 'merae_skin_studio_concept', ...details };

    if (Array.isArray(window.dataLayer)) {
      window.dataLayer.push(payload);
    }

    window.dispatchEvent(new CustomEvent('merae:track', { detail: payload }));
  };

  const utmParams = {};
  const searchParams = new URLSearchParams(window.location.search);
  searchParams.forEach((value, key) => {
    if (key.toLowerCase().startsWith('utm_')) utmParams[key] = value;
  });

  try {
    if (Object.keys(utmParams).length) {
      sessionStorage.setItem('merae_utm', JSON.stringify(utmParams));
    }
  } catch (_) {
    // The experience does not depend on storage availability.
  }

  track('page_view', { ...utmParams });

  const menuToggle = document.querySelector('.menu-toggle');
  const mobileMenu = document.querySelector('#mobile-menu');

  const closeMenu = () => {
    menuToggle.setAttribute('aria-expanded', 'false');
    menuToggle.setAttribute('aria-label', 'Open menu');
    mobileMenu.hidden = true;
    document.body.classList.remove('is-menu-open');
  };

  menuToggle.addEventListener('click', () => {
    const isOpen = menuToggle.getAttribute('aria-expanded') === 'true';
    menuToggle.setAttribute('aria-expanded', String(!isOpen));
    menuToggle.setAttribute('aria-label', isOpen ? 'Open menu' : 'Close menu');
    mobileMenu.hidden = isOpen;
    document.body.classList.toggle('is-menu-open', !isOpen);
    track(isOpen ? 'menu_close' : 'menu_open');
  });

  mobileMenu.querySelectorAll('a').forEach(link => {
    link.addEventListener('click', closeMenu);
  });

  window.addEventListener('resize', () => {
    if (window.innerWidth > 1100 && !mobileMenu.hidden) closeMenu();
  });

  const goalContent = {
    lines: {
      index: '01 / 06',
      title: 'Soften the look of expression lines',
      body: 'A consultation can explore facial movement, what you want to preserve and whether a provider-led option belongs in your plan.',
      formValue: 'Expression lines'
    },
    texture: {
      index: '02 / 06',
      title: 'Support tone and texture',
      body: 'Start with what you see and feel. A provider can discuss skincare, renewal options, expected downtime and realistic next steps.',
      formValue: 'Tone and texture'
    },
    refresh: {
      index: '03 / 06',
      title: 'Refresh tired-looking skin',
      body: 'Explore hydration, skin quality and facial balance without assuming that one treatment—or any treatment—is automatically right.',
      formValue: 'Tired-looking skin'
    },
    balance: {
      index: '04 / 06',
      title: 'Explore facial balance',
      body: 'Discuss proportion, movement and the features you want to preserve. Suitability and tradeoffs should come before a recommendation.',
      formValue: 'Facial balance'
    },
    routine: {
      index: '05 / 06',
      title: 'Build a consistent skin routine',
      body: 'A steady plan may begin with skincare, periodic review and small adjustments rather than a long list of procedures.',
      formValue: 'A consistent skin routine'
    },
    laser: {
      index: '06 / 06',
      title: 'Learn about laser and light',
      body: 'Ask how technology-led options differ, what they may support and why skin type, history, timing and device choice all matter.',
      formValue: 'Laser and light'
    }
  };

  const goalTabs = [...document.querySelectorAll('.goal-tab')];
  const goalOutput = document.querySelector('#goal-output');
  const goalIndex = goalOutput.querySelector('.goal-index span');
  const goalTitle = goalOutput.querySelector('h3');
  const goalBody = goalOutput.querySelector('p:not(.goal-index)');
  let currentGoal = goalContent.lines.formValue;

  goalTabs.forEach(tab => {
    tab.addEventListener('click', () => {
      const content = goalContent[tab.dataset.goal];
      if (!content || tab.classList.contains('is-active')) return;

      goalTabs.forEach(item => {
        const isSelected = item === tab;
        item.classList.toggle('is-active', isSelected);
        item.setAttribute('aria-pressed', String(isSelected));
      });

      goalIndex.textContent = content.index;
      goalTitle.textContent = content.title;
      goalBody.textContent = content.body;
      currentGoal = content.formValue;

      goalOutput.classList.remove('is-updating');
      window.requestAnimationFrame(() => goalOutput.classList.add('is-updating'));
      window.setTimeout(() => goalOutput.classList.remove('is-updating'), 500);
      track('goal_selected', { goal: tab.dataset.goal });
    });
  });

  const bookingDialog = document.querySelector('#booking-dialog');
  const bookingForm = document.querySelector('#booking-form');
  const bookingClose = bookingDialog.querySelector('.dialog-close');
  const bookingDone = bookingDialog.querySelector('.dialog-done');
  const demoSuccess = document.querySelector('#demo-success');
  const bookingTriggers = [...document.querySelectorAll('.js-open-booking')];
  let lastFocusedElement = null;

  const focusableSelector = [
    'button:not([disabled])',
    'a[href]',
    'input:not([disabled])',
    'select:not([disabled])',
    'textarea:not([disabled])',
    '[tabindex]:not([tabindex="-1"])'
  ].join(',');

  const resetBooking = () => {
    bookingForm.reset();
    bookingForm.hidden = false;
    demoSuccess.hidden = true;
  };

  const openBooking = trigger => {
    lastFocusedElement = trigger;
    closeMenu();
    resetBooking();

    const goalSelect = bookingForm.elements.goal;
    if ([...goalSelect.options].some(option => option.value === currentGoal)) {
      goalSelect.value = currentGoal;
    }

    if (typeof bookingDialog.showModal === 'function') {
      bookingDialog.showModal();
    } else {
      bookingDialog.setAttribute('open', '');
    }

    document.body.classList.add('is-dialog-open');
    window.requestAnimationFrame(() => bookingClose.focus());
    track('booking_open', { source: trigger.dataset.track || 'unknown' });
  };

  const closeBooking = () => {
    if (typeof bookingDialog.close === 'function') {
      bookingDialog.close();
    } else {
      bookingDialog.removeAttribute('open');
      document.body.classList.remove('is-dialog-open');
      lastFocusedElement?.focus();
    }
  };

  bookingTriggers.forEach(trigger => {
    trigger.addEventListener('click', () => openBooking(trigger));
  });

  bookingClose.addEventListener('click', closeBooking);
  bookingDone.addEventListener('click', closeBooking);

  bookingDialog.addEventListener('click', event => {
    if (event.target === bookingDialog) closeBooking();
  });

  bookingDialog.addEventListener('close', () => {
    document.body.classList.remove('is-dialog-open');
    lastFocusedElement?.focus();
    track('booking_close');
  });

  bookingDialog.addEventListener('keydown', event => {
    if (event.key !== 'Tab') return;

    const focusable = [...bookingDialog.querySelectorAll(focusableSelector)].filter(element => !element.hidden && element.offsetParent !== null);
    if (!focusable.length) return;

    const first = focusable[0];
    const last = focusable[focusable.length - 1];

    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  });

  bookingForm.addEventListener('submit', event => {
    event.preventDefault();

    if (!bookingForm.checkValidity()) {
      bookingForm.reportValidity();
      track('booking_validation_error');
      return;
    }

    const selectedGoal = bookingForm.elements.goal.value;
    bookingForm.hidden = true;
    demoSuccess.hidden = false;
    demoSuccess.focus?.();
    bookingDone.focus();
    track('booking_demo_complete', { goal: selectedGoal });
  });

  document.querySelectorAll('[data-track]:not(.js-open-booking)').forEach(element => {
    element.addEventListener('click', () => track(element.dataset.track));
  });

  document.querySelectorAll('.faq-list details').forEach((detail, index) => {
    detail.addEventListener('toggle', () => {
      if (detail.open) track('faq_open', { item: index + 1 });
    });
  });

  const revealElements = [...document.querySelectorAll('.reveal')];

  if (reduceMotion || !('IntersectionObserver' in window) || window.location.hash) {
    revealElements.forEach(element => element.classList.add('is-visible'));
  } else {
    document.documentElement.classList.add('reveal-enabled');
    const revealObserver = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-visible');
        revealObserver.unobserve(entry.target);
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });

    revealElements.forEach(element => revealObserver.observe(element));
  }

  if (window.location.hash) {
    const initialTarget = document.querySelector(window.location.hash);
    if (initialTarget) {
      window.requestAnimationFrame(() => {
        initialTarget.scrollIntoView({ block: 'start' });
        window.requestAnimationFrame(() => document.documentElement.classList.remove('has-initial-hash'));
      });
    } else {
      document.documentElement.classList.remove('has-initial-hash');
    }
  }

  document.querySelector('#year').textContent = String(new Date().getFullYear());
})();
