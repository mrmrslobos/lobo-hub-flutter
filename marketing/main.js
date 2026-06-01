(function () {
  const cfg = window.HUDDLE_MARKETING || {};
  const form = document.getElementById('waitlist-form');
  const msg = document.getElementById('form-message');
  const emailInput = document.getElementById('waitlist-email');

  const playUrl = cfg.googlePlayUrl || '';
  const hasPlay = playUrl.length > 0;

  function signupUrl(email) {
    const base = (cfg.appUrl || '').replace(/\/$/, '');
    const path = cfg.signupPath || '/auth';
    const url = new URL(path, base || window.location.origin);
    if (email) url.searchParams.set('email', email);
    return url.toString();
  }

  /** Primary CTA: Play Store when configured, else web app. */
  function primarySignupUrl() {
    if (hasPlay) return playUrl;
    if (cfg.appUrl) return signupUrl();
    return '#';
  }

  document.querySelectorAll('[data-play-store]').forEach((el) => {
    if (hasPlay) {
      el.setAttribute('href', playUrl);
      el.setAttribute('target', '_blank');
      el.setAttribute('rel', 'noopener noreferrer');
    } else {
      el.classList.add('hidden');
    }
  });

  document.querySelectorAll('[data-signup]').forEach((el) => {
    const target = primarySignupUrl();
    if (target !== '#') {
      el.setAttribute('href', target);
      if (hasPlay) {
        el.setAttribute('target', '_blank');
        el.setAttribute('rel', 'noopener noreferrer');
      }
    }
    el.addEventListener('click', (e) => {
      if (hasPlay) return;
      const email = emailInput?.value?.trim();
      if (cfg.appUrl) {
        e.preventDefault();
        window.location.href = signupUrl(email);
      }
    });
  });

  document.querySelectorAll('[data-app-link]').forEach((el) => {
    if (cfg.appUrl) {
      el.setAttribute('href', signupUrl());
    }
  });

  const trialEl = document.getElementById('trial-days');
  if (trialEl && cfg.trialDays) trialEl.textContent = String(cfg.trialDays);

  const header = document.querySelector('.site-header');
  window.addEventListener(
    'scroll',
    () => header?.classList.toggle('scrolled', window.scrollY > 8),
    { passive: true },
  );

  if (!form) return;

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const email = emailInput?.value?.trim();
    if (!email || !email.includes('@')) {
      showMessage('Please enter a valid email address.', true);
      return;
    }

    const btn = form.querySelector('button[type="submit"]');
    btn.disabled = true;
    showMessage('Submitting…', false);

    try {
      const mode = cfg.waitlistMode || 'mailto';
      if (mode === 'none') {
        showMessage('Thanks! Download the app to get started.', false);
        if (hasPlay) window.open(playUrl, '_blank', 'noopener,noreferrer');
        form.reset();
      } else if (mode === 'supabase' && cfg.supabaseUrl && cfg.supabaseAnonKey) {
        await submitSupabase(email);
        showMessage("You're on the list! Download Huddle on Google Play when you're ready.", false);
        form.reset();
      } else if (mode === 'formspree' && cfg.formspreeFormId) {
        await submitFormspree(email);
        showMessage("Thanks — you're on the waitlist.", false);
        form.reset();
      } else if (mode === 'mailto') {
        window.location.href = `mailto:${cfg.supportEmail || 'support@huddleapp.com.au'}?subject=${encodeURIComponent('Huddle release waitlist')}&body=${encodeURIComponent('Please notify me at launch:\n\n' + email)}`;
        showMessage('Opening your email app…', false);
      } else {
        showMessage('Use Google Play to download Huddle, or email support.', true);
      }
    } catch (err) {
      console.error(err);
      const text = err?.message || String(err);
      if (text.includes('duplicate') || text.includes('23505')) {
        showMessage("You're already signed up — we'll be in touch soon.", false);
      } else {
        showMessage('Something went wrong. Please try again or email support.', true);
      }
    } finally {
      btn.disabled = false;
    }
  });

  async function submitSupabase(email) {
    const url = `${cfg.supabaseUrl.replace(/\/$/, '')}/rest/v1/release_signups`;
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        apikey: cfg.supabaseAnonKey,
        Authorization: `Bearer ${cfg.supabaseAnonKey}`,
        'Content-Type': 'application/json',
        Prefer: 'return=minimal',
      },
      body: JSON.stringify({ email, source: 'marketing' }),
    });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(body || `HTTP ${res.status}`);
    }
  }

  async function submitFormspree(email) {
    const res = await fetch(`https://formspree.io/f/${cfg.formspreeFormId}`, {
      method: 'POST',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, _subject: 'Huddle release waitlist' }),
    });
    if (!res.ok) throw new Error('Formspree error');
  }

  function showMessage(text, isError) {
    if (!msg) return;
    msg.textContent = text;
    msg.className = 'form-message ' + (isError ? 'err' : 'ok');
  }
})();
