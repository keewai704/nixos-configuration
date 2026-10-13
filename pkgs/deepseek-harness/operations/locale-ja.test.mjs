import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import test from 'node:test';
import { createJapaneseLocalePlugin } from './locale-ja-client.js';

const dictionaries = JSON.parse(await readFile(new URL('./locale-ja.json', import.meta.url), 'utf8'));
const expected = JSON.parse(await readFile(new URL('./ja/expected.json', import.meta.url), 'utf8'));
const sortedKeys = value => Object.keys(value).sort();
const tokens = text => [...text.matchAll(/\{\w+\}/g)].map(match => match[0]).sort();
const lineBreaks = text => [...text.matchAll(/\n+/g)].map(match => match[0].length);

const literalTerms = new Set([
  'ID', 'HTTP', 'HTML', 'JSON', 'PDF', 'Markdown', 'Bash', 'Pwsh', 'Grep', 'Glob',
  'Tab', 'TTFT', 'UTC', 'Cron', 'KB', 'K', 'M', 'px', 'v', 'ja', 'en',
  'goal', 'plan', 'feedback', 'compact', 'permission', 'export',
  'DeepSeek Harness', 'OpenAI Chat Completions', 'OpenAI Responses', 'Anthropic Messages',
  'dsh-plugin-whale-pet', 'userData/keybindings.json',
  'https://npm.example.com/', 'https://api.deepseek.com/anthropic',
  'https://gateway.example/v1', 'https://gateway.example',
  'Cursor', 'VS Code', 'VS Code Insiders', 'Windsurf', 'Zed', 'Sublime Text',
  'Xcode', 'Android Studio', 'IntelliJ IDEA', 'PyCharm', 'WebStorm', 'PhpStorm',
  'GoLand', 'Rider', 'RustRover', 'Fork', 'Sourcetree', 'GitHub Desktop', 'Tower',
  'GitKraken', 'SmartGit', 'Sublime Merge', 'Ghostty', 'Warp', 'iTerm2', 'kitty',
  'Windows Terminal', 'Git Bash', 'GNOME Terminal', 'Konsole', 'Finder',
]);

for (const [namespace, manifest] of Object.entries(expected.namespaces)) {
  test(`${namespace}: exact source keys, interpolation tokens, and line breaks`, () => {
    const dictionary = dictionaries[namespace];
    assert.ok(dictionary, `Missing namespace ${namespace}`);
    assert.deepEqual(sortedKeys(dictionary), manifest.keys);
    for (const [key, text] of Object.entries(dictionary)) {
      const location = `${namespace}:${key}`;
      assert.equal(typeof text, 'string', location);
      assert.deepEqual(tokens(text), manifest.tokens[key] ?? [], location);
      assert.deepEqual(lineBreaks(text), manifest.lineBreaks[key] ?? [], location);
      assert.ok(!/\{[^{}]*\}/.test(text.replace(/\{\w+\}/g, '')), location);
      assert.ok(!/\r|\uFFFD/.test(text), location);
      assert.ok(!/TODO|TRANSLATE|未翻訳/.test(text), location);
      if (text === '') {
        assert.ok(['chat:message.stepProcess.sharedPrefix', 'settings.account:onboardingPurposePrefix'].includes(location), location);
      }
      if (!/[\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Han}]/u.test(text)) {
        const remaining = text.replace(/\{\w+\}/g, '').replace(/[\s\p{P}\p{S}\d]/gu, '');
        assert.ok(remaining === '' || literalTerms.has(text) || literalTerms.has(remaining), `Untranslated prose at ${location}: ${text}`);
      }
    }
  });
}

test('the pack covers the complete fixture without taking existing ownership', () => {
  assert.deepEqual(sortedKeys(dictionaries), sortedKeys(expected.namespaces));
  assert.equal(Object.hasOwn(dictionaries, 'common'), false);
  assert.equal(Object.hasOwn(dictionaries, 'operations'), false);
  assert.equal(Object.keys(dictionaries).length, 55);
  assert.equal(Object.values(dictionaries).reduce((total, dictionary) => total + Object.keys(dictionary).length, 0), 2505);
});

