import Upstream from '@deepseek-ai/dsh-session-telemetry-otel';
import { makeChannelPlugin } from './privacy-channels.mjs';
import { gateSessionReporter } from './privacy-otel.mjs';

const wrapper = makeChannelPlugin('session-telemetry-otel', Upstream, 'mode', 'FEEDBACK_ONLY', 'DISABLED');
export default {
  ...wrapper,
  async apply(ctx, config) {
    ctx.on('session-telemetry/record', (record, next) => {
      if (!ctx.privacyPolicy.enabled('session-telemetry-otel')) throw new Error('Session sharing is disabled');
      return next();
    });
    const otel = ctx.otel;
    const bridge = ctx.isolate('otel');
    await bridge.plugin({ apply(child) { child.provide('otel', gateSessionReporter(otel, ctx.privacyPolicy)); } });
    await bridge.plugin(wrapper, config);
  },
};
