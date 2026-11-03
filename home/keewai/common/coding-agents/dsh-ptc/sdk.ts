export const RUN_CODE_NAME = "run_code";

export const RUN_CODE_DESCRIPTION =
  "Execute a TypeScript program against the available tools. Takes two required arguments: `code`, the BODY of an async function (erasable syntax only; top-level `await` and `return` work), and `description`, a short summary of what the program does. Call tools as `await tools.name(args)` per the declarations in the system prompt. Only what you print or return is program output — curate it. Image-bearing subtool results are attached after the run.";

const EXECUTION_INSTRUCTIONS =
  "The program is the body of an async TypeScript function; only erasable syntax is accepted, with no enum or namespaces. Type annotations are advisory. Top-level await and return are supported. Emit output with console.log(...) or return a lossless JSON value. Only printed values and the returned value become program output. Each call runs in a fresh Node process. Node APIs are available through await import(...). Relative paths use the supplied working directory; process.env starts empty. Direct filesystem access follows the user's own permissions; no sandbox policy applies.";

export const RUN_CODE_TOOL_DESCRIPTION = `${RUN_CODE_DESCRIPTION} ${EXECUTION_INSTRUCTIONS} Each program starts in the Session's current directory. Running programs keep their initial directory.`;

export const RUN_CODE_CODE_DESCRIPTION =
  "The program: the body of an async TypeScript function.";

export const RUN_CODE_DESCRIPTION_PARAM_DESCRIPTION =
  'Clear, concise description of what this program does in active voice, 5-10 words (shown in the UI). Examples: "Count TODO markers across packages"; "Read failing test and its fixture"; "Rename config key in every cordis.yml".';

export const RUN_CODE_TIMEOUT_DEFAULT_MS = 120000;
export const RUN_CODE_TIMEOUT_MAX_MS = 600000;

export const RUN_CODE_TIMEOUT_DESCRIPTION = `Positive elapsed-time budget in milliseconds, including nested tool and approval waits. Default ${RUN_CODE_TIMEOUT_DEFAULT_MS}; capped at ${RUN_CODE_TIMEOUT_MAX_MS}. Zero does not disable the deadline.`;

export interface SdkToolSchema {
  readonly name: string;
  readonly description?: string;
  readonly parameters: unknown;
  readonly output?: unknown;
}

type JsonSchema = {
  readonly type?: string | readonly string[];
  readonly properties?: Readonly<Record<string, JsonSchema>>;
  readonly required?: readonly string[];
  readonly items?: JsonSchema;
  readonly enum?: readonly unknown[];
  readonly const?: unknown;
  readonly anyOf?: readonly JsonSchema[];
  readonly oneOf?: readonly JsonSchema[];
  readonly description?: string;
};

const IDENTIFIER = /^[A-Za-z_$][A-Za-z0-9_$]*$/;

const renderKey = (name: string): string => (IDENTIFIER.test(name) ? name : JSON.stringify(name));

const pad = (indent: number): string => "  ".repeat(indent);

