const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const { resolve } = require('node:path');

const source = readFileSync(resolve(__dirname, '../terraform/frontend/functions/spa.js'), 'utf8');
const handler = runInNewContext(source + '\nhandler;');

test('SPA navigation uses the root document and preserves query parameters', () => {
  for (const uri of ['/', '/login', '/app/all/home', '/invitations/accept']) {
    const request = { uri, querystring: { token: { value: 'example' } } };
    assert.equal(handler({ request }).uri, '/index.html');
    assert.equal(request.querystring.token.value, 'example');
  }
});

test('asset requests keep their original paths, including missing assets', () => {
  for (const uri of ['/assets/index-abc.js', '/assets/missing', '/favicon.svg', '/missing.js']) {
    assert.equal(handler({ request: { uri } }).uri, uri);
  }
});

test('unconfigured API calls fail as JSON instead of serving the SPA', () => {
  for (const uri of ['/api', '/api/session', '/api/events/']) {
    const response = handler({ request: { uri } });
    assert.equal(response.statusCode, 503);
    assert.equal(response.headers['cache-control'].value, 'no-store');
    assert.equal(response.headers['content-type'].value, 'application/json');
    assert.equal(response.body.encoding, 'text');
    assert.match(JSON.parse(response.body.data).message, /not configured/);
  }
});
