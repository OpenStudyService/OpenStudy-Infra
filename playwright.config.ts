import { defineConfig, devices } from '@playwright/test';

const port = Number(process.env.E2E_STACK_PORT ?? 18700);
if (!Number.isInteger(port) || port < 1024 || port > 65528) {
  throw new Error('E2E_STACK_PORT must be an integer from 1024 to 65528.');
}

export default defineConfig({
  testDir: './tests/e2e/local',
  outputDir: 'test-results/local',
  timeout: 30_000,
  globalTimeout: 10 * 60_000,
  expect: { timeout: 5_000 },
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  workers: 2,
  reporter: [['list'], ['html', { outputFolder: 'playwright-report/local', open: 'never' }]],
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    // Only the disposable local stack uses a generated, untrusted test certificate.
    ignoreHTTPSErrors: true,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'off',
  },
  webServer: {
    command: `python3 scripts/e2e-stack.py --port ${port}`,
    url: `http://127.0.0.1:${port}/ready`,
    reuseExistingServer: false,
    timeout: 180_000,
    gracefulShutdown: { signal: 'SIGTERM', timeout: 20_000 },
    stdout: 'pipe',
    stderr: 'pipe',
  },
});
