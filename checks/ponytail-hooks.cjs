// Exercise the packaged Codex hooks with isolated state and configuration.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = process.argv[2];
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'ponytail-hooks-'));
const state = path.join(temp, 'state', '.ponytail-active');
const env = {
  ...process.env,
  PLUGIN_DATA: path.dirname(state),
  CLAUDE_CONFIG_DIR: path.join(temp, 'claude'),
  XDG_CONFIG_HOME: path.join(temp, 'config'),
};
delete env.PONYTAIL_DEFAULT_MODE;
delete env.COPILOT_PLUGIN_DATA;
delete env.CLAUDE_PLUGIN_ROOT;
delete env.QODER_SESSION_ID;

function hook(name, input = {}) {
  const result = spawnSync(process.execPath, [path.join(root, 'hooks', `ponytail-${name}.js`)], {
    env,
    input: JSON.stringify(input),
    encoding: 'utf8',
    timeout: 5000,
  });
  assert.equal(result.status, 0, result.error?.message || result.stderr);
  return result.stdout ? JSON.parse(result.stdout) : {};
}

try {
  const start = hook('activate');
  assert.equal(start.systemMessage, 'PONYTAIL:FULL');
  assert.equal(start.hookSpecificOutput.hookEventName, 'SessionStart');
  const context = start.hookSpecificOutput.additionalContext;
  assert(context.includes('/etc/codex/skills/ponytail/SKILL.md'));
  assert(context.length < 600, 'The lifecycle hook must not inject the full skill');

  for (const mode of ['lite', 'full', 'ultra']) {
    const change = hook('mode-tracker', { prompt: `/ponytail ${mode}` });
    assert.equal(change.systemMessage, `PONYTAIL:${mode.toUpperCase()}`);
    assert.equal(fs.readFileSync(state, 'utf8'), mode);
  }
  assert.deepEqual(hook('mode-tracker', { prompt: 'Explain this photograph.' }), {});
  assert.equal(fs.readFileSync(state, 'utf8'), 'ultra');
  hook('mode-tracker', { prompt: 'Add a normal mode toggle to the UI.' });
  assert.equal(fs.readFileSync(state, 'utf8'), 'ultra');

  for (const prompt of ['/ponytail off', 'stop ponytail', 'normal mode']) {
    hook('mode-tracker', { prompt: '/ponytail full' });
    assert.equal(hook('mode-tracker', { prompt }).systemMessage, 'PONYTAIL:OFF');
    assert(!fs.existsSync(state));
  }

  hook('mode-tracker', { prompt: '/ponytail default lite' });
  assert.equal(hook('activate').systemMessage, 'PONYTAIL:LITE');
  hook('mode-tracker', { prompt: '/ponytail default off' });
  const off = hook('activate');
  assert.equal(off.systemMessage, 'PONYTAIL:OFF');
  assert.equal(off.hookSpecificOutput, undefined);
  assert(!fs.existsSync(state));
  console.log('Packaged Ponytail lifecycle, mode changes, and compact context: PASS');
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
