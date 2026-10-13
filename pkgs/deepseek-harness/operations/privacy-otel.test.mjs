import test from 'node:test';
import assert from 'node:assert/strict';
import { gateSessionReporter } from './privacy-otel.mjs';

test('disabled consent withholds new records and shutdown discards queued exports', async () => {
  const events = [];
  let enabled = false;
  const provider = { reportSessionLog: () => events.push('report'), stopPending: () => events.push('stop'), shutdown: async () => events.push('shutdown') };
  const reporter = gateSessionReporter({ createSessionLogReporter: () => provider }, { enabled: () => enabled }).createSessionLogReporter({});
  reporter.reportSessionLog({});
  assert.deepEqual(events, ['stop']);
  enabled = true;
  reporter.reportSessionLog({});
  enabled = false;
  await reporter.shutdown();
  assert.deepEqual(events, ['stop', 'report', 'stop', 'shutdown']);
});

test('transport header gate rechecks cross-process consent before starting queued exports', async () => {
  let options;
  let enabled = true;
  const ready = Promise.withResolvers();
  const original = { exporter: { url: 'https://example.invalid', headers: () => ready.promise } };
  gateSessionReporter({ createSessionLogReporter(input) {
    options = input;
    return { reportSessionLog() {}, stopPending() {}, shutdown: async () => {} };
  } }, { enabled: () => enabled }).createSessionLogReporter(original);
  const pending = options.exporter.headers();
  enabled = false;
  ready.resolve({ authorization: 'fixture-only' });
  await assert.rejects(pending, /disabled/);
  await assert.rejects(options.exporter.headers(), /disabled/);
  assert.equal(typeof original.exporter.headers, 'function');
});
