const fs = require('node:fs');
const path = require('node:path');

function redact(value) {
  let result = value || '';
  for (const secret of [process.env.E2E_EMAIL, process.env.E2E_PASSWORD].filter(Boolean)) {
    for (const representation of [secret, JSON.stringify(secret).slice(1, -1), encodeURIComponent(secret)]) {
      result = result.split(representation).join('[REDACTED]');
    }
  }
  return result;
}

class LiveReporter {
  constructor() { this.tests = []; this.errors = []; }
  printsToStdio() { return true; }
  onBegin(_config, suite) {
    if (process.argv.includes('--list')) {
      for (const test of suite.allTests()) console.log(test.titlePath().join(' > '));
      return;
    }
    console.log(`Running ${suite.allTests().length} deployed-service tests (credentials and recordings excluded).`);
  }
  onTestEnd(test, result) {
    const summary = { title: test.title, status: result.status,
      errors: result.errors.map(error => redact(error.message)) };
    this.tests.push(summary);
    console.log(`${summary.status}: ${summary.title}`);
    for (const error of summary.errors) console.log(error);
  }
  onError(error) { this.errors.push(redact(error.message)); }
  onEnd(result) {
    if (process.argv.includes('--list')) return;
    const file = path.join('test-results', 'live', 'summary.json');
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify({ status: result.status, tests: this.tests, errors: this.errors }, null, 2), { mode: 0o600 });
    for (const error of this.errors) console.error(error);
    console.log(`Deployed-service result: ${result.status}. Summary: ${file}`);
  }
}
module.exports = LiveReporter;
