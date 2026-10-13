import { createHash } from 'node:crypto';

export const privacyChannels = Object.freeze([
  { id: 'session-telemetry-otel', key: 'mode', on: 'FEEDBACK_ONLY', off: 'DISABLED', fallback: 'FEEDBACK_ONLY', scope: 'Explicit feedback can upload the earlier session prefix, regardless of provider.' },
  { id: 'session-log-deepseek', key: 'enabled', on: true, off: false, fallback: true, scope: 'Session history on official DeepSeek requests, including conversation text, system/developer instructions and tool inputs/results, not just metadata. Re-enabling can send the pending backlog.' },
  { id: 'plugin-package-inventory-deepseek', key: 'enabled', on: true, off: false, fallback: true, scope: 'Active plugin names and versions on official DeepSeek requests.' },
  { id: 'product-analytics', key: 'enabled', on: true, off: false, fallback: true, scope: 'Desktop product events, separate from feedback and session-log sharing. Normally absent on Web.' },
]);

export class OperationError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}

function resolved(value) {
  return value && typeof value.get === 'function' ? value.get() : value;
}

function entryFor(ctx, id) {
  const rows = [...ctx.loader.entries()].filter(entry => entry.options.id === id);
  return rows.length === 1 ? rows[0] : undefined;
}

function revision(entry, key) {
  return createHash('sha256').update(JSON.stringify([
    entry.id, entry.fiber?.uid, entry.disabled, entry.fiber?.state,
    entry.options.config ?? {}, resolved(entry.fiber?.config?.[key]),
  ])).digest('hex');
}

export function persistencePolicy(ctx) {
  const value = entryFor(ctx, 'operations')?.fiber?.config?.persistence;
  return ['launch-reset', 'profile'].includes(value) ? value : 'unknown';
}

export function privacySnapshot(ctx) {
  const policy = ctx.get?.('privacyPolicy');
  if (policy) return privacyChannels.map(channel => {
    const state = policy.status(channel.id);
    return { id: channel.id, scope: channel.scope, effective: state.effective, configured: state.enabled, editable: state.editable, revision: state.revision, disabledByEnvironment: state.forced, persistence: 'durable-store' };
  });
  const editable = ctx.configEditor?.entries() ?? [];
  return privacyChannels.map(channel => {
    const entry = entryFor(ctx, channel.id);
    const active = entry && !entry.disabled && entry.fiber?.state === 2;
    const value = entry ? resolved(entry.fiber?.config?.[channel.key]) ?? channel.fallback : undefined;
    return {
      id: channel.id,
      scope: channel.scope,
      effective: !entry ? 'not-mounted' : !active ? 'not-active' : value === channel.on ? 'enabled' : value === channel.off ? 'disabled' : 'unknown',
      configured: entry ? resolved(entry.options.config?.[channel.key]) ?? 'inherited' : null,
      editable: Boolean(active && editable.includes(entry)),
      revision: entry ? revision(entry, channel.key) : null,
      disabledByEnvironment: channel.id === 'session-telemetry-otel' && Boolean(process.env.DSH_TELEMETRY_DISABLED),
    };
  });
}

export async function changePrivacy(ctx, input) {
  const channel = privacyChannels.find(row => row.id === input.id);
  if (!channel) throw new OperationError('Unknown privacy channel');
  const entry = entryFor(ctx, input.id);
  const snapshot = privacySnapshot(ctx).find(row => row.id === input.id);
  if (!snapshot?.editable) throw new OperationError('Privacy channel is not active or is controlled by another configuration layer', 409);
  if (typeof input.enabled !== 'boolean') throw new OperationError('enabled must be boolean');
  const confirmation = `${input.enabled ? 'ENABLE' : 'DISABLE'} ${input.id}`;
  if (input.confirmation !== confirmation) throw new OperationError('Explicit confirmation is required');
  const policy = ctx.get?.('privacyPolicy');
  if (policy) {
    let saved;
    try { saved = await policy.change(input.id, input.enabled, input.revision, input.confirmation); }
    catch (error) { throw new OperationError(error.message, 409); }
    return { channels: privacySnapshot(ctx), application: saved.application, persistence: 'durable-store', remoteDeletion: false, note: 'Consent survives profile regeneration and process restart. Applies to future collection; previously transmitted data is not erased and in-flight requests may finish.' };
  }
  await ctx.configEditor.edit(entry, current => {
    if (input.revision !== revision(entry, channel.key)) throw new OperationError('Privacy configuration changed; refresh before retrying', 409);
    return { ...current, [channel.key]: input.enabled ? channel.on : channel.off };
  });
  return { channels: privacySnapshot(ctx), persistence: persistencePolicy(ctx), remoteDeletion: false, note: 'Applies to future collection. Previously transmitted data is not erased; in-flight requests may finish.' };
}

export function retentionPreview(snapshots, days = 365, now = Date.now()) {
  if (!Number.isSafeInteger(days) || days < 1 || days > 36500) throw new OperationError('days must be an integer from 1 to 36500');
  const cutoff = now - days * 86400000;
  const candidates = snapshots.filter(row => Number.isFinite(row.header.createdAt) && row.header.createdAt < cutoff)
    .map(row => ({ id: String(row.header.id), createdAt: row.header.createdAt, bytes: row.sizeBytes ?? null, formatStatus: row.formatStatus ?? 'unknown' }))
    .sort((a, b) => a.createdAt - b.createdAt || a.id.localeCompare(b.id));
  return {
    days, cutoff, totalSessions: snapshots.length, candidates,
    candidateBytes: candidates.reduce((sum, row) => sum + (row.bytes ?? 0), 0),
    deletionAvailable: false,
    policy: 'Creation age is not inactivity. Preview never deletes. Offline maintenance requires a fresh locked plan and explicit confirmation; no automatic retention is enabled.',
  };
}

export function jsonRoute(method, handler) {
  return async request => {
    const headers = { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' };
    try {
      if (request.method !== method) throw new OperationError('Method not allowed', 405);
      let input;
      if (method === 'POST') {
        if (request.headers.get('content-type')?.split(';')[0].trim().toLowerCase() !== 'application/json') throw new OperationError('JSON required', 415);
        if (request.headers.get('x-dsh-operations') !== '1') throw new OperationError('Same-origin operations header required', 403);
        if (Number(request.headers.get('content-length')) > 32768) throw new OperationError('Request too large', 413);
        const body = await request.text();
        if (Buffer.byteLength(body) > 32768) throw new OperationError('Request too large', 413);
        try { input = JSON.parse(body); } catch { throw new OperationError('Invalid JSON'); }
        if (!input || Array.isArray(input) || typeof input !== 'object') throw new OperationError('Expected JSON object');
      }
      return new Response(JSON.stringify(await handler(input, request)), { headers });
    } catch (error) {
      const known = error instanceof OperationError;
      return new Response(JSON.stringify({ error: known ? error.message : 'Operation failed; inspect the host log without sharing credentials.' }), { status: known ? error.status : 500, headers });
    }
  };
}
