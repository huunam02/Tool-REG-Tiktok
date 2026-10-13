/// Closes TikTok's country or region dialog when it appears after navigation.
const autoCloseCountryModalScript = r'''
(() => {
  if (window.__countryModalObserverActive) return;
  window.__countryModalObserverActive = true;

  const observer = new MutationObserver(() => {
    const headings = document.querySelectorAll('h1, h2, h3, h4, div, span');
    for (const element of headings) {
      const text = (element.innerText || element.textContent || '')
        .trim().toLowerCase();
      if (!text.includes('select country') &&
          !text.includes('select region') &&
          !text.includes('chọn quốc gia') &&
          !text.includes('chọn khu vực')) continue;

      const buttons = document.querySelectorAll('button, a, [role="button"]');
      for (const button of buttons) {
        const label = (button.innerText || button.textContent || '')
          .trim().toLowerCase();
        if (label === 'done' || label === 'xong' || label === 'hoàn tất') {
          button.click();
          return;
        }
      }
    }
  });

  observer.observe(document.body, { childList: true, subtree: true });
})();
''';
