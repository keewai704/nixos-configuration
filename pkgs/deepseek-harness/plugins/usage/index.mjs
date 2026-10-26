import { Service } from "@deepseek-ai/cordis";
import { clientRequestSchema } from "@deepseek-ai/dsh-client-connection";
import z from "@deepseek-ai/schemastery";
import { homedir } from "node:os";
import { isAbsolute, join } from "node:path";
import { Worker } from "node:worker_threads";
import { normalizeLimits } from "./limits.mjs";

export const name = "dsh-subscription-usage";
export const inject = [];
export const Config = z.object({
  claudeHome: z.string().default(process.env.CLAUDE_CONFIG_DIR || join(homedir(), ".claude")),
  codexHome: z.string().default(process.env.CODEX_HOME || join(homedir(), ".codex")),
  t3Database: z.string().default(join(homedir(), ".t3", "userdata", "statev2.sqlite")),
});

export class SubscriptionUsage extends Service {
  constructor(ctx, config) {
    super(ctx, "subscriptionUsage");
    for (const path of [config.claudeHome, config.codexHome, config.t3Database].filter(Boolean)) if (!isAbsolute(path)) throw new Error("Usage paths must be absolute");
    const dshHome = process.env.DSH_HOME || join(homedir(), ".dsh");
    this.workerData = {
      stateDir: join(dshHome, "subscription-usage"),
      t3Database: config.t3Database,
      sources: [
        { id: "claude", kind: "claude", roots: [join(config.claudeHome, "projects")] },
        { id: "codex", kind: "codex", roots: [join(config.codexHome, "sessions"), join(config.codexHome, "archived_sessions")] },
        { id: "dsh", kind: "dsh", roots: [join(dshHome, "sessions")] },
      ],
    };
    this.providers = new Map();
    this.limits = new Map();
    this.pendingLimits = new Map();
    this.pending = new Map();
    this.nextId = 1;
    this.closed = false;
    ctx.effect(() => async () => {
      this.closed = true;
      this.rejectPending();
      await this.worker?.terminate();
    });
  }

  register(provider, facts) {
    if (this.providers.has(provider)) throw new Error("Subscription usage provider is already registered");
    this.providers.set(provider, facts);
    return () => { this.providers.delete(provider); this.limits.delete(provider); };
  }

  rejectPending() {
    for (const pending of this.pending.values()) pending.reject(new Error("Usage history worker is unavailable"));
    this.pending.clear();
  }

  request(operation, payload) {
    if (this.closed) return Promise.reject(new Error("Usage service has stopped"));
    if (!this.worker) {
      const worker = new Worker(new URL("./worker.mjs", import.meta.url), { workerData: this.workerData });
      this.worker = worker;
      worker.on("message", ({ id, value, error }) => {
        const pending = this.pending.get(id);
        if (!pending) return;
        this.pending.delete(id);
        if (error) pending.reject(new Error(error));
        else pending.resolve(value);
      });
      worker.on("error", () => this.rejectPending());
      worker.on("exit", () => {
        if (this.worker === worker) { this.worker = undefined; this.rejectPending(); }
      });
    }
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.worker.postMessage({ id, operation, payload });
    });
  }

  async readLimits(force = false) {
    return Promise.all(["chatgpt", "claude"].map(async (provider) => {
      const old = this.limits.get(provider);
      if (!force && old && Date.now() - Date.parse(old.checkedAt) < 300_000) return old;
      let pending = this.pendingLimits.get(provider);
      if (!pending) {
        pending = (async () => {
          let value;
          try {
            const facts = this.providers.get(provider);
            if (!facts) throw new Error("Provider is not active");
            value = normalizeLimits(provider, await facts.usage());
          } catch { value = { provider, status: "unavailable", windows: [], plan: null }; }
          const result = { ...value, checkedAt: new Date().toISOString() };
          this.limits.set(provider, result);
          return result;
        })().finally(() => this.pendingLimits.delete(provider));
        this.pendingLimits.set(provider, pending);
      }
      return pending;
    }));
  }
}

function registerTransport(connection, usage) {
  return ["summary", "limits", "prices", "save-prices"].map((operation) => {
    const method = `subscription-usage/${operation}`;
    return connection.fetch.register({
      path: `/api/${method}`, methods: ["POST"], requestBody: "buffered",
      async fetch(request) {
        if (!request.headers.get("content-type")?.startsWith("application/json")) return new Response("JSON required", { status: 415 });
        let body;
        try { body = await request.json(); }
        catch { return new Response("Invalid JSON", { status: 400 }); }
        const parsed = clientRequestSchema.safeParse(body);
        if (!parsed.success || parsed.data.method !== method) return new Response("Invalid RPC", { status: 400 });
        let result;
        try {
          request.signal.throwIfAborted();
          const payload = parsed.data.payload;
          const value = operation === "limits" ? await usage.readLimits(payload?.refresh === true) : await usage.request(operation, payload);
          result = { ok: true, value };
        } catch {
          result = { ok: false, error: { code: "usage_unavailable", message: "Usage could not be loaded. Refresh or check local history access.", details: { issues: [] } } };
        }
        return Response.json({ type: "server-response", rpcId: parsed.data.rpcId, result }, { headers: { "cache-control": "no-store" } });
      },
    });
  });
}

export function apply(ctx, config) {
  const usage = new SubscriptionUsage(ctx, config);
  ctx.inject(["connection"], (scoped) => {
    scoped.effect(() => {
      const disposers = registerTransport(scoped.connection, usage);
      return () => { for (const dispose of disposers) dispose(); };
    });
  });
}
