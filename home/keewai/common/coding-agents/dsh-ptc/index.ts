import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { AgentToolResult, ExtensionAPI, ExtensionToolContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import {
  RUN_CODE_CODE_DESCRIPTION,
  RUN_CODE_DESCRIPTION_PARAM_DESCRIPTION,
  RUN_CODE_NAME,
  RUN_CODE_TIMEOUT_DEFAULT_MS,
  RUN_CODE_TIMEOUT_DESCRIPTION,
  RUN_CODE_TIMEOUT_MAX_MS,
  RUN_CODE_TOOL_DESCRIPTION,
  renderToolsSdk,
} from "./sdk.ts";

const RUNNER = join(dirname(fileURLToPath(import.meta.url)), "program-runner.mjs");
const MAX_OUTPUT_CHARS = 50_000;

const runCodeParameters = Type.Object({
  code: Type.String({ description: RUN_CODE_CODE_DESCRIPTION }),
  description: Type.String({ description: RUN_CODE_DESCRIPTION_PARAM_DESCRIPTION }),
  timeoutMs: Type.Optional(Type.Number({ description: RUN_CODE_TIMEOUT_DESCRIPTION })),
});

interface RunCodeParams {
  code: string;
  description: string;
  timeoutMs?: number;
}

type ResultContent = AgentToolResult<RunCodeDetails>["content"][number];

interface ContentBlock {
  type: string;
  text?: string;
  data?: string;
  mimeType?: string;
}

interface RunCodeDetails {
  description: string;
  timeoutMs: number;
  durationMs: number;
}

type ProgramMessage =
  | { type: "call"; id: number; name: string; args: unknown }
  | { type: "done"; ok: boolean; logs: string[]; json?: string; message?: string };

interface Outcome {
  ok: boolean;
  logs: string[];
  json?: string;
  message?: string;
}

const timeoutFor = (timeoutMs: number | undefined): number => {
  if (timeoutMs === undefined || !Number.isFinite(timeoutMs) || timeoutMs <= 0) return RUN_CODE_TIMEOUT_DEFAULT_MS;
  return Math.min(Math.floor(timeoutMs), RUN_CODE_TIMEOUT_MAX_MS);
};

const textOf = (content: readonly ContentBlock[]): string =>
  content
    .filter((block) => block.type === "text")
    .map((block) => block.text ?? "")
    .join("\n");

const truncate = (text: string): string =>
  text.length <= MAX_OUTPUT_CHARS
    ? text
    : `${text.slice(0, MAX_OUTPUT_CHARS)}\n[output truncated: ${text.length - MAX_OUTPUT_CHARS} characters omitted]`;

const runProgram = (
  pi: ExtensionAPI,
  params: RunCodeParams,
  signal: AbortSignal | undefined,
  ctx: ExtensionToolContext,
) =>
  new Promise<AgentToolResult<RunCodeDetails>>((resolve) => {
    const timeoutMs = timeoutFor(params.timeoutMs);
    const started = Date.now();
    const tools = new Map(ctx.tools.map((tool) => [tool.name, tool]));
    const names = pi.getActiveTools().filter((name) => name !== RUN_CODE_NAME && tools.has(name));
    const readOnly = new Set(pi.getAllTools().filter((tool) => tool.annotations?.readOnlyHint === true).map((tool) => tool.name));
    const images: ResultContent[] = [];
    let queue: Promise<void> = Promise.resolve();
    let settled = false;
    let stderr = "";

    const child = spawn(process.execPath, ["--disable-warning=ExperimentalWarning", RUNNER], {
      cwd: ctx.cwd,
      env: {},
      stdio: ["ignore", "pipe", "pipe", "ipc"],
    });

    const finish = (outcome: Outcome) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      signal?.removeEventListener("abort", onAbort);
      if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
      const output = [...outcome.logs];
      if (!outcome.ok) output.push(`Program failed: ${outcome.message}`);
      else if (outcome.json !== undefined) output.push(outcome.json);
      resolve({
        content: [{ type: "text", text: truncate(output.join("\n")) || "(no output)" }, ...images],
        details: { description: params.description, timeoutMs, durationMs: Date.now() - started },
        isError: !outcome.ok,
      });
    };

    const timer = setTimeout(
      () => finish({ ok: false, logs: [], message: `timed out after ${timeoutMs} ms` }),
      timeoutMs,
    );
    const onAbort = () => finish({ ok: false, logs: [], message: "aborted" });
    if (signal?.aborted) {
      onAbort();
      return;
    }
    signal?.addEventListener("abort", onAbort, { once: true });

    const reply = (id: number, ok: boolean, value: unknown) => {
      if (child.connected) child.send({ type: "result", id, ok, ...(ok ? { value } : { message: String(value) }) });
    };

    const invoke = async ({ id, name, args }: { id: number; name: string; args: unknown }) => {
      if (!names.includes(name)) {
        reply(id, false, `${name} is not available to programs`);
        return;
      }
      try {
        const outcome = await ctx.executeTool(name, args, { signal });
        const content = outcome.result.content as ContentBlock[];
        if (outcome.isError) {
          reply(id, false, textOf(content) || `${name} failed`);
          return;
        }
        images.push(...(content.filter((block) => block.type === "image") as ResultContent[]));
        reply(id, true, outcome.result.structuredContent ?? textOf(content));
      } catch (error) {
        reply(id, false, error instanceof Error ? error.message : String(error));
      }
    };

    child.stdout?.resume();
    child.stderr?.on("data", (chunk: Buffer) => {
      stderr = `${stderr}${chunk.toString()}`.slice(-4000);
    });
    child.on("error", (error) => finish({ ok: false, logs: [], message: error.message }));
    child.on("exit", (code, signalName) =>
      finish({
        ok: false,
        logs: [],
        message: `program process ended before completing (${signalName ?? `exit ${code}`})${stderr ? `: ${stderr.trim()}` : ""}`,
      }),
    );
    child.on("message", (message: ProgramMessage) => {
      if (message.type === "done") {
        finish({ ok: message.ok, logs: message.logs, json: message.json, message: message.message });
        return;
      }
      const parallel = tools.get(message.name)?.executionMode === "parallel" || readOnly.has(message.name);
      if (parallel) void invoke(message);
      else queue = queue.then(() => invoke(message));
    });
    child.send({ type: "run", code: params.code, names });
  });

