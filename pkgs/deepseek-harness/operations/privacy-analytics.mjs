import Upstream from '@deepseek-ai/dsh-client-product-analytics';
import { makeChannelPlugin } from './privacy-channels.mjs';

class Analytics extends Upstream {
  static inject = [...Upstream.inject, 'privacyPolicy'];
  enabled() { return this.ctx.privacyPolicy.enabled('product-analytics') && super.enabled(); }
}

export default makeChannelPlugin('product-analytics', Analytics, 'enabled', true, false);
