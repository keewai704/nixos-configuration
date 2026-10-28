import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { Context } from "@deepseek-ai/cordis";
import { SessionController } from "@deepseek-ai/dsh-api-session-controller";
import { interruptedTurnClosers } from "@deepseek-ai/dsh-session";
import { apply, needsRecovery, Recovery } from "./index.mjs";

const start = { type: "turn/start", data: { turn: 1 } };
const end = (kind, reason) => ({ type: "turn/end", data: { turn: 1, reason: { kind, ...(reason ? { reason: { kind: reason } } : {}) } } });
const armed = { id: "goal", revision: 2, phase: "active", activation: "armed", roundsStarted: 1, maxGoalRounds: 10 };

function fixture(t, goal) {
  const directory = mkdtempSync(join(tmpdir(), "dsh-recovery-test-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const file = join(directory, "state.json");
  const messages = [];
  const agent = { id: "session", status: "running", session: { header: { id: "session", cwd: directory }, ownEvents: () => agent.events }, events: [start], inbox: { nextTurn: [], nextStep: [] }, followup: (message) => messages.push(message) };
  const ctx = {
    agents: { get: () => agent, list: () => [agent] },
    goals: { get: () => goal, resume: (_agent, ref) => { assert.equal(ref.id, goal.id); goal = { ...goal, activation: "armed" }; ctx.rearms++; } },
    sessionController: { inspect: async () => ({ meta: agent.session.header, events: agent.events }), resolveAgent: async () => ({ agent }) },
    logger: { warn: () => { ctx.warnings++; }, info() {} },
    rearms: 0, warnings: 0,
  };
  return { file, agent, ctx, messages };
}

function persist(file, entry = { id: "session" }) {
  writeFileSync(file, JSON.stringify({ version: 1, sessions: [entry] }));
}

test("real Cordis wiring waits for successful application startup before recovering", async (t) => {
  const fixtureState = fixture(t);
  const home = join(fixtureState.file, "..");
  const file = join(home, "restart-recovery", "web.json");
  const previousHome = process.env.DSH_HOME;
  const previousProfile = process.env.DSH_PROFILE;
  process.env.DSH_HOME = home;
  process.env.DSH_PROFILE = "web";
  t.after(() => {
    if (previousHome === undefined) delete process.env.DSH_HOME; else process.env.DSH_HOME = previousHome;
    if (previousProfile === undefined) delete process.env.DSH_PROFILE; else process.env.DSH_PROFILE = previousProfile;
  });
  const saved = new Recovery(fixtureState.ctx, file);
  saved.track(fixtureState.agent);
  saved.close();
  fixtureState.agent.status = "idle";
  const ctx = new Context();
  for (const key of ["agents", "goals", "sessionController"]) ctx.provide(key, fixtureState.ctx[key]);
  let ready;
  ctx.provide("appReady", { onReady(listener) { ready = listener; return () => { ready = undefined; }; } });
  const done = Promise.withResolvers();
  const followup = fixtureState.agent.followup;
  fixtureState.agent.followup = (message) => { followup(message); done.resolve(); };
  apply(ctx);
  await ctx.fiber.await();
  assert.equal(fixtureState.messages.length, 0);
  assert.equal(typeof ready, "function");
  ready();
  await done.promise;
  assert.equal(fixtureState.messages.length, 1);
  await ctx.fiber.dispose();
  assert.equal(ready, undefined);
});

test("only interrupted turns or previously armed active goals are eligible", () => {
  assert.equal(needsRecovery([start], {}), true);
  for (const cause of ["disposed", "interrupted"]) assert.equal(needsRecovery([start, end("aborted", cause)], {}), true);
  for (const event of [end("completed"), end("error"), end("blocked"), end("aborted", "user")]) assert.equal(needsRecovery([start, event], {}), false);
  assert.equal(needsRecovery([start, end("completed")], { goalId: "goal", armed: true }), true);
  assert.equal(needsRecovery([start, end("aborted", "parent")], {}), false);
  assert.equal(needsRecovery([start, end("aborted", "parent")], { goalId: "goal", armed: true }), true);
  assert.equal(needsRecovery([], {}), false);
});

test("core crash-recovery closers remain eligible for automatic continuation", () => {
  const events = [{ ...start, seq: 1, time: 1 }];
  const closers = interruptedTurnClosers(events);
  assert.equal(closers.at(-1).data.reason.kind, "interrupted");
  assert.equal(needsRecovery([...events, ...closers], {}), true);
});

test("running markers survive a crash and disposed shutdown but not a user stop", (t) => {
  const { ctx, file, agent } = fixture(t);
  const recovery = new Recovery(ctx, file);
  recovery.track(agent);
  assert.deepEqual(JSON.parse(readFileSync(file)).sessions, [{ id: "session" }]);
  assert.equal(statSync(file).mode & 0o777, 0o600);
  recovery.event(agent.session, end("aborted", "disposed"));
  assert.equal(JSON.parse(readFileSync(file)).sessions.length, 1);
  recovery.event(agent.session, end("aborted", "user"));
  assert.equal(JSON.parse(readFileSync(file)).sessions.length, 0);
});

test("recovery consumes the real SessionController inspection contract", async (t) => {
  const { ctx, file, agent, messages } = fixture(t);
  persist(file);
  agent.status = "idle";
  const observation = { header: agent.session.header, events: agent.events, inheritedEventCount: 0, [Symbol.dispose]() {} };
  const controller = { ctx: { sessions: { get: () => undefined }, sessionQuery: { observeSession: async () => observation } } };
  ctx.sessionController.inspect = (id) => SessionController.prototype.inspect.call(controller, id);
  assert.equal((await ctx.sessionController.inspect("session")).meta, agent.session.header);
  await new Recovery(ctx, file).recover();
  assert.equal(messages.length, 1);
});

test("interrupted work without a goal receives exactly Continue. as a user prompt once", async (t) => {
  const { ctx, file, agent, messages } = fixture(t);
  persist(file);
  agent.status = "idle";
  const recovery = new Recovery(ctx, file);
  await Promise.all([recovery.recover(), recovery.recover()]);
  assert.equal(messages.length, 1);
  assert.equal(messages[0].role, "user");
  assert.deepEqual(messages[0].source, { kind: "user" });
  assert.deepEqual(messages[0].content, [{ type: "text", text: "Continue." }]);
});

test("completed, canceled and subagent sessions are not driven", async (t) => {
  for (const terminal of [end("completed"), end("error"), end("aborted", "user")]) {
    const { ctx, file, agent, messages } = fixture(t);
    persist(file);
    agent.status = "idle";
    agent.events.push(terminal);
    await new Recovery(ctx, file).recover();
    assert.equal(messages.length, 0);
    assert.equal(JSON.parse(readFileSync(file)).sessions.length, 0);
  }
  const { ctx, file, agent, messages } = fixture(t);
  persist(file);
  agent.status = "idle";
  agent.session.header.origin = "subagent";
  await new Recovery(ctx, file).recover();
  assert.equal(messages.length, 0);
});

test("an armed goal is rearmed with its persisted identity and budget", async (t) => {
  const { ctx, file, agent, messages } = fixture(t, { ...armed, activation: "disarmed" });
  persist(file, { id: "session", goalId: "goal", armed: true });
  agent.status = "idle";
  agent.events.push(end("completed"));
  await new Recovery(ctx, file).recover();
  assert.equal(ctx.rearms, 1);
  assert.equal(messages.length, 0);
});

test("a live active goal takes precedence over a marker without goal metadata", async (t) => {
  const { ctx, file, agent, messages } = fixture(t, { ...armed, activation: "disarmed" });
  persist(file);
  agent.status = "idle";
  await new Recovery(ctx, file).recover();
  assert.equal(ctx.rearms, 1);
  assert.equal(messages.length, 0);
});

test("a stopped current goal never receives Continue. even without saved goal metadata", async (t) => {
  for (const goal of [{ ...armed, phase: "paused" }, { ...armed, phase: "complete" }, { ...armed, roundsStarted: 10 }]) {
    const { ctx, file, agent, messages } = fixture(t, goal);
    persist(file);
    agent.status = "idle";
    await new Recovery(ctx, file).recover();
    assert.equal(messages.length, 0);
    assert.equal(ctx.rearms, 0);
  }
});

test("a cleared saved goal does not fall back to a user continuation", async (t) => {
  const { ctx, file, agent, messages } = fixture(t);
  persist(file, { id: "session", goalId: "goal", armed: true });
  agent.status = "idle";
  await new Recovery(ctx, file).recover();
  assert.equal(messages.length, 0);
  assert.equal(ctx.rearms, 0);
});

test("paused, blocked, completed, replaced, disarmed or exhausted goals stay stopped", async (t) => {
  for (const goal of [{ ...armed, phase: "paused" }, { ...armed, phase: "blocked" }, { ...armed, phase: "complete" }, { ...armed, id: "different" }, { ...armed, roundsStarted: 10 }]) {
    const { ctx, file, agent, messages } = fixture(t, goal);
    persist(file, { id: "session", goalId: "goal", armed: true });
    agent.status = "idle";
    await new Recovery(ctx, file).recover();
    assert.equal(messages.length, 0);
    assert.equal(ctx.rearms, 0);
  }
  const { ctx, file, agent, messages } = fixture(t, armed);
  persist(file, { id: "session", goalId: "goal", armed: false });
  agent.status = "idle";
  await new Recovery(ctx, file).recover();
  assert.equal(messages.length, 0);
});

test("manual activity wins races and temporarily unavailable sessions remain retryable", async (t) => {
  const { ctx, file, messages } = fixture(t);
  persist(file);
  await new Recovery(ctx, file).recover();
  assert.equal(messages.length, 0);
  ctx.sessionController.resolveAgent = async () => ({ error: new Error("writer held") });
  await new Recovery(ctx, file).recover();
  assert.equal(ctx.warnings, 1);
  assert.equal(JSON.parse(readFileSync(file)).sessions.length, 1);
});

test("a task completed while resolving its agent is not resumed from a stale inspection", async (t) => {
  const { ctx, file, agent, messages } = fixture(t);
  persist(file);
  agent.status = "idle";
  ctx.sessionController.inspect = async () => ({ meta: agent.session.header, events: [...agent.events] });
  ctx.sessionController.resolveAgent = async () => { agent.events.push(end("completed")); return { agent }; };
  await new Recovery(ctx, file).recover();
  assert.equal(messages.length, 0);
});

test("unload during an inspection never starts a task", async (t) => {
  const { ctx, file, agent, messages } = fixture(t);
  persist(file);
  agent.status = "idle";
  const gate = Promise.withResolvers();
  ctx.sessionController.inspect = () => gate.promise;
  const recovery = new Recovery(ctx, file);
  const work = recovery.recover();
  recovery.close();
  gate.resolve({ meta: agent.session.header, events: agent.events });
  await work;
  assert.equal(messages.length, 0);
});

test("durable markers survive two instances and disappear after the recovered task finishes", async (t) => {
  const { ctx, file, agent, messages } = fixture(t);
  const before = new Recovery(ctx, file);
  before.track(agent);
  before.event(agent.session, end("aborted", "disposed"));
  before.close();
  agent.status = "idle";
  agent.events.push(end("aborted", "disposed"));
  const after = new Recovery(ctx, file);
  await after.recover();
  assert.equal(messages.length, 1);
  after.event(agent.session, end("completed"));
  after.close();
  await new Recovery(ctx, file).recover();
  assert.equal(messages.length, 1);
});

test("queued user input is recovered even across a between-turn crash", () => {
  const queued = { type: "agent/inbox/spliced", data: { target: "next-turn", start: 0, inserted: [{ id: "queued" }] } };
  assert.equal(needsRecovery([start, queued, end("completed")], {}), true);
  const consumed = { type: "agent/inbox/spliced", data: { target: "next-turn", start: 0, removedCount: 1, inserted: [] } };
  assert.equal(needsRecovery([start, queued, consumed, end("completed")], {}), false);
});

test("malformed durable state fails closed instead of resuming arbitrary work", (t) => {
  const { ctx, file } = fixture(t);
  writeFileSync(file, '{"version":1,"sessions":[{"id":3}]}');
  assert.throws(() => new Recovery(ctx, file), /state/);
});
