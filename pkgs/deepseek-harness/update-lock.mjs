import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const [release, bridge, sdk] = process.argv.slice(2, 5).map((path) =>
  JSON.parse(readFileSync(path, "utf8")),
);
const destination = resolve(process.argv[5] ?? "pkgs/deepseek-harness");
const temporary = mkdtempSync(join(tmpdir(), "deepseek-harness-lock-"));
const manifest = {
  name: "deepseek-harness",
  version: release.version,
  private: true,
  dependencies: {
    "@deepseek-ai/dsh": release.version,
    "@deepseek-ai/dsh-llm": release.version,
    "dsh-claude-bridge": bridge.version,
    "@anthropic-ai/claude-agent-sdk": sdk.version,
  },
  overrides: {
    "dsh-claude-bridge": {
      "@anthropic-ai/claude-agent-sdk": "$@anthropic-ai/claude-agent-sdk",
      "@deepseek-ai/dsh-llm": "$@deepseek-ai/dsh-llm",
    },
  },
};
const json = JSON.stringify(manifest, null, 2) + "\n";
writeFileSync(join(temporary, "package.json"), json);
execFileSync(
  "npm",
  ["install", "--package-lock-only", "--ignore-scripts", "--no-audit", "--no-fund"],
  { cwd: temporary, stdio: "inherit" },
);
const lock = join(temporary, "package-lock.json");
const hash = execFileSync("prefetch-npm-deps", [lock], {
  encoding: "utf8",
  stdio: ["ignore", "pipe", "inherit"],
}).trim();
writeFileSync(join(destination, "package.json"), json);
writeFileSync(join(destination, "package-lock.json"), readFileSync(lock));
writeFileSync(join(destination, "npm-deps-hash"), hash + "\n");
