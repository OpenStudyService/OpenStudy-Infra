import { test as base, expect } from '@playwright/test';

type Site = { http: string; https: string };
type Sites = Record<'unconfigured' | 'demo' | 'proxy', Site>;
const test = base.extend<{ sites: Sites }>({
  sites: async ({ request }, use) => {
    const response = await request.get('/config');
    expect(response.ok()).toBeTruthy();
    await use(await response.json());
  },
});

for (const mode of ['unconfigured', 'demo', 'proxy'] as const) {
  test(`${mode}: browser loads SPA routes and the real static asset`, async ({ page, sites }) => {
    for (const route of ['/', '/login', '/app/all/home', '/invitations/accept?token=fixture']) {
      const response = await page.goto(sites[mode].https + route);
      expect(response?.status()).toBe(200);
      await expect(page.getByRole('heading', { name: 'OpenStudy deployment fixture' })).toBeVisible();
      await expect(page.locator('html')).toHaveAttribute('data-asset-loaded', 'true');
    }
  });

  test(`${mode}: redirects preserve paths and missing assets stay 404`, async ({ request, sites }) => {
    const redirect = await request.get(sites[mode].http + '/login?next=%2Fapp', { maxRedirects: 0 });
    expect(redirect.status()).toBe(308);
    expect(redirect.headers().location).toBe('https://openstudy.example.test/login?next=%2Fapp');
    const asset = await request.get(sites[mode].https + '/assets/app-e2e.js');
    expect(asset.status()).toBe(200);
    expect(asset.headers()['cache-control']).toContain('immutable');
    for (const path of ['/assets/missing.js', '/missing.css']) {
      expect((await request.get(sites[mode].https + path)).status()).toBe(404);
    }
  });
}

test('missing backend returns JSON 503 in the browser', async ({ page, sites }) => {
  await page.goto(sites.unconfigured.https);
  const result = await page.evaluate(async () => {
    const response = await fetch('/api/echo');
    return { status: response.status, type: response.headers.get('content-type'), data: await response.json() };
  });
  expect(result.status).toBe(503);
  expect(result.type).toContain('application/json');
  expect(result.data.message).toBe('Backend origin is not configured.');
});

test('browser sends secure cookies and CSRF headers through the proxy', async ({ page, context, sites }) => {
  await context.addCookies([{ name: 'SESSION', value: 'fixture-session', url: sites.proxy.https,
    secure: true, httpOnly: true, sameSite: 'Lax' }]);
  await page.goto(sites.proxy.https);
  const data = await page.evaluate(async () => {
    const response = await fetch('/api/echo?branch=fixture', {
      method: 'POST', credentials: 'include', headers: { 'X-CSRF-Token': 'fixture-csrf' },
    });
    return response.json();
  });
  expect(data).toMatchObject({ uri: '/api/echo?branch=fixture', proto: 'https',
    cookie: 'SESSION=fixture-session', csrf: 'fixture-csrf', method: 'POST' });
  expect(await page.evaluate(() => document.cookie)).not.toContain('SESSION');
});

test('browser CORS preflight succeeds only for an allowed origin', async ({ page, sites, baseURL }) => {
  await page.goto('/');
  const result = await page.evaluate(async (url) => {
    const response = await fetch(url + '/api/echo', { method: 'POST', credentials: 'include',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': 'fixture-csrf' }, body: '{}' });
    return { status: response.status, data: await response.json() };
  }, sites.proxy.https);
  expect(result.status).toBe(200);
  expect(result.data.csrf).toBe('fixture-csrf');

  const untrustedOrigin = baseURL!.replace('127.0.0.1', 'localhost');
  await page.goto(untrustedOrigin); // Same fixture server, different origin absent from the allowlist.
  const blocked = await page.evaluate(async (url) => {
    try {
      await fetch(url + '/api/echo', { method: 'POST', headers: { 'X-CSRF-Token': 'fixture-csrf' } });
      return false;
    } catch (error) {
      return error instanceof TypeError;
    }
  }, sites.proxy.https);
  expect(blocked).toBe(true);
  const denied = await page.request.get(sites.proxy.https + '/api/echo', { headers: { Origin: untrustedOrigin } });
  expect(denied.status()).toBe(403);
  expect(denied.headers()['access-control-allow-origin']).toBeUndefined();
});

test('proxy errors retain one credential-compatible CORS policy', async ({ request, sites, baseURL }) => {
  const response = await request.get(sites.proxy.https + '/api/denied', { headers: { Origin: baseURL! } });
  expect(response.status()).toBe(401);
  const origins = response.headersArray().filter(header => header.name.toLowerCase() === 'access-control-allow-origin');
  expect(origins).toHaveLength(1);
  expect(origins[0].value).toBe(baseURL);
  expect(response.headers()['access-control-allow-credentials']).toBe('true');
});

test('demo authentication accepts only the disposable fixture credentials', async ({ page, sites }) => {
  await page.goto(sites.demo.https + '/login');
  for (const [password, status] of [['wrong', 401], ['disposable-playwright-password', 200]] as const) {
    const result = await page.evaluate(async (password) => {
      const response = await fetch('/api/test-login', { method: 'POST',
        headers: { Authorization: `Basic ${btoa('demo@example.test:' + password)}` } });
      return { status: response.status, data: await response.json(),
        challenge: response.headers.get('www-authenticate'), cache: response.headers.get('cache-control') };
    }, password);
    expect(result.status).toBe(status);
    expect(result.data.ok).toBe(status === 200);
    expect(result.challenge).toBeNull();
    expect(result.cache).toBe('no-store');
  }
});

test('the generated certificate is rejected without explicit local trust bypass', async ({ playwright, sites }) => {
  const client = await playwright.request.newContext({ ignoreHTTPSErrors: false });
  try {
    await expect(client.get(sites.proxy.https)).rejects.toThrow(/certificate/i);
  } finally {
    await client.dispose();
  }
});
