import { writeFileSync } from "node:fs";
import { createRequire } from "node:module";

if (!process.argv[2]) throw new Error("The pinned SDK esbuild path is required");
const { buildSync } = createRequire(import.meta.url)(process.argv[2]);
buildSync({
  entryPoints: ["lib/subagent-cli-extension.ts"],
  outfile: "pi-web-native-subagents/subagent-cli-extension.js",
  bundle: true,
  platform: "node",
  format: "esm",
  packages: "external",
});
writeFileSync("pi-web-native-subagents/package.json", JSON.stringify({
  name: "pi-web-native-subagents",
  type: "module",
  private: true,
}, null, 2) + "\n");
