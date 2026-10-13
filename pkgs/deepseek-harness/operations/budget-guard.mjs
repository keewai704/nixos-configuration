export const name = 'budget-dispatch-guard';
export const inject = ['llm'];

export function apply(ctx) {
  ctx.on('llm/stream', function (_options, next) {
    const identity = ctx.get('budgetPolicy')?.identity;
    return (async function* () {
      if (typeof identity !== 'symbol' || ctx.get('budgetPolicy')?.identity !== identity) throw new Error('Budget policy changed or is unavailable; model dispatch refused');
      return yield* next();
    })();
  }, { prepend: true });
  ctx.provide('budgetDispatchGuard', {});
}
