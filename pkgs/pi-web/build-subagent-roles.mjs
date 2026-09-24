import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { basename, join, resolve } from "node:path";

const { load } = createRequire(resolve("package.json"))("js-yaml");
const source = process.argv[2];
if (!source) throw new Error("Role source directory is required");
const roles = readdirSync(source).filter((name) => name.endsWith(".md")).sort().map((name) => {
  const text = readFileSync(join(source, name), "utf8");
  const match = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/);
  if (!match) throw new Error(`Invalid role frontmatter: ${name}`);
  const data = load(match[1]);
  if (data.name !== basename(name, ".md") || typeof data.description !== "string" || !match[2].trim()) {
    throw new Error(`Invalid role definition: ${name}`);
  }
  return { name: data.name, description: data.description, systemPrompt: match[2].trim() };
});
writeFileSync("lib/subagent-role-data.json", JSON.stringify(roles, null, 2) + "\n");
