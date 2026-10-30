import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { runInNewContext } from "node:vm";

const directory = process.argv[2];
const sources = await Promise.all(
  (await fs.readdir(directory))
    .filter((name) => name.endsWith(".mjs"))
    .map((name) => fs.readFile(path.join(directory, name), "utf8")),
);
const servers = sources.filter((source) => source.includes("const threadLinkFor ="));
assert.equal(servers.length, 1, "Expected one server thread link implementation");
const source = servers[0];

function declaration(pattern) {
  const matches = [...source.matchAll(pattern)];
  assert.equal(matches.length, 1, `Expected one bundled declaration: ${pattern}`);
  return matches[0][0];
}

const declarations = [
  declaration(/^const THREAD_LINK_PROTOCOL = .*;$/gm),
  declaration(/^const V1_PREFIX = .*;$/gm),
  declaration(/^const V2_PREFIX = .*;$/gm),
  declaration(/^function threadLinkHref\(link\) \{[\s\S]*?^\}/gm),
  declaration(/^function formatThreadLink\(ref, label\) \{[\s\S]*?^\}/gm),
  declaration(/^const threadLinkFor = \(scope, threadId\) => \{[\s\S]*?^\};/gm),
];
const threadLinkFor = runInNewContext(`${declarations.join("\n")}\nthreadLinkFor`);
const environmentId = "00000000-0000-4000-8000-000000000001";
const origin = "https://orange.tail1e65cd.ts.net";

for (const threadId of ["synthetic-thread", "thread:synthetic/review?value=1"]) {
  for (const [webOrigin, prefix] of [
    [origin, "/t3"],
    ["https://synthetic.connect.example", ""],
    ["http://127.0.0.1:3773", ""],
  ]) {
    assert.equal(
      threadLinkFor({ environmentId, client: { webOrigin } }, threadId),
      `${webOrigin}${prefix}/${environmentId}/${encodeURIComponent(threadId)}`,
    );
  }
  for (const scope of [{ environmentId }, { environmentId, client: {} }]) {
    assert.equal(threadLinkFor(scope, threadId), `<t3-thread://v2/${environmentId}/${threadId}>`);
  }
}
console.log("Bundled HTTP thread links use /t3/ on orange and preserve Connect and native links (10 cases)");
