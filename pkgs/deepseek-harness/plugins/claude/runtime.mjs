import { homedir } from "node:os";
import { query } from "@anthropic-ai/claude-agent-sdk";
import { scrubbedParentEnv } from "@deepseek-ai/dsh-subprocess";
import { LiveCatalog } from "../shared.mjs";

export class ClaudeRuntime {
  constructor(executable, signal) {
    this.executable = executable;
    this.signal = signal;
    this.models = new LiveCatalog(() => this.control(async (session) => {
      const models = await session.supportedModels();
      if (!Array.isArray(models) || !models.length || models.some((model) =>
        typeof model.value !== "string" || !model.value || typeof model.displayName !== "string")) {
        throw new Error("Claude SDK returned an invalid model catalog");
      }
      return models;
    }));
  }

  async control(operation) {
    const controller = new AbortController();
    const signal = AbortSignal.any([this.signal, AbortSignal.timeout(20_000)]);
    const abort = () => controller.abort(signal.reason);
    signal.throwIfAborted();
    signal.addEventListener("abort", abort, { once: true });
    const env = scrubbedParentEnv();
    for (const key of ["ANTHROPIC_BASE_URL", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX"]) delete env[key];
    const session = query({
      prompt: {
        async *[Symbol.asyncIterator]() {
          await new Promise((resolve) => {
            if (controller.signal.aborted) resolve();
            else controller.signal.addEventListener("abort", resolve, { once: true });
          });
        },
      },
      options: {
        pathToClaudeCodeExecutable: this.executable,
        cwd: homedir(),
        env,
        settingSources: [],
        strictMcpConfig: true,
        mcpServers: {},
        tools: [],
        persistSession: false,
        abortController: controller,
      },
    });
    try {
      return await operation(session);
    } finally {
      signal.removeEventListener("abort", abort);
      controller.abort();
      session.close();
    }
  }

  async usage() {
    return this.control(async (session) => {
      const account = await session.accountInfo();
      const usage = await session.usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET({ skipBehaviors: true });
      return {
        plan: account.subscriptionType ?? null,
        rate_limits_available: usage.rate_limits_available,
        rate_limits: usage.rate_limits,
      };
    });
  }
}
