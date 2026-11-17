import { defineConfig, devices } from '@playwright/test';

const suppliedURL = process.env.E2E_BASE_URL;
if (!suppliedURL) throw new Error('Set E2E_BASE_URL explicitly for deployed-service tests.');
let target: URL;
try { target = new URL(suppliedURL); }
catch { throw new Error('E2E_BASE_URL must be a valid origin URL.'); }
const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(target.hostname);
if (target.username || target.password || target.search || target.hash || target.pathname !== '/' ||
    (target.protocol !== 'https:' && !(loopback && target.protocol === 'http:'))) {
  throw new Error('E2E_BASE_URL must be an HTTPS origin, or an HTTP loopback origin, without credentials or a path.');
}

export default defineConfig({
  testDir: './tests/e2e/live',
  outputDir: 'test-results/live',
  timeout: 60_000,
  globalTimeout: 5 * 60_000,
  expect: { timeout: 10_000 },
  fullyParallel: false,
  workers: 1,
  retries: 0,
  forbidOnly: Boolean(process.env.CI),
  // Only sanitized status/error summaries leave the authenticated runner.
  reporter: [['./tests/e2e/live/reporter.cjs']],
  projects: [
    { name: 'smoke', testMatch: 'smoke.spec.ts', use: { ...devices['Desktop Chrome'] } },
    { name: 'authenticated', testMatch: 'session.spec.ts', use: { ...devices['Desktop Chrome'] } },
  ],
  use: {
    baseURL: target.origin,
    ignoreHTTPSErrors: false,
    trace: 'off',
    screenshot: 'off',
    video: 'off',
  },
});
