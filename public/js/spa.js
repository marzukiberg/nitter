// SPA Navigation Engine for Nitter using instant fetch & DOM morphing (Swup/Turbo-like lightweight engine)
(function() {
  let isNavigating = false;
  let topProgressBar = null;

  function createProgressBar() {
    if (!topProgressBar) {
      topProgressBar = document.createElement('div');
      topProgressBar.id = 'spa-progress-bar';
      document.body.appendChild(topProgressBar);
    }
  }

  function startProgress() {
    createProgressBar();
    topProgressBar.style.transition = 'none';
    topProgressBar.style.width = '0%';
    topProgressBar.style.opacity = '1';
    requestAnimationFrame(() => {
      topProgressBar.style.transition = 'width 0.4s ease-out';
      topProgressBar.style.width = '70%';
    });
  }

  function finishProgress() {
    if (topProgressBar) {
      topProgressBar.style.transition = 'width 0.15s ease-out, opacity 0.3s ease 0.15s';
      topProgressBar.style.width = '100%';
      topProgressBar.style.opacity = '0';
    }
  }

  async function navigate(url, pushState = true) {
    if (isNavigating) return;
    isNavigating = true;
    startProgress();

    try {
      const response = await fetch(url, {
        headers: { 'X-Requested-With': 'SPA' }
      });

      if (!response.ok) {
        window.location.href = url;
        return;
      }

      const htmlText = await response.text();
      const parser = new DOMParser();
      const newDoc = parser.parseFromString(htmlText, 'text/html');

      // Update Title
      document.title = newDoc.title;

      // Swap main container content
      const currentContainer = document.querySelector('.container');
      const newContainer = newDoc.querySelector('.container');

      if (currentContainer && newContainer) {
        currentContainer.innerHTML = newContainer.innerHTML;
        currentContainer.className = newContainer.className;
      } else {
        window.location.href = url;
        return;
      }

      // Update URL in browser history
      if (pushState) {
        window.history.pushState({ url }, '', url);
      }

      window.scrollTo(0, 0);

      // Re-trigger scripts like infinite scroll or video players if needed
      document.dispatchEvent(new CustomEvent('spa:navigated', { detail: { url } }));

    } catch (err) {
      console.error('SPA navigation failed, falling back to full load:', err);
      window.location.href = url;
    } finally {
      finishProgress();
      isNavigating = false;
    }
  }

  // Intercept all internal anchor clicks
  document.addEventListener('click', (e) => {
    const anchor = e.target.closest('a');
    if (!anchor) return;

    const href = anchor.getAttribute('href');
    if (!href) return;

    // Ignore external links, downloads, new tabs, media links, and anchors
    if (
      anchor.target === '_blank' ||
      anchor.hasAttribute('download') ||
      href.startsWith('http://') ||
      href.startsWith('https://') ||
      href.startsWith('mailto:') ||
      href.startsWith('#') ||
      href.startsWith('/pic/') ||
      href.startsWith('/video/') ||
      e.ctrlKey || e.metaKey || e.shiftKey || e.altKey
    ) {
      return;
    }

    e.preventDefault();
    navigate(anchor.href, true);
  });

  // Handle browser Back / Forward buttons
  window.addEventListener('popstate', (e) => {
    navigate(window.location.href, false);
  });

  // Intercept GET form submissions (e.g. search form)
  document.addEventListener('submit', (e) => {
    const form = e.target;
    if (form.method.toLowerCase() === 'get' && form.action) {
      const url = new URL(form.action, window.location.origin);
      const formData = new FormData(form);
      const params = new URLSearchParams();
      for (const [key, value] of formData.entries()) {
        if (value) params.append(key, value);
      }
      const targetUrl = url.pathname + (params.toString() ? '?' + params.toString() : '');
      e.preventDefault();
      navigate(targetUrl, true);
    }
  });
})();
