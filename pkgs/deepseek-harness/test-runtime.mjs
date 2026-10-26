import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { join } from "node:path";

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
