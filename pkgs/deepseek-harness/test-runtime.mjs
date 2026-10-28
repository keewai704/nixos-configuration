import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { access, readFile, readdir } from "node:fs/promises";
import { dirname, join } from "node:path";

const directory = process.argv[2];
const cli = createRequire(join(directory, "@deepseek-ai/dsh/package.json"));
const dshVersion = cli("./package.json").version;
for (const plugin of [
  "dsh-claude-bridge",
  "dsh-codex-native",
  "dsh-claude-agent",
  "dsh-chatgpt-subscription",
  "dsh-subscription-usage",
  "dsh-history-window",
  "dsh-restart-recovery",
]) {
  const require = createRequire(join(directory, plugin, "package.json"));
  for (const name of ["@deepseek-ai/cordis", "@deepseek-ai/dsh-llm"]) {
    assert.equal(
      require.resolve(name),
      cli.resolve(name),
      `${name} must share its module instance between DSH and ${plugin}`,
    );
  }
}

for (const path of [
  "dsh-claude-agent/index.mjs",
  "dsh-chatgpt-subscription/index.mjs",
  "dsh-subscription-usage/index.mjs",
  "dsh-history-window/index.mjs",
  "dsh-restart-recovery/index.mjs",
]) {
  const plugin = await import(join(directory, path));
  assert.equal(typeof plugin.apply, "function");
}

const codex = createRequire(join(directory, "dsh-codex-native/package.json"));
const { CODEX_APP_SERVER_VERSION } = await import(
  join(directory, "dsh-codex-native/lib/index.js")
);
const codexManifest = JSON.parse(
  await readFile(codex.resolve("@openai/codex/package.json"), "utf8"),
);
assert.equal(codexManifest.version, CODEX_APP_SERVER_VERSION);
const pluginManifest = JSON.parse(
  await readFile(join(directory, "dsh-codex-native/package.json"), "utf8"),
);
for (const name of Object.keys(pluginManifest.peerDependencies).filter((name) =>
  name.startsWith("@deepseek-ai/dsh-"),
)) {
  assert.equal(codex.resolve(name), cli.resolve(name));
  const peer = JSON.parse(
    await readFile(codex.resolve(`${name}/package.json`), "utf8"),
  );
  assert.equal(peer.version, dshVersion);
}

const assets = join(
  dirname(cli.resolve("@deepseek-ai/dsh-web-frontend/package.json")),
  "dist/assets",
);
const files = await readdir(assets);
const indexAsset = files.find((file) => /^index-[\w-]+\.js$/.test(file));
const vendorAsset = files.find((file) => /^vendor-[\w-]+\.js$/.test(file));
assert.ok(indexAsset);
assert.ok(vendorAsset);
const { rewriteIndexChunk, rewriteIndexHtml } = await import(
  join(directory, "rdsh-markdown-cjk/markdown-cjk-runtime.js")
);
const rewritten = rewriteIndexChunk(
  await readFile(join(assets, indexAsset), "utf8"),
  vendorAsset,
);
assert.notEqual(rewritten, null);
for (const prefix of ["/", "/dsh/"]) {
  const baseUrl = `https://localhost${prefix}markdown-cjk/v1/${indexAsset}`;
  for (const [, specifier] of rewritten.matchAll(
    /"((?:\/assets\/|(?:\.\.?\/)+)[^"\n]+\.(?:js|css))"/g,
  )) {
    const pathname = new URL(specifier, baseUrl).pathname;
    if (pathname === `${prefix}markdown-cjk/v1/${vendorAsset}`) continue;
    assert.ok(
      pathname.startsWith(`${prefix}assets/`),
      `${specifier} must resolve to a served asset under ${prefix}`,
    );
    await access(join(assets, pathname.slice(`${prefix}assets/`.length)));
  }
  const html = rewriteIndexHtml(
    await readFile(join(assets, "../index.html"), "utf8"),
    indexAsset,
    vendorAsset,
  );
  for (const asset of [indexAsset, vendorAsset]) {
    assert.ok(html.includes(`./markdown-cjk/v1/${asset}`));
  }
}
