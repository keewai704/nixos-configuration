import { stripTypeScriptTypes } from "node:module";
import { format } from "node:util";

const PREFIX = "async function __dsh_program__() {\n";
const SUFFIX = "\n}";
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor;

const logs = [];
const pending = new Map();
let nextCallId = 0;

const capture = (...values) => {
  logs.push(format(...values));
};

const programConsole = { log: capture, info: capture, warn: capture, error: capture, debug: capture };

const captureWrite = (chunk) => {
  logs.push(String(chunk).replace(/\n$/, ""));
  return true;
};
process.stdout.write = captureWrite;
process.stderr.write = captureWrite;

class ToolCallError extends Error {
  constructor(toolName, message) {
    super(message);
    this.name = "ToolCallError";
    this.toolName = toolName;
  }
}

const finish = (result) => {
  process.send({ type: "done", logs, ...result }, () => process.exit(0));
};

const callTool = (name, args) =>
  new Promise((resolve, reject) => {
    const id = ++nextCallId;
    pending.set(id, { name, resolve, reject });
    process.send({ type: "call", id, name, args });
  });

const bindTools = (names) =>
  Object.freeze(Object.fromEntries(names.map((name) => [name, (args = {}) => callTool(name, args)])));

const compile = (code) => {
  const stripped = stripTypeScriptTypes(PREFIX + code + SUFFIX);
  return stripped.slice(PREFIX.length, stripped.length - SUFFIX.length);
};

const run = async ({ code, names }) => {
  try {
    const program = new AsyncFunction("tools", "ToolCallError", "console", compile(code));
    const value = await program(bindTools(names), ToolCallError, programConsole);
    finish({ ok: true, json: value === undefined ? undefined : JSON.stringify(value) });
  } catch (error) {
    finish({ ok: false, message: error instanceof Error ? `${error.name}: ${error.message}` : String(error) });
  }
};

process.on("message", (message) => {
  if (message.type === "run") {
    void run(message);
    return;
  }
  if (message.type === "result") {
    const entry = pending.get(message.id);
    pending.delete(message.id);
    if (entry === undefined) return;
    if (message.ok) entry.resolve(message.value);
    else entry.reject(new ToolCallError(entry.name, message.message));
  }
});

process.on("uncaughtException", (error) => {
  finish({ ok: false, message: error instanceof Error ? `${error.name}: ${error.message}` : String(error) });
});
