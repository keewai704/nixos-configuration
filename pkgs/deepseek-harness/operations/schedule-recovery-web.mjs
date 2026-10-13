import { jsonRoute, OperationError } from './core.mjs';

export function registerScheduleRecoveryRoutes(ctx) {
  const routes = [
    { path: '/api/operations/deliveries', methods: ['GET'], requestBody: 'buffered', fetch: jsonRoute('GET', () => ctx.scheduleRecovery.list()) },
    { path: '/api/operations/deliveries/retry', methods: ['POST'], requestBody: 'buffered', fetch: jsonRoute('POST', async (input, request) => {
      let origin;
      try { origin = new URL(request.headers.get('origin')); } catch { throw new OperationError('Same-origin operator request required', 403); }
      if (!['https:', 'http:'].includes(origin.protocol) || origin.origin !== request.headers.get('origin') || origin.host !== request.headers.get('host')) throw new OperationError('Same-origin operator request required', 403);
      const site = request.headers.get('sec-fetch-site');
      if (site !== null && site !== 'same-origin') throw new OperationError('Cross-origin action rejected', 403);
      if (Object.keys(input).some(key => !['id', 'expectedRevision', 'confirmation'].includes(key))) throw new OperationError('Unknown delivery recovery field');
      request.signal.throwIfAborted();
      try { return { obligation: await ctx.scheduleRecovery.retry(input) }; }
      catch (error) { throw new OperationError(`Delivery recovery refused (${error.code ?? 'recovery-error'}); refresh and inspect the obligation`, 409); }
    }) },
  ];
  for (const route of routes) ctx.effect(() => ctx.connection.fetch.register(route));
}
