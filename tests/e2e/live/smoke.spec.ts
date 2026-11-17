import { test, expect } from '@playwright/test';

test('real login page loads without demo controls or a mock service worker', async ({ page }) => {
  const errors: string[] = [];
  const workers: string[] = [];
  page.on('pageerror', error => errors.push(error.name));
  page.on('request', request => {
    if (new URL(request.url()).pathname.includes('mockServiceWorker')) workers.push('mock worker requested');
  });
  const response = await page.goto('/login');
  expect(response?.status()).toBe(200);
  await expect(page.getByLabel('이메일', { exact: true })).toBeVisible();
  await expect(page.getByLabel('비밀번호', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: '로그인', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: '사장님으로 체험', exact: true })).toHaveCount(0);
  expect(workers).toHaveLength(0);
  expect(await page.evaluate(() => navigator.serviceWorker.getRegistrations().then(items => items.length))).toBe(0);
  expect(errors).toHaveLength(0);
});

test('anonymous protected navigation returns to login', async ({ page }) => {
  await page.goto('/app/all/home');
  await expect(page).toHaveURL(/\/login(?:\?|$)/);
  await expect(page.getByRole('button', { name: '로그인', exact: true })).toBeVisible();
});

test('real API issues CSRF tokens and refuses anonymous access', async ({ request }) => {
  const currentUser = await request.get('/api/me');
  expect(currentUser.status()).toBe(401);
  expect(currentUser.headers()['content-type']).toContain('application/json');
  const csrf = await request.get('/api/auth/csrf');
  expect(csrf.status()).toBe(200);
  expect(csrf.headers()['content-type']).toContain('application/json');
  const body = await csrf.json();
  expect(typeof body.token === 'string' && body.token.length > 0).toBe(true);
  expect((await request.post('/api/auth/logout', { data: {} })).status()).toBe(403);
});
