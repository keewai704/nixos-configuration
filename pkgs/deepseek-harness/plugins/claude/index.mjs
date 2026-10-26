import z from "@deepseek-ai/schemastery";
import { ClaudeBridgeAdapter } from "dsh-claude-bridge";
import { modelReasoning, registerUsage, usageMetadata, watchModels } from "../shared.mjs";
import { ClaudeRuntime } from "./runtime.mjs";

export const name = "dsh-claude-agent";
export const inject = ["llm", "subprocess"];
export const Config = z.object({ executable: z.string().default("claude") });

export class ClaudeAgentAdapter extends ClaudeBridgeAdapter {
  constructor(executable, runtime) {
    super({ pathToClaudeCodeExecutable: executable });
    this.runtime = runtime;
  }

  providerInfo(provider) {
    return { id: provider, name: "Claude (Agent SDK)" };
  }

  async listModels(provider) {
    return (await this.runtime.models.read()).map((model) => ({
      provider,
      id: model.value,
      name: model.displayName,
      description: model.description,
      inputModalities: ["text"],
    }));
  }

  async resolveModel(provider, id) {
    const model = (await this.runtime.models.read()).find((candidate) => candidate.value === id || candidate.resolvedModel === id);
    return {
      provider,
      id,
      name: model?.displayName ?? id,
      inputModalities: ["text"],
      ...(model?.description ? { description: model.description } : {}),
      ...(id.includes("[1m]") ? { context: { contextWindow: 1_000_000 } } : {}),
      ...(model?.supportedEffortLevels?.length ? { reasoning: modelReasoning(model.supportedEffortLevels) } : {}),
    };
  }

  async *stream(options) {
    const models = await this.runtime.models.read();
    const model = models.find((candidate) => candidate.value === options.model || candidate.resolvedModel === options.model);
    for await (const chunk of super.stream(options)) {
      yield usageMetadata(chunk, model?.resolvedModel ?? options.model);
    }
  }
}

export async function apply(ctx, config) {
  const executable = await ctx.subprocess.resolveExecutable(config.executable ?? "claude");
  const controller = new AbortController();
  const runtime = new ClaudeRuntime(executable, controller.signal);
  watchModels(ctx, runtime.models);
  const adapter = new ClaudeAgentAdapter(executable, runtime);
  ctx.llm.registerAdapter(["claude-bridge"], adapter);
  registerUsage(ctx, "claude", { usage: () => runtime.usage() });
  ctx.effect(() => async () => {
    controller.abort();
    await adapter.dispose();
  });
}
