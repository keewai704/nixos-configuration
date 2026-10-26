export class LiveCatalog {
  constructor(load, ttlMs = 30_000) {
    this.load = load;
    this.ttlMs = ttlMs;
  }

  async read() {
    if (this.value && Date.now() < this.expiresAt) return this.value;
    this.pending ??= this.load().then((value) => {
      this.value = value;
      this.expiresAt = Date.now() + this.ttlMs;
      return value;
    }).finally(() => { this.pending = undefined; });
    return this.pending;
  }
}

export function usageMetadata(chunk, model, speed = "standard") {
  if (chunk.type !== "finish") return chunk;
  return {
    ...chunk,
    replayState: {
      ...chunk.replayState,
      response: {
        ...chunk.replayState?.response,
        subscriptionUsage: { model, speed },
      },
    },
  };
}

export function registerUsage(ctx, provider, facts) {
  ctx.inject(["subscriptionUsage"], (scoped) => {
    scoped.effect(() => scoped.subscriptionUsage.register(provider, facts));
  });
}

export function watchModels(ctx, catalog) {
  ctx.effect(() => {
    const timer = setInterval(async () => {
      const previous = JSON.stringify(catalog.value);
      try {
        const current = JSON.stringify(await catalog.read());
        if (previous !== current) ctx.emit("llm/adapters-updated");
      } catch { ctx.logger.warn("Subscription model catalog could not be refreshed"); }
    }, 300_000);
    timer.unref();
    return () => clearInterval(timer);
  });
}

export function modelReasoning(efforts, defaultEffort) {
  if (!efforts?.length) return undefined;
  return {
    efforts: efforts.map((effort) => ({ id: effort, name: effort })),
    ...(defaultEffort ? { defaultEffort } : {}),
  };
}
