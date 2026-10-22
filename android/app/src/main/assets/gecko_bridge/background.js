'use strict';

// GeckoSession owns the User-Agent. The extension removes Android's optional
// embedding header from every request so pages cannot identify the host app.
browser.webRequest.onBeforeSendHeaders.addListener(
  details => ({
    requestHeaders: (details.requestHeaders || []).filter(
      header => header.name.toLowerCase() !== 'x-requested-with',
    ),
  }),
  {urls: ['<all_urls>']},
  ['blocking', 'requestHeaders'],
);
