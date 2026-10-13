import * as upstream from '@deepseek-ai/dsh-session-log-deepseek';
import { makeExtensionChannelPlugin } from './privacy-channels.mjs';
export default makeExtensionChannelPlugin('session-log-deepseek', upstream);
