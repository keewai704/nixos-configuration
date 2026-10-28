import assert from "node:assert/strict";
import test from "node:test";
import { Context, Service } from "@deepseek-ai/cordis";
import { apply, initialWindow } from "./index.mjs";

test("the plugin wraps and restores a real Cordis service proxy", async () => {
  const ctx = new Context();
  class Controller extends Service {
    constructor() { super(ctx, "sessionController"); }
    follow(request) { return request; }
  }
  const controller = new Controller();
  apply(ctx);
  await ctx.fiber.await();
  assert.equal(ctx.sessionController.follow({ maxMessages: 500 }).maxMessages, 24);
  await ctx.fiber.dispose();
  assert.equal(controller.follow({ maxMessages: 500 }).maxMessages, 500);
});

test("opening a long conversation uses a small window without mutating callers", () => {
  const request = { address: { kind: "session", sessionId: "long" }, maxMessages: 500, turnWindow: { minMessages: 50, minTurns: 2 }, assistantStream: true };
  assert.deepEqual(initialWindow(request), { ...request, maxMessages: 24, turnWindow: { minMessages: 8, minTurns: 1 } });
  assert.equal(request.maxMessages, 500);
  assert.equal(request.turnWindow.minMessages, 50);
});

test("smaller requests and invalid inputs retain their original validation", () => {
  assert.equal(initialWindow({}).maxMessages, 24);
  const small = { maxMessages: 3, turnWindow: { minMessages: 2, minTurns: 1 } };
  assert.deepEqual(initialWindow(small), small);
  for (const request of [{ maxMessages: 0 }, { maxMessages: -1 }, { maxMessages: 1.5 }, { maxMessages: 4, turnWindow: { minMessages: 5, minTurns: 2 } }, { turnWindow: { minMessages: 1, minTurns: 0 } }]) {
    assert.equal(initialWindow(request), request);
  }
});

test("only follow is bounded; backward pages, signals and cleanup are unchanged", async () => {
  const calls = [];
  const disposers = [];
  const controller = {
    follow(request, signal) { calls.push({ owner: this, request, signal }); return "stream"; },
    page(request) { return request; },
  };
  const original = controller.follow;
  apply({ sessionController: controller, effect(callback) { disposers.push(callback()); } });
  const signal = new AbortController().signal;
  assert.equal(controller.follow({ maxMessages: 500 }, signal), "stream");
  assert.equal(calls[0].owner, controller);
  assert.equal(calls[0].signal, signal);
  assert.equal(calls[0].request.maxMessages, 24);
  const page = { beforeSeq: 100, throughSeq: 200, maxMessages: 500 };
  assert.equal(controller.page(page), page);
  for (const dispose of disposers) dispose();
  assert.equal(controller.follow, original);
});
