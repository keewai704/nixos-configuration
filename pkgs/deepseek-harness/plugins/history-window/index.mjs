export const name = "dsh-history-window";
export const inject = ["sessionController"];

export function initialWindow(request) {
  const maximum = request.maxMessages === undefined ? 50 : request.maxMessages;
  if (!Number.isSafeInteger(maximum) || maximum <= 0) return request;
  const window = request.turnWindow;
  if (window !== undefined && (!window || !Number.isSafeInteger(window.minMessages) || window.minMessages <= 0 || window.minMessages > maximum || !Number.isSafeInteger(window.minTurns) || window.minTurns <= 0)) return request;
  const maxMessages = Math.min(maximum, 24);
  return {
    ...request,
    maxMessages,
    turnWindow: {
      minMessages: Math.min(window?.minMessages ?? 8, 8, maxMessages),
      minTurns: 1,
    },
  };
}

export function apply(ctx) {
  ctx.effect(() => {
    const controller = ctx.sessionController;
    const own = Object.getOwnPropertyDescriptor(controller, "follow");
    let prototype = controller;
    while (prototype && !Object.hasOwn(prototype, "follow")) prototype = Object.getPrototypeOf(prototype);
    const original = prototype && Object.getOwnPropertyDescriptor(prototype, "follow")?.value;
    if (typeof original !== "function") throw new Error("DSH history follow API is unavailable");
    function follow(request, signal) {
      return original.call(this, initialWindow(request), signal);
    }
    Object.defineProperty(controller, "follow", { configurable: true, writable: true, value: follow });
    return () => {
      if (Object.getOwnPropertyDescriptor(controller, "follow")?.value !== follow) return;
      if (own) Object.defineProperty(controller, "follow", own);
      else delete controller.follow;
    };
  });
}
