import z from "@deepseek-ai/schemastery";
import { DshCodexAdapter, CodexAppServerRunner } from "dsh-codex-native";
import { LiveCatalog, registerUsage, usageMetadata, watchModels } from "../shared.mjs";
import { withAppServer } from "./rpc.mjs";

export const name = "dsh-chatgpt-subscription";
export const inject = ["llm", "subprocess"];
export const Config = z.object({ executable: z.string().default("codex") });

export async function readModels(client) {
  const models = [];
  const cursors = new Set();
  let cursor = null;
  do {
    const page = await client.request("model/list", { cursor, limit: 100, includeHidden: false });
    if (!Array.isArray(page.data)) throw new Error("Codex returned an invalid model catalog");
    for (const model of page.data) {
      if (typeof model.id !== "string" || !model.id || typeof model.displayName !== "string") {
        throw new Error("Codex returned an invalid model");
      }
      if (model.hidden) continue;
      models.push({
        id: model.id,
        name: model.displayName,
        description: model.description,
        inputModalities: Array.isArray(model.inputModalities)
          ? model.inputModalities.filter((value) => value === "text" || value === "image")
          : ["text"],
        reasoningEfforts: (model.supportedReasoningEfforts ?? []).map((effort) => effort.reasoningEffort),
        defaultReasoningEffort: model.defaultReasoningEffort,
        ...(Number.isSafeInteger(model.contextWindow) && model.contextWindow > 0 ? { contextWindow: model.contextWindow } : {}),
      });
    }
    cursor = page.nextCursor ?? null;
    if (cursor !== null && (typeof cursor !== "string" || cursors.has(cursor))) throw new Error("Codex model pagination did not advance");
    cursors.add(cursor);
  } while (cursor !== null);
  if (!models.length) throw new Error("The authenticated Codex account returned no available models");
  return models;
}

export class ChatGPTAdapter extends DshCodexAdapter {
  constructor(options, catalog) {
    super(options);
    this.catalog = catalog;
  }

  async listModels(provider) {
    this.options.models = (await this.catalog.read()).models;
    return super.listModels(provider);
  }

  async resolveModel(provider, model, signal) {
    this.options.models = (await this.catalog.read()).models;
    return super.resolveModel(provider, model, signal);
  }

  async *stream(options) {
    const facts = await this.catalog.read();
    this.options.models = facts.models;
    for await (const chunk of super.stream(options)) yield usageMetadata(chunk, options.model, facts.speed);
  }
}

export async function apply(ctx, config) {
  const executable = await ctx.subprocess.resolveExecutable(config.executable ?? "codex");
  const controller = new AbortController();
  const control = (operation) => withAppServer(ctx, executable, controller.signal, operation);
  const catalog = new LiveCatalog(() => control(async (client) => {
    const models = await readModels(client);
    const configuration = await client.request("config/read", { includeLayers: false });
    const tier = configuration.config?.service_tier;
    return { models, speed: tier === "priority" || tier === "fast" ? "fast" : tier === "ultrafast" ? "ultrafast" : "standard" };
  }));
  watchModels(ctx, catalog);
  const runner = new CodexAppServerRunner({
    timeoutMs: 0,
    disposeGraceMs: 3_000,
    maxJsonRpcLineBytes: 8 * 1024 * 1024,
    maxStderrBytes: 65_536,
    env: {},
    skillsMode: "dsh",
    skillsMaxContextTokens: 10_000,
    spawn: (spec) => ctx.subprocess.spawn({ ...spec, argv: [executable, "app-server", ...spec.argv.slice(4)] }),
  });
  const adapter = new ChatGPTAdapter({
    provider: "codex-local",
    displayName: "ChatGPT (subscription)",
    modelProvider: "openai",
    models: [],
    maxRetries: 1,
    maxRequestImageBytes: 16 * 1024 * 1024,
    maxCachedSessions: 8,
    sessionIdleTimeoutMs: 600_000,
    onCleanupError: () => ctx.logger.warn("ChatGPT session cleanup failed"),
    resolveAttachments: () => ctx.get("attachments"),
    runner,
  }, catalog);
  ctx.llm.registerAdapter(["codex-local"], adapter);
  ctx.on("session/disposed", (session) => adapter.disposeSession(String(session.id)));
  registerUsage(ctx, "chatgpt", {
    usage: () => control(async (client, account) => {
      const response = await client.request("account/rateLimits/read");
      return {
        plan: account.planType ?? null,
        rateLimits: response.rateLimits,
        rateLimitsByLimitId: response.rateLimitsByLimitId,
        resetCredits: response.rateLimitResetCredits?.availableCount ?? null,
      };
    }),
  });
  ctx.effect(() => async () => {
    controller.abort();
    await adapter.dispose();
  });
}
