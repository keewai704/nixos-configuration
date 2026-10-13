import { randomUUID } from 'node:crypto';
import { BudgetError, validateLimits } from './budget.mjs';

const count = value => Number.isSafeInteger(value) && value > 0;
const supported = new Set(['deepseek-official']);
const fail = message => { throw new BudgetError(message); };

export function createBudgetPolicy(ctx, ledger, { limits = {}, routes = {} } = {}) {
  validateLimits(limits);
  let closing = false;
  const pending = new Set();
  const cancellations = new Set();
  const lineage = new Map();
  const agents = () => { const value = ctx.get('agents'); if (!value) fail('Budget agent registry is unavailable'); return value; };

  async function bindSession(header, visited = new Set()) {
    const key = String(header.id);
    if (visited.has(key)) fail('Budget lineage contains a cycle');
    const ancestors = new Set([...visited, key]);
    if (visited.size === 0 && lineage.has(key)) return lineage.get(key);
    const task = (async () => {
      if (header.parentSession !== undefined) {
        try { ledger.rootFor(header.parentSession); }
        catch {
          const parent = agents().get(header.parentSession)?.session.header
            ?? (await ctx.sessionPersistence.stat(header.parentSession))?.header;
          if (!parent || parent.id === header.id) fail('Budget parent lineage is unavailable');
          await bindSession(parent, ancestors);
        }
      }
      return ledger.bindSession({ id: key, createdAt: header.createdAt, ...(header.parentSession === undefined ? {} : { parentId: String(header.parentSession) }) }, limits);
    })();
    lineage.set(key, task);
    try { return await task; } finally { lineage.delete(key); }
  }

  async function sessionIdFor(options) {
    const initiator = agents().currentInitiator?.();
    const id = options.sessionId ?? initiator?.id;
    if (id === undefined) fail('Budget accounting requires an explicit session or initiating agent');
    try { ledger.rootFor(id); }
    catch {
      const header = agents().get(id)?.session.header ?? (await ctx.sessionPersistence.stat(id))?.header;
      if (!header) fail('Budget session lineage is unavailable');
      await bindSession(header);
    }
    return id;
  }

  function routeFor(provider, model) {
    const configured = routes[`${provider}/${model}`];
    if (configured === undefined) return undefined;
    if (!configured || typeof configured !== 'object' || Array.isArray(configured)
      || Object.keys(configured).some(key => !['maxOutputTokens', 'inputTokenUpperBound', 'pricing'].includes(key))
      || (configured.maxOutputTokens !== undefined && !count(configured.maxOutputTokens))
      || (configured.inputTokenUpperBound !== undefined && !count(configured.inputTokenUpperBound))) fail('Invalid budget route configuration');
    return configured;
  }

  function deadlineTimer(deadlineAt, action) {
    let timer;
    let stopped = false;
    const arm = () => {
      if (stopped || deadlineAt === undefined) return;
      const delay = deadlineAt - ledger.now();
      if (delay <= 0) { action(); return; }
      timer = setTimeout(arm, Math.min(delay, 2_147_483_647));
      timer.unref();
    };
    arm();
    return () => { stopped = true; clearTimeout(timer); };
  }

  const policy = {
    identity: Symbol('budget-policy'),
    ready: Promise.resolve(),
    bindSession,
    snapshot: sessionId => ledger.snapshot(sessionId),
    configure: input => ledger.configure(input),
    reconcile: input => ledger.reconcile(input),
    capabilities: () => ({
      sharedLineage: true, persisted: true, accountingScope: 'Calls admitted after ledger enrollment; historical sessions are not retroactively billed.',
      requestCaps: 'host llm/stream attempts; opaque external executors are refused',
      outputCaps: [...supported], hardCostAvailable: 'Only audited routes with explicitly operator-attested inputTokenUpperBound and integer per-million pricing',
      cost: 'Integer per-million operator pricing is recorded only with complete disjoint usage; unknown billing is never zero. A configured input upper bound is an operator assumption, not a measured estimate or provider guarantee.',
      totalInputCap: false, limits: ['maxRequests', 'maxChildren', 'maxConcurrentChildren', 'maxOutputTokens', 'maxCostMicros', 'deadlineAt'],
      deadline: 'Admission cutoff plus active local cancellation and external disposal; failed cleanup retains uncertain reservations.',
    }),
    async request({ agent, signal }, next) {
      if (closing) fail('Budget policy is closing');
      const config = await next();
      signal.throwIfAborted();
      await bindSession(agent.session.header);
      const route = routeFor(config.provider, config.model);
      const limits = ledger.snapshot(agent.id).limits;
      if (limits.maxCostMicros !== undefined && (!supported.has(config.provider) || !route?.inputTokenUpperBound || !route?.pricing)) fail('Hard cost budget requires an audited route with operator-attested input billing upper bound and pricing');
      if ((limits.maxOutputTokens !== undefined || limits.maxCostMicros !== undefined) && (!supported.has(config.provider) || !route?.maxOutputTokens)) fail('Hard output budget requires an audited route and configured output maximum');
      if (route?.maxOutputTokens !== undefined && supported.has(config.provider)) {
        return { ...config, maxTokens: Math.min(config.maxTokens ?? route.maxOutputTokens, route.maxOutputTokens) };
      }
      return config;
    },
    stream(options, next) {
      const done = Promise.withResolvers();
      const job = randomUUID();
      return (async function* () {
        pending.add(done.promise);
        let stopTimer = () => {};
        let cancel = () => {};
        let reservation;
        let dispatched = false;
        let usage;
        let finish;
        let ended = false;
        try {
          if (closing) fail('Budget policy is closing');
          const sessionId = await sessionIdFor(options);
          options.signal?.throwIfAborted();
          const route = routeFor(options.provider, options.model);
          const bounded = supported.has(options.provider) && count(options.maxTokens);
          reservation = ledger.reserveRequest({
            sessionId, provider: options.provider, model: options.model, purpose: options.purpose ?? 'conversation',
            outputUpper: bounded ? options.maxTokens : 0, outputBoundKnown: bounded,
            ...route?.inputTokenUpperBound === undefined ? {} : { inputUpper: route.inputTokenUpperBound, inputBoundKnown: bounded },
            ...route?.pricing === undefined ? {} : { pricing: route.pricing },
          });
          const deadlineAt = ledger.snapshot(sessionId).limits.deadlineAt;
          const liveAgent = agents().get(sessionId);
          if (deadlineAt !== undefined && (!liveAgent || !options.signal)) fail('Active deadline requires a live cancellable agent request');
          cancel = () => liveAgent?.cancel({ kind: 'parent' });
          cancellations.add(cancel);
          stopTimer = deadlineTimer(deadlineAt, cancel);
          options.signal?.throwIfAborted();
          if (liveAgent && await ctx.sessions.flush(liveAgent.session) !== true) fail('Session checkpoint did not acknowledge durability before budget dispatch');
          options.signal?.throwIfAborted();
          if (closing) fail('Budget policy is closing');
          ledger.markDispatched(reservation);
          dispatched = true;
          for await (const chunk of next()) {
            if (chunk.type === 'usage') usage = chunk.usage;
            if (chunk.type === 'finish') finish = chunk;
            else yield chunk;
          }
          ended = ['stop', 'tool-calls', 'max-tokens'].includes(finish?.reason?.kind);
          ledger.settleRequest(reservation, { usage, complete: ended });
          reservation = undefined;
          if (finish) yield finish;
        } finally {
          try {
            if (reservation !== undefined) {
              if (dispatched) ledger.settleRequest(reservation, { usage, complete: ended });
              else ledger.cancelRequest(reservation);
            }
          } finally { stopTimer(); cancellations.delete(cancel); pending.delete(done.promise); done.resolve(job); }
        }
      })();
    },
    async tool(exec, next) {
      if (closing) fail('Budget policy is closing');
      if (!exec.agent) fail('Budget tool accounting requires a calling agent');
      await bindSession(exec.agent.session.header);
      const limits = ledger.snapshot(exec.agent.id).limits;
      ledger.assertDeadline(limits);
      exec.signal.throwIfAborted();
      const done = Promise.withResolvers();
      const controller = new AbortController();
      const original = exec.signal;
      const cancel = () => { controller.abort(new BudgetError('Root budget deadline exceeded')); exec.agent.cancel({ kind: 'parent' }); };
      pending.add(done.promise);
      cancellations.add(cancel);
      const stopTimer = deadlineTimer(limits.deadlineAt, cancel);
      exec.signal = AbortSignal.any([original, controller.signal]);
      try { exec.signal.throwIfAborted(); return await next(); }
      finally { exec.signal = original; stopTimer(); cancellations.delete(cancel); pending.delete(done.promise); done.resolve(); }
    },
    async admitChild(request) {
      if (closing) fail('Budget policy is closing');
      await bindSession(request.parent.session.header);
      request.signal.throwIfAborted();
      const id = ledger.reserveChild({ parentId: request.parent.id, childId: request.childId, kind: request.kind, provider: request.provider });
      const controller = new AbortController();
      const done = Promise.withResolvers();
      pending.add(done.promise);
      const cancel = () => controller.abort(new BudgetError('Root budget admission lifetime ended'));
      cancellations.add(cancel);
      const stopTimer = deadlineTimer(ledger.snapshot(request.parent.id).limits.deadlineAt, cancel);
      let settled = false;
      return {
        signal: controller.signal,
        publish: childId => ledger.publishChild(id, childId),
        settle: outcome => {
          if (settled) return;
          try { ledger.settleChild(id, outcome); settled = true; }
          finally { stopTimer(); cancellations.delete(cancel); pending.delete(done.promise); done.resolve(); }
        },
      };
    },
    async close() { closing = true; for (const cancel of cancellations) cancel(); await Promise.allSettled([...pending]); ledger.close(); },
  };
  return policy;
}
