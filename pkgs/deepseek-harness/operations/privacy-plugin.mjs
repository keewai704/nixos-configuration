import { join } from 'node:path';
import { resolveDshHome } from '@deepseek-ai/dsh-home-paths';
import { PrivacyStore, PRIVACY_CHANNELS } from './privacy-store.mjs';

export const name = 'privacy-policy';

export function apply(ctx) {
  const store = new PrivacyStore(join(resolveDshHome(), 'operations'));
  const attachments = new Map();
  let closed = false;
  let tail = Promise.resolve();
  const policy = {
    get: channel => store.get(channel),
    enabled(channel) {
      if (closed || channel === 'session-telemetry-otel' && process.env.DSH_TELEMETRY_DISABLED) return false;
      return store.get(channel).enabled;
    },
    attach(channel, read, reconcile = async () => {}) {
      if (!PRIVACY_CHANNELS.includes(channel) || attachments.has(channel)) throw new Error('Duplicate privacy channel controller');
      const attachment = { read, reconcile };
      attachments.set(channel, attachment);
      return () => { if (attachments.get(channel) === attachment) attachments.delete(channel); };
    },
    status(channel) {
      const saved = store.get(channel);
      const attachment = attachments.get(channel);
      const forced = channel === 'session-telemetry-otel' && Boolean(process.env.DSH_TELEMETRY_DISABLED);
      return { ...saved, effective: forced ? 'disabled' : attachment?.read() ?? 'not-active', editable: Boolean(attachment) && !forced, forced };
    },
    change(channel, enabled, revision, confirmation) {
      const task = tail.then(async () => {
        if (closed) throw new Error('Privacy service is closed');
        if (channel === 'session-telemetry-otel' && process.env.DSH_TELEMETRY_DISABLED && enabled) throw new Error('Telemetry is disabled by deployment environment');
        const saved = store.set(channel, enabled, revision, confirmation);
        const failures = [];
        try { await attachments.get(channel)?.reconcile(); } catch (error) { failures.push(error); }
        return { ...saved, effective: policy.status(channel).effective, application: failures.length ? 'saved-reconcile-required' : 'applied' };
      });
      tail = task.catch(() => {});
      return task;
    },
  };
  ctx.provide('privacyPolicy', policy);
  ctx.effect(() => async () => { closed = true; await tail; store.close(); });
}
