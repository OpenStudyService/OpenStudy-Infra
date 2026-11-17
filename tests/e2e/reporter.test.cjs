const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const LiveReporter = require('./live/reporter.cjs');

function isolatedReporter(callback) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'openstudy-reporter-'));
  const original = { cwd: process.cwd(), email: process.env.E2E_EMAIL, password: process.env.E2E_PASSWORD,
    log: console.log, error: console.error };
  const messages = [];
  try {
    process.chdir(directory);
    process.env.E2E_EMAIL = 'fixture@example.test';
    process.env.E2E_PASSWORD = 'fixture-"secret\\value';
    console.log = console.error = message => messages.push(String(message));
    callback(new LiveReporter(), directory, messages);
  } finally {
    process.chdir(original.cwd);
    for (const [key, value] of [['E2E_EMAIL', original.email], ['E2E_PASSWORD', original.password]]) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
    console.log = original.log;
    console.error = original.error;
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

test('authenticated failures redact literal, escaped and URL-encoded credentials', () => {
  isolatedReporter((reporter, directory, messages) => {
    const secret = process.env.E2E_PASSWORD;
    const values = [secret, JSON.stringify(secret).slice(1, -1), encodeURIComponent(secret), process.env.E2E_EMAIL];
    reporter.onTestEnd({ title: 'login' }, { status: 'failed', errors: [{ message: values.join('\n') }] });
    reporter.onError({ message: 'worker failure: ' + secret });
    reporter.onEnd({ status: 'failed' });
    const file = path.join(directory, 'test-results/live/summary.json');
    const summary = JSON.parse(fs.readFileSync(file, 'utf8'));
    assert.equal(summary.status, 'failed');
    assert.equal(summary.tests[0].errors[0], values.map(() => '[REDACTED]').join('\n'));
    assert.equal(summary.errors[0], 'worker failure: [REDACTED]');
    for (const value of values) assert.equal(messages.join('\n').includes(value), false);
    assert.equal(fs.statSync(file).mode & 0o777, 0o600);
  });
});

test('listing tests does not write a successful execution report', () => {
  isolatedReporter((reporter, directory) => {
    process.argv.push('--list');
    try { reporter.onEnd({ status: 'passed' }); }
    finally { process.argv.pop(); }
    assert.equal(fs.existsSync(path.join(directory, 'test-results/live/summary.json')), false);
  });
});
