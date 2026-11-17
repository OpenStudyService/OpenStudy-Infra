import { test, expect } from '@playwright/test';

test('login, reload, CSRF denial and logout preserve the session contract', async ({ page, context, baseURL }) => {
  const email = process.env.E2E_EMAIL;
  const password = process.env.E2E_PASSWORD;
  if (!email || !password) throw new Error('Authenticated E2E requires both E2E_EMAIL and E2E_PASSWORD. Use --project=smoke for anonymous checks.');

  await page.goto('/login');
  const csrfResponse = await page.request.get('/api/auth/csrf');
  expect(csrfResponse.status()).toBe(200);
  const anonymousSession = (await context.cookies(baseURL!)).find(cookie => cookie.name === 'SESSION')?.value;
  try {
    await test.step('sign in through the visible form', async () => {
      await page.getByLabel('이메일', { exact: true }).fill(email);
      await page.getByLabel('비밀번호', { exact: true }).fill(password);
      const loggedIn = page.waitForResponse(response =>
        new URL(response.url()).pathname === '/api/auth/login' && response.request().method() === 'POST');
      await page.getByRole('button', { name: '로그인', exact: true }).click();
      expect((await loggedIn).status()).toBe(200);
      await expect(page).toHaveURL(/\/app\/[^/]+\/home$/);
      await expect(page.getByRole('button', { name: '사용자 메뉴', exact: true })).toBeVisible();
    });

    const homeURL = page.url();
    const session = (await context.cookies(baseURL!)).find(cookie => cookie.name === 'SESSION');
    expect(Boolean(session)).toBe(true);
    expect(session?.httpOnly).toBe(true);
    expect(session?.path).toBe('/');
    expect(session?.sameSite).toBe('Lax');
    if (baseURL!.startsWith('https:')) expect(session?.secure).toBe(true);
    if (anonymousSession) expect(session?.value !== anonymousSession).toBe(true);

    await page.reload();
    await expect(page.getByRole('button', { name: '사용자 메뉴', exact: true })).toBeVisible();
    expect((await page.request.get('/api/me')).status()).toBe(200);

    await test.step('reject a request without CSRF without ending the session', async () => {
      expect((await page.request.post('/api/auth/logout', { data: {} })).status()).toBe(403);
      expect((await page.request.get('/api/me')).status()).toBe(200);
    });

    if (process.env.E2E_REQUIRE_AI === 'true') {
      await test.step('verify the AI catalog and installed embedding model', async () => {
        const response = await page.request.get('/api/ai/catalog/readiness');
        expect(response.status()).toBe(200);
        const readiness = await response.json();
        expect(readiness.ready).toBe(true);
        expect(Array.isArray(readiness.warnings) && readiness.warnings.length === 0).toBe(true);
      });
    }

    await page.getByRole('button', { name: '사용자 메뉴', exact: true }).click();
    await page.getByRole('menuitem', { name: '로그아웃', exact: true }).click();
    await expect(page).toHaveURL(/\/login(?:\?|$)/);
    expect((await page.request.get('/api/me')).status()).toBe(401);
    expect((await context.cookies(baseURL!)).some(cookie => cookie.name === 'SESSION')).toBe(false);
    await page.goto(homeURL);
    await expect(page).toHaveURL(/\/login(?:\?|$)/);
  } finally {
    // End only this test's session, including after an assertion failure.
    const csrf = await page.request.get('/api/auth/csrf');
    if (csrf.ok()) {
      const token = (await csrf.json()).token;
      if (typeof token === 'string') {
        await page.request.post('/api/auth/logout', { data: {}, headers: { 'X-CSRF-Token': token } });
      }
    }
  }
});
