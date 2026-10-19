function handler(event) {
  var request = event.request;
  var uri = request.uri;

  // API behaviors bypass this function when a Backend origin is configured.
  if (uri === '/api' || uri.startsWith('/api/')) {
    return {
      statusCode: 503,
      statusDescription: 'Service Unavailable',
      headers: {
        'content-type': { value: 'application/json' },
        'cache-control': { value: 'no-store' },
      },
      body: {
        encoding: 'text',
        data: JSON.stringify({ message: 'Backend origin is not configured.' }),
      },
    };
  }

  // Missing assets must remain errors instead of returning HTML.
  var fileName = uri.substring(uri.lastIndexOf('/') + 1);
  if (!uri.startsWith('/assets/') && !fileName.includes('.')) {
    request.uri = '/index.html';
  }
  return request;
}
