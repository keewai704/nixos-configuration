import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { access, readFile, readdir } from "node:fs/promises";
import { dirname, join } from "node:path";

const directory = process.argv[2];
const cli = createRequire(join(directory, "@deepseek-ai/dsh/package.json"));
const bridge = createRequire(join(directory, "dsh-claude-bridge/package.json"));

for (const name of ["@deepseek-ai/cordis", "@deepseek-ai/dsh-llm"]) {
  assert.equal(
    bridge.resolve(name),
    cli.resolve(name),
    `${name} must share its module instance between DSH and the Claude bridge`,
  );
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
const { rewriteIndexChunk } = await import(
  join(directory, "rdsh-markdown-cjk/markdown-cjk-runtime.js")
);
const rewritten = rewriteIndexChunk(
  await readFile(join(assets, indexAsset), "utf8"),
  vendorAsset,
);
assert.notEqual(rewritten, null);
const baseUrl = `http://localhost/markdown-cjk/v1/${indexAsset}`;
for (const [, specifier] of rewritten.matchAll(
  /"(\/assets\/[^"\n]+|\.\/[^"\n]+\.(?:js|css))"/g,
)) {
  const pathname = new URL(specifier, baseUrl).pathname;
  if (pathname === `/markdown-cjk/v1/${vendorAsset}`) continue;
  assert.ok(
    pathname.startsWith("/assets/"),
    `${specifier} must resolve to a served asset`,
  );
  await access(join(assets, pathname.slice("/assets/".length)));
}
