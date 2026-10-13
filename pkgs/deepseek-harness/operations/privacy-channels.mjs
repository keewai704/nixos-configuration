export function makeChannelPlugin(channel, upstream, key, on, off) {
  const injection = upstream.inject ?? [];
  return {
    name: `private-${channel}`,
    Config: upstream.Config,
    inject: [...injection, 'privacyPolicy'],
    async apply(ctx, config) {
      const policy = ctx.privacyPolicy;
      let current;
      let active;
      let closing = false;
      let tail = Promise.resolve();
      function reconcile() {
        const task = tail.then(async () => {
          if (closing) return;
          const enabled = policy.enabled(channel);
          if (current && active === enabled && current.state === 2) return;
          if (current) { await current.dispose(); current = undefined; active = undefined; }
          if (closing) return;
          const next = ctx.plugin(upstream, { ...config, [key]: enabled ? on : off });
          try {
            await next;
            if (next.state !== 2) throw new Error('Privacy channel did not activate');
            current = next;
            active = enabled;
          } catch (error) { await next.dispose(); throw error; }
        });
        tail = task.catch(() => {});
        return task;
      }
      const read = () => !current || current.state !== 2 ? 'not-active' : active ? 'enabled' : 'disabled';
      ctx.effect(() => policy.attach(channel, read, reconcile));
      const interval = setInterval(() => { void reconcile().catch(error => ctx.logger.error('Privacy channel reconciliation failed', error)); }, 1000);
      interval.unref();
      ctx.effect(() => async () => {
        closing = true;
        clearInterval(interval);
        await tail;
        if (current) await current.dispose();
      });
      await reconcile();
    },
  };
}

export function makeExtensionChannelPlugin(channel, upstream) {
  return {
    name: `private-${channel}`,
    Config: upstream.Config,
    inject: [...upstream.inject, 'privacyPolicy'],
    async apply(ctx, config) {
      const policy = ctx.privacyPolicy;
      const registry = ctx.deepseekLlmApiExtensions;
      const bridge = ctx.isolate('deepseekLlmApiExtensions');
      await bridge.plugin({
        apply(child) {
          child.provide('deepseekLlmApiExtensions', {
            register(field, provider) {
              return registry.register(field, {
                async prepare(request) {
                  if (!policy.enabled(channel)) return undefined;
                  const result = await provider.prepare(request);
                  return policy.enabled(channel) ? result : undefined;
                },
              });
            },
          });
        },
      });
      const mounted = await bridge.plugin(upstream, { ...config, enabled: true });
      if (mounted.state !== 2) throw new Error('Privacy extension did not activate');
      ctx.effect(() => policy.attach(channel, () => policy.enabled(channel) ? 'enabled' : 'disabled'));
    },
  };
}