const docLines = (description: unknown, indent: number): string[] => {
  if (typeof description !== "string" || description.trim() === "") return [];
  const lines = description.trim().split(/\r?\n/).map((line) => line.replace(/\*\//g, "*\\/"));
  if (lines.length === 1) return [`${pad(indent)}/** ${lines[0]} */`];
  return [`${pad(indent)}/**`, ...lines.map((line) => `${pad(indent)} * ${line}`), `${pad(indent)} */`];
};

const union = (members: readonly string[]): string => [...new Set(members)].join(" | ") || "never";

const renderSchema = (schema: JsonSchema | undefined, indent: number): string => {
  if (schema === undefined || typeof schema !== "object") return "unknown";
  if (schema.const !== undefined) return JSON.stringify(schema.const);
  if (Array.isArray(schema.enum)) return union(schema.enum.map((value) => JSON.stringify(value)));
  if (Array.isArray(schema.anyOf)) return union(schema.anyOf.map((member) => renderSchema(member, indent)));
  if (Array.isArray(schema.oneOf)) return union(schema.oneOf.map((member) => renderSchema(member, indent)));
  const types = Array.isArray(schema.type) ? schema.type : schema.type === undefined ? [] : [schema.type];
  if (types.length === 0) return schema.properties === undefined ? "unknown" : renderObject(schema, indent);
  return union(types.map((type) => renderType(type, schema, indent)));
};

const renderType = (type: string, schema: JsonSchema, indent: number): string => {
  switch (type) {
    case "string": return "string";
    case "number":
    case "integer": return "number";
    case "boolean": return "boolean";
    case "null": return "null";
    case "array": {
      const item = renderSchema(schema.items, indent);
      return /[|\s]/.test(item) ? `(${item})[]` : `${item}[]`;
    }
    case "object": return renderObject(schema, indent);
    default: return "unknown";
  }
};

const renderObject = (schema: JsonSchema, indent: number): string => {
  const required = new Set(schema.required ?? []);
  const entries = Object.entries(schema.properties ?? {});
  if (entries.length === 0) return "Record<string, unknown>";
  const members = entries.flatMap(([name, property]) => [
    ...docLines(property.description, indent + 1),
    `${pad(indent + 1)}${renderKey(name)}${required.has(name) ? "" : "?"}: ${renderSchema(property, indent + 1)};`,
  ]);
  return `{\n${members.join("\n")}\n${pad(indent)}}`;
};

const renderBashExample = (schemas: readonly SdkToolSchema[]): string => {
  const bash = schemas.find((schema) => schema.name === "bash");
  if (bash === undefined) return "";
  const parameters = bash.parameters as JsonSchema;
  if (parameters.type !== "object") return "";
  const required = parameters.required ?? [];
  if (required.some((name) => name !== "command" && name !== "description")) return "";
  if (parameters.properties?.command?.type !== "string") return "";
  const needsDescription = required.includes("description");
  if (needsDescription && parameters.properties?.description?.type !== "string") return "";
  const description = needsDescription ? "description: 'Show current directory', " : "";
  const program = `return await tools.bash({ ${description}command: 'pwd' })`;
  return ` When no separate \`bash\` schema is supplied, invoke a declared \`bash\` binding inside \`run_code\`:\n\n\`run_code({ code: "${program}", description: "Show current directory" })\``;
};

export const renderToolsSdk = (schemas: readonly SdkToolSchema[]): string => {
  const sorted = [...schemas].sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  const argsMembers: string[] = [];
  const outputMembers: string[] = [];
  for (const schema of sorted) {
    argsMembers.push(...docLines(schema.description, 1));
    argsMembers.push(`${pad(1)}${renderKey(schema.name)}: ${renderSchema(schema.parameters as JsonSchema, 1)};`);
    outputMembers.push(`${pad(1)}${renderKey(schema.name)}: ${schema.output === undefined ? "string" : renderSchema(schema.output as JsonSchema, 1)};`);
  }
  const argsMap = `interface ToolArgsMap {${argsMembers.length > 0 ? `\n${argsMembers.join("\n")}\n` : ""}}`;
  const outputMap = `interface ToolOutputMap {${outputMembers.length > 0 ? `\n${outputMembers.join("\n")}\n` : ""}}`;
  const declaration = [
    argsMap,
    outputMap,
    "type ToolName = keyof ToolOutputMap",
    ["declare class ToolCallError extends Error {", '  readonly name: "ToolCallError";', "  readonly toolName: ToolName;", "}"].join("\n"),
    ["declare const tools: {", "  [K in ToolName]: (args: ToolArgsMap[K]) => Promise<ToolOutputMap[K]>;", "}"].join("\n"),
  ].join("\n\n");
  const jsonValue = "type JsonValue = null | boolean | number | string | JsonValue[] | { [key: string]: JsonValue }";
  const instructions = `## Writing code for run_code

\`run_code\` takes two required arguments: \`code\`, the body of an async TypeScript function (erasable syntax only — no \`enum\` or namespaces; type annotations are advisory, the code runs type-stripped), and \`description\`, a short summary of what the program does. The declarations below are SDK bindings for this program. A declaration does not make its name a directly callable tool; only names supplied as separate tool schemas may be called directly.`;
  const programInstructions = `Inside the program:

- Call tools as \`await tools.name(args)\` — quoted access for exotic names: \`tools["my-tool"](args)\`. Every call resolves to the tool's typed canonical JSON value. Tool arguments must be lossless JSON.
- A FAILED tool call rejects with \`ToolCallError\`, whose \`toolName\` identifies the failed tool and whose \`message\` is human-readable — \`try/catch\` it to handle and continue.
- Independent read-only calls MAY overlap under \`Promise.all\` (safe calls run concurrently; mutating calls run alone, in submission order). Sequence dependent work with \`await\`.
- Emit results with \`return\` and/or \`console.log(...)\`. Only what you print or return is program output. A successful tool result containing an image is attached after the run so you can inspect it on the next step; every other intermediate result stays out of the conversation, so extract just what you need.

Program-only SDK bindings:`;
  return `${instructions}${renderBashExample(sorted)}\n\n${programInstructions}\n\n\`\`\`ts\n${jsonValue}\n\n${declaration}\n\`\`\``;
};