test('locale selectors and command tokens preserve their consumer contracts', () => {
  assert.equal(dictionaries['settings.account'].onboardingArtworkLocale, 'ja');
  assert.equal(dictionaries.sidebarExcel.language, 'en');
  for (const namespace of ['schedule.catalog', 'schedule.manager']) {
    assert.equal(dictionaries[namespace]['time.locale'], 'ja');
    assert.equal(dictionaries[namespace]['cron.months'].replace('{months}', '1月'), '（1月）');
  }
  for (const command of ['goal', 'plan', 'feedback', 'compact', 'permission', 'export']) {
    assert.equal(dictionaries.command[`token.${command}`], command);
  }
});

function harness(failAt) {
  const registered = new Map([
    ['common/ja', { save: '保存' }],
    ['operations/ja', { title: 'プライバシーと運用' }],
    ['settings/en', { title: 'Settings' }],
  ]);
  const baseline = new Map(registered);
  const cleanups = [];
  const releases = [];
  let calls = 0;
  return {
    registered, baseline, cleanups, releases,
    ctx: {
      locale: {
        addLanguage() { assert.fail('The feature pack must not own the language'); },
        register(namespace, language, dictionary) {
          assert.equal(language, 'ja');
          if (calls++ === failAt) throw new Error('registration failed');
          const key = `${namespace}/${language}`;
          assert.equal(registered.has(key), false, `Duplicate ${key}`);
          registered.set(key, dictionary);
          return () => {
            assert.equal(registered.get(key), dictionary);
            releases.push(namespace);
            registered.delete(key);
          };
        },
      },
      effect(callback) { cleanups.push(callback()); },
    },
  };
}

test('factory registers and disposes every namespace and supports reload', () => {
  const runtime = harness();
  const plugin = createJapaneseLocalePlugin(dictionaries);
  assert.deepEqual(plugin.inject, ['locale']);
  plugin.apply(runtime.ctx);
  assert.equal(runtime.cleanups.length, 1);
  for (const [namespace, dictionary] of Object.entries(dictionaries)) {
    assert.equal(runtime.registered.get(`${namespace}/ja`), dictionary);
  }
  assert.equal(runtime.registered.size, runtime.baseline.size + Object.keys(dictionaries).length);
  runtime.cleanups[0]();
  runtime.cleanups[0]();
  assert.deepEqual(runtime.registered, runtime.baseline);
  assert.deepEqual(runtime.releases, Object.keys(dictionaries).reverse());
  plugin.apply(runtime.ctx);
  runtime.cleanups[1]();
  assert.deepEqual(runtime.registered, runtime.baseline);
});

test('registration failures roll back the whole feature pack', () => {
  for (const failAt of [0, 1, 25, 54]) {
    const runtime = harness(failAt);
    assert.throws(() => createJapaneseLocalePlugin(dictionaries).apply(runtime.ctx), /registration failed/);
    assert.deepEqual(runtime.registered, runtime.baseline);
    assert.deepEqual(runtime.releases, Object.keys(dictionaries).slice(0, failAt).reverse());
    assert.equal(runtime.cleanups.length, 0);
  }
});

test('the factory rejects namespaces owned by the existing operations client', () => {
  for (const namespace of ['common', 'operations']) {
    assert.throws(() => createJapaneseLocalePlugin({ [namespace]: {} }), /must not own/);
  }
});

test('fixture provenance matches the pinned upstream source', {
  skip: !process.env.DSH_LOCALE_UPSTREAM,
}, async () => {
  for (const [file, digest] of Object.entries(expected.sources)) {
    const bytes = await readFile(join(process.env.DSH_LOCALE_UPSTREAM, file));
    assert.equal(createHash('sha256').update(bytes).digest('hex'), digest, file);
  }
});
