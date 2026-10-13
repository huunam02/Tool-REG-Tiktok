String buildProxyIpCheckScript(int navigationId) => '''
(async () => {
  let timeout;
  try {
    const abort = new AbortController();
    timeout = setTimeout(() => abort.abort(), 8000);
    const response = await fetch('https://api.ipify.org?format=json', {
      cache: 'no-store', signal: abort.signal,
    });
    if (!response.ok) throw new Error('IP check failed');
    const data = await response.json();
    if (typeof data.ip !== 'string' || !data.ip) {
      throw new Error('Missing IP');
    }
    await window.flutter_inappwebview.callHandler(
      'FlutterProxyIp', $navigationId, data.ip,
    );
  } catch (_) {
    await window.flutter_inappwebview.callHandler(
      'FlutterProxyIp', $navigationId, 'Không xác định',
    );
  } finally {
    clearTimeout(timeout);
  }
})();
''';
