import { LlmAdapter, createUserMessage } from "@deepseek-ai/dsh-llm";

export const name = "recovery-fixture";
export const inject = ["llm", "agents", "goals", "sessions", "sessionController"];

function report(event) {
  process.stdout.write("RECOVERY_TEST " + JSON.stringify(event) + "\n");
}

export function apply(ctx) {
  class Adapter extends LlmAdapter {
    async *stream(options) {
      if (options.purpose) throw new Error("Unexpected auxiliary request");
      const agent = ctx.agents.get(options.sessionId);
      if (!agent) throw new Error("Missing real agent");
      if (process.env.RECOVERY_PHASE === "seed") {
        if (process.env.RECOVERY_GOAL === "yes") {
          ctx.goals.create(agent, { objective: "Finish the restart regression", maxGoalRounds: 8 });
        }
        await ctx.sessions.flush(agent.session);
        report({ type: "seed-ready", sessionId: agent.id, goal: ctx.goals.get(agent) ?? null });
      } else {
        const message = options.messages.findLast((message) => message.role === "user" && ["user", "goal"].includes(message.source?.kind));
        report({ type: "recovered", sessionId: agent.id, source: message?.source, content: message?.content, goal: ctx.goals.get(agent) ?? null });
      }
      await new Promise((resolve) => {
        if (options.signal?.aborted) resolve();
        else options.signal?.addEventListener("abort", resolve, { once: true });
      });
    }
  }
  ctx.llm.registerAdapter(["recovery-fixture"], new Adapter());
  const ready = ctx.get("appReady");
  ctx.effect(() => ready.onReady(() => {
    report({ type: "boot-ready" });
    if (process.env.RECOVERY_PHASE !== "seed") return;
    void (async () => {
      const { sessionId } = await ctx.sessionController.create({ cwd: process.cwd() });
      const { agent, error } = await ctx.sessionController.resolveAgent(sessionId);
      if (error) throw error;
      agent.followup(createUserMessage({ source: { kind: "user" }, content: [{ type: "text", text: "Seed interrupted work" }] }));
    })().catch((error) => report({ type: "fixture-error", message: error.stack }));
  }));
}
