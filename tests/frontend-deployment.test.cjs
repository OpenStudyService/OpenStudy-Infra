const { test } = require('node:test');
const assert = require('node:assert/strict');
const { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, existsSync, realpathSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { resolve, join } = require('node:path');
const { spawnSync } = require('node:child_process');

const script = resolve(__dirname, '../scripts/deploy-frontend.sh');

function fixture(t) {
  const dir = mkdtempSync(join(tmpdir(), 'openstudy-frontend-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const frontend = join(dir, 'frontend with spaces');
  const bin = join(dir, 'bin');
  const log = join(dir, 'commands.jsonl');
  mkdirSync(join(frontend, 'scripts'), { recursive: true });
  mkdirSync(bin);
  for (const source of ['package.json', 'package-lock.json', 'index.html']) {
    writeFileSync(join(frontend, source), 'fixture');
  }
  writeFileSync(join(frontend, 'scripts/deploy-static.sh'), `#!/usr/bin/env bash
printf '["publish"]\\n' >> "$DEPLOY_TEST_LOG"
exit "$DEPLOY_TEST_PUBLISH_STATUS"
`);
  writeFileSync(join(bin, 'node'), `#!/bin/sh
printf '%s\\n' "$DEPLOY_TEST_NODE_VERSION"
`, { mode: 0o755 });
  for (const command of ['aws', 'npm']) {
    writeFileSync(join(bin, command), `#!${process.execPath}
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(process.env.DEPLOY_TEST_LOG, JSON.stringify({
  command: '${command}', args, cwd: process.cwd(),
  mode: process.env.VITE_API_MODE, api: process.env.VITE_API_BASE_URL,
}) + '\\n');
if ('${command}' === 'aws') {
  if (process.env.DEPLOY_TEST_STS_FAILURE) process.exit(11);
  console.log(process.env.DEPLOY_TEST_ACCOUNT || '123456789012');
}
if ('${command}' === 'npm' && args.join(' ') === process.env.DEPLOY_TEST_NPM_FAILURE) process.exit(12);
`, { mode: 0o755 });
  }
  return {
    frontend,
    env: {
      ...process.env,
      PATH: bin + ':' + process.env.PATH,
      FRONTEND_SOURCE_DIR: frontend,
      AWS_ACCOUNT_ID: '123456789012',
      AWS_REGION: 'ap-northeast-2',
      S3_BUCKET: 'example-frontend',
      CLOUDFRONT_DISTRIBUTION_ID: 'EXAMPLE123',
      DEPLOY_TEST_LOG: log,
      DEPLOY_TEST_NODE_VERSION: 'v24.19.0',
      DEPLOY_TEST_PUBLISH_STATUS: '0',
      VITE_API_MODE: 'mock',
      VITE_API_BASE_URL: '/wrong-api',
    },
    run(extraEnv = {}) {
      return spawnSync('bash', [script], { env: { ...this.env, ...extraEnv }, encoding: 'utf8' });
    },
    commands() {
      return existsSync(log) ? readFileSync(log, 'utf8').trim().split('\n').map(JSON.parse) : [];
    },
  };
}

test('apply checks the AWS account and builds the live app before publication', (t) => {
  const f = fixture(t);
  const result = f.run();
  assert.equal(result.status, 0, result.stderr);
  const commands = f.commands();
  assert.deepEqual(commands.map((entry) => entry.command || entry[0]), ['aws', 'npm', 'npm', 'npm', 'publish']);
  assert.deepEqual(commands[0].args, ['sts', 'get-caller-identity', '--region', 'ap-northeast-2', '--query', 'Account', '--output', 'text']);
  assert.deepEqual(commands.slice(1, 4).map((entry) => entry.args), [['ci', '--include=dev'], ['run', 'check'], ['run', 'build']]);
  for (const entry of commands.slice(1, 4)) {
    assert.equal(entry.cwd, realpathSync(f.frontend));
    assert.equal(entry.mode, 'live');
    assert.equal(entry.api, '/api');
  }
});

test('a different AWS account fails before installing or publishing', (t) => {
  const f = fixture(t);
  const result = f.run({ DEPLOY_TEST_ACCOUNT: '999999999999' });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /does not match/);
  assert.equal(f.commands().length, 1);
});

test('failed AWS authentication stops before installing or publishing', (t) => {
  const f = fixture(t);
  assert.notEqual(f.run({ DEPLOY_TEST_STS_FAILURE: '1' }).status, 0);
  assert.equal(f.commands().length, 1);
});

for (const failedCommand of ['ci --include=dev', 'run check', 'run build']) {
  test(`failed npm ${failedCommand} stops before publication`, (t) => {
    const f = fixture(t);
    assert.notEqual(f.run({ DEPLOY_TEST_NPM_FAILURE: failedCommand }).status, 0);
    assert.ok(!f.commands().some((entry) => entry[0] === 'publish'));
    assert.equal(f.commands().at(-1).args.join(' '), failedCommand);
  });
}

test('publisher failure fails the apply command', (t) => {
  const f = fixture(t);
  assert.equal(f.run({ DEPLOY_TEST_PUBLISH_STATUS: '23' }).status, 23);
});

test('unsupported Node.js fails before AWS authentication', (t) => {
  const f = fixture(t);
  const result = f.run({ DEPLOY_TEST_NODE_VERSION: 'v26.11.1' });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /requires Node.js 24/);
  assert.deepEqual(f.commands(), []);
});

test('an incomplete checkout fails before AWS authentication', (t) => {
  const f = fixture(t);
  rmSync(join(f.frontend, 'scripts/deploy-static.sh'));
  const result = f.run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Missing frontend source/);
  assert.deepEqual(f.commands(), []);
});