export default function (pi: ExtensionAPI) {
  const outputSchemas = new Map<string, unknown>();

  pi.registerTool({
    name: RUN_CODE_NAME,
    label: "run_code",
    description: RUN_CODE_TOOL_DESCRIPTION,
    promptSnippet: "Run a TypeScript program that calls the available tools as tools.name(args)",
    parameters: runCodeParameters,
    exposure: "direct",
    executionMode: "sequential",
    prepareLoadout: (loadout) => {
      for (const tool of loadout.registered) outputSchemas.set(tool.name, tool.outputSchema);
      return {
        hiddenDeclarations: loadout.declared.map((tool) => tool.name).filter((name) => name !== RUN_CODE_NAME),
      };
    },
    execute: (_toolCallId, params, signal, _onUpdate, ctx) => runProgram(pi, params, signal, ctx),
  });

  pi.on("before_agent_start", (event) => {
    const active = new Set(pi.getActiveTools());
    const schemas = pi
      .getAllTools()
      .filter((tool) => tool.name !== RUN_CODE_NAME && active.has(tool.name))
      .map((tool) => ({
        name: tool.name,
        description: tool.description,
        parameters: tool.parameters,
        output: outputSchemas.get(tool.name),
      }));
    event.systemPromptOptions.sections.tools_sdk = renderToolsSdk(schemas);
  });
}
