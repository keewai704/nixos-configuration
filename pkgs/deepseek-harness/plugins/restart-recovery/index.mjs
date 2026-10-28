import { createUserMessage } from "@deepseek-ai/dsh-llm";
import { randomUUID } from "node:crypto";
import { closeSync, fsyncSync, mkdirSync, openSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

export const name = "dsh-restart-recovery";
export const inject = ["agents", "goals", "sessionController"];

function interrupted(event, entry = {}) {
  if (event?.type !== "turn/end") return false;
  if (event.data.reason?.kind === "interrupted") return true;
  if (event.data.reason?.kind !== "aborted") return false;
  const cause = event.data.reason.reason?.kind;
  return ["disposed", "interrupted"].includes(cause) || cause === "parent" && Boolean(entry.goalId && entry.armed);
}

function pendingInput(events) {
  const inbox = { "next-turn": [], "next-step": [] };
  for (const event of events) {
    if (event.type !== "agent/inbox/spliced") continue;
    const { target, start, removedCount = 0, inserted } = event.data;
    inbox[target]?.splice(start, removedCount, ...inserted);
  }
  return Object.values(inbox).some((messages) => messages.length > 0);
}

export function needsRecovery(events, entry) {
  const last = events.findLast((event) => event.type === "turn/start" || event.type === "turn/end");
  if (last?.type === "turn/start" || interrupted(last, entry)) return true;
  if (last && last.data.reason?.kind !== "completed") return false;
  return Boolean(entry.goalId && entry.armed) || pendingInput(events);
}

function eligible(header) {
  return Boolean(header.cwd) && header.origin !== "subagent";
}

export class Recovery {
  constructor(ctx, file) {
    this.ctx = ctx;
    this.file = file;
    this.closed = false;
    let state = { version: 1, sessions: [] };
    try { state = JSON.parse(readFileSync(file, "utf8")); }
    catch (error) { if (error.code !== "ENOENT") throw new Error("Invalid restart recovery state", { cause: error }); }
    if (state.version !== 1 || !Array.isArray(state.sessions) || state.sessions.some((entry) => !entry || typeof entry.id !== "string" || !entry.id || (entry.goalId !== undefined && (typeof entry.goalId !== "string" || typeof entry.armed !== "boolean")))) throw new Error("Invalid restart recovery state");
    this.entries = new Map(state.sessions.map((entry) => [entry.id, entry]));
    this.candidates = [...this.entries.values()];
  }

  save() {
    mkdirSync(dirname(this.file), { recursive: true, mode: 0o700 });
    const temporary = this.file + "." + randomUUID() + ".tmp";
    const fd = openSync(temporary, "wx", 0o600);
    try {
      writeFileSync(fd, JSON.stringify({ version: 1, sessions: [...this.entries.values()] }) + "\n");
      fsyncSync(fd);
    } finally { closeSync(fd); }
    renameSync(temporary, this.file);
    const directory = openSync(dirname(this.file), "r");
    try { fsyncSync(directory); } finally { closeSync(directory); }
  }

  forget(id) {
    if (this.entries.delete(id)) this.save();
  }

  track(agent) {
    if (this.closed || !eligible(agent.session.header)) return;
    const goal = this.ctx.goals.get(agent);
    const entry = { id: agent.id };
    if (goal && (goal.phase !== "complete" || this.entries.get(agent.id)?.goalId === goal.id)) {
      entry.goalId = goal.id;
      entry.armed = goal.activation === "armed";
    }
    if (JSON.stringify(this.entries.get(agent.id)) === JSON.stringify(entry)) return;
    this.entries.set(agent.id, entry);
    this.save();
  }

  event(session, event) {
    if (this.closed) return;
    const agent = this.ctx.agents.get(session.id ?? session.header.id);
    if (!agent || agent.session !== session || !eligible(session.header)) return;
    if (event.type === "turn/start") this.track(agent);
    if (event.type === "goal/change") {
      const goal = this.ctx.goals.get(agent);
      if (goal && goal.phase !== "active") this.forget(agent.id);
      else if (agent.status === "running" || goal?.activation === "armed") this.track(agent);
    }
    if (event.type === "turn/end" && !interrupted(event, this.entries.get(agent.id))) {
      const goal = this.ctx.goals.get(agent);
      if (event.data.reason?.kind === "completed" && (goal?.phase === "active" && goal.activation === "armed" || agent.inbox.nextTurn.length || agent.inbox.nextStep.length)) this.track(agent);
      else this.forget(agent.id);
    }
  }

  idle(agent) {
    const last = agent.session.ownEvents().findLast((event) => event.type === "turn/end");
    if (interrupted(last, this.entries.get(agent.id))) return;
    const goal = this.ctx.goals.get(agent);
    if (goal?.phase === "active" && goal.activation === "armed") this.track(agent);
    else this.forget(agent.id);
  }

  recover() {
    return this.work ??= this.recoverCandidates();
  }

  async recoverCandidates() {
    for (const entry of this.candidates) {
      if (this.closed) return;
      try {
        const inspection = await this.ctx.sessionController.inspect(entry.id);
        if (this.closed) return;
        if (!eligible(inspection.meta) || !needsRecovery(inspection.events.slice(inspection.inheritedEventCount ?? 0), entry)) {
          this.forget(entry.id);
          continue;
        }
        const result = await this.ctx.sessionController.resolveAgent(entry.id);
        if (this.closed) return;
        if (result.error) throw result.error;
        const { agent } = result;
        if (agent.status === "running") continue;
        if (!needsRecovery(agent.session.ownEvents(), entry)) {
          this.forget(entry.id);
          continue;
        }
        const goal = this.ctx.goals.get(agent);
        if (goal || entry.goalId) {
          if (!goal || goal.phase !== "active" || goal.roundsStarted >= goal.maxGoalRounds || entry.goalId && (!entry.armed || goal.id !== entry.goalId)) {
            this.forget(entry.id);
            continue;
          }
          this.ctx.goals.resume(agent, { id: goal.id, revision: goal.revision });
        } else {
          agent.followup(createUserMessage({
            source: { kind: "user" },
            content: [{ type: "text", text: "Continue." }],
          }));
        }
        this.ctx.logger.info("Resumed interrupted task: %s", entry.id);
      } catch (error) {
        this.ctx.logger.warn("Restart recovery deferred for %s: %s", entry.id, error instanceof Error ? error.message : String(error));
      }
    }
  }

  close() { this.closed = true; }
}

export function apply(ctx) {
  const home = process.env.DSH_HOME || join(homedir(), ".dsh");
  const recovery = new Recovery(ctx, join(home, "restart-recovery", encodeURIComponent(process.env.DSH_PROFILE || "web") + ".json"));
  ctx.effect(() => () => { recovery.close(); return recovery.work; });
  ctx.on("agent/status", ({ agent, status }) => {
    if (recovery.closed) return;
    if (status === "running") recovery.track(agent);
    else recovery.idle(agent);
  }, { global: true });
  ctx.on("session/event", (session, event) => recovery.event(session, event), { global: true });
  for (const agent of ctx.agents.list()) if (agent.status === "running") recovery.track(agent);
  const ready = ctx.get("appReady");
  if (ready) ctx.effect(() => ready.onReady(() => { void recovery.recover(); }));
  else void recovery.recover();
}
