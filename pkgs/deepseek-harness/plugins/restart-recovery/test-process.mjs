import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const require = createRequire(import.meta.url);
const cli = join(dirname(require.resolve("@deepseek-ai/dsh/package.json")), "lib/bin.js");
const plugin = dirname(fileURLToPath(import.meta.url));

async function profile(root) {
  const directory = join(root, "dsh/profiles/web");
  await mkdir(join(directory, "node_modules"), { recursive: true });
  await symlink(plugin, join(directory, "node_modules/dsh-restart-recovery"));
  await mkdir(join(directory, "node_modules/recovery-fixture"));
  await writeFile(join(directory, "node_modules/recovery-fixture/package.json"), JSON.stringify({ name: "recovery-fixture", version: "0.0.0", type: "module", exports: "./index.mjs", dsh: { bundle: { patch: "./cordis.patch.yml" } } }));
  await symlink(join(plugin, "fixtures/runtime.mjs"), join(directory, "node_modules/recovery-fixture/index.mjs"));
  await writeFile(join(directory, "node_modules/recovery-fixture/cordis.patch.yml"), '- insert:\n    - id: recovery-fixture\n      name: recovery-fixture\n');
  await writeFile(join(directory, "package.json"), JSON.stringify({ private: true, dsh: { profile: { bundles: ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app", "dsh-restart-recovery", "recovery-fixture"] } } }));
  await writeFile(join(directory, "cordis.patch.yml"), '- id: agent-default-model\n  config:\n    provider: recovery-fixture\n    model: test\n- id: hmr\n  disabled: true\n- id: session-title-llm\n  disabled: true\n');
}

function boot(root, phase, goal) {
  const child = spawn(process.execPath, ["--expose-internals", cli, "--profile", "web", "--host", "127.0.0.1", "--port", "0", "--no-open"], {
    cwd: root,
    env: { HOME: root, DSH_HOME: join(root, "dsh"), PATH: process.env.PATH, DSH_PROFILE: "web", RECOVERY_PHASE: phase, RECOVERY_GOAL: goal ? "yes" : "no", NO_COLOR: "1", DSH_TELEMETRY_MODE: "DISABLED" },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let output = "";
  const diagnostics = () => output.replace(/([?&]token=)[^\s]+/g, "$1<redacted>");
  const events = [];
  const waiters = new Set();
  let buffer = "";
  let ended = false;
  let termination;
  child.stdout.on("data", (chunk) => {
    output += chunk;
    buffer += chunk;
    for (;;) {
      const index = buffer.indexOf("\n");
      if (index < 0) break;
      const line = buffer.slice(0, index);
      buffer = buffer.slice(index + 1);
      if (line.startsWith("RECOVERY_TEST ")) events.push(JSON.parse(line.slice(14)));
    }
    for (const waiter of waiters) waiter();
  });
  child.stderr.on("data", (chunk) => { output += chunk; });
  const exit = new Promise((resolve) => child.once("close", (code, signal) => { ended = true; termination = { code, signal }; resolve(termination); for (const waiter of waiters) waiter(); }));
  child.once("error", (error) => { output += error.stack; });
  return {
    wait(type, timeout = 20000) {
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => done(new Error("Timed out waiting for " + type + "\n" + diagnostics())), timeout);
        const done = (error, value) => { clearTimeout(timer); waiters.delete(check); error ? reject(error) : resolve(value); };
        const check = () => {
          const event = events.find((event) => event.type === type || event.type === "fixture-error");
          if (event?.type === "fixture-error") done(new Error(event.message));
          else if (event) done(null, event);
          else if (ended) done(new Error("Child exited before " + type + " " + JSON.stringify(termination) + "\n" + diagnostics()));
        };
        waiters.add(check); check();
      });
    },
    async stop(signal = "SIGTERM") {
      if (ended) return exit;
      child.kill(signal);
      const timer = setTimeout(() => child.kill("SIGKILL"), 8000);
      try { return await exit; } finally { clearTimeout(timer); }
    },
  };
}

for (const goal of [false, true]) {
  test((goal ? "goal" : "ordinary") + " does not resume when the recovery plugin is disabled", { timeout: 60000 }, async () => {
    const root = await mkdtemp(join(tmpdir(), "dsh-recovery-control-"));
    let child;
    try {
      await profile(root);
      child = boot(root, "seed", goal);
      await child.wait("seed-ready");
      await child.stop();
      const file = join(root, "dsh/profiles/web/package.json");
      const manifest = JSON.parse(await readFile(file, "utf8"));
      manifest.dsh.profile.bundles = manifest.dsh.profile.bundles.filter((name) => name !== "dsh-restart-recovery");
      await writeFile(file, JSON.stringify(manifest));
      child = boot(root, "recover", goal);
      await child.wait("boot-ready");
      await assert.rejects(child.wait("recovered", 1500), /Timed out waiting for recovered/);
    } finally {
      if (child) await child.stop();
      await rm(root, { recursive: true, force: true });
    }
  });
  for (const signal of ["SIGTERM", "SIGKILL"]) {
    test((goal ? "goal" : "ordinary") + " resumes automatically after " + signal, { timeout: 60000 }, async () => {
      const root = await mkdtemp(join(tmpdir(), "dsh-recovery-process-"));
      let child;
      try {
        await profile(root);
        child = boot(root, "seed", goal);
        const seed = await child.wait("seed-ready");
        const stopped = await child.stop(signal);
        assert.deepEqual(stopped, signal === "SIGKILL" ? { code: null, signal } : { code: 0, signal: null });
        const state = JSON.parse(await readFile(join(root, "dsh/restart-recovery/web.json"), "utf8"));
        assert.ok(state.sessions.some((entry) => entry.id === seed.sessionId), "shutdown must preserve the recovery marker");
        child = boot(root, "recover", goal);
        const recovered = await child.wait("recovered");
        assert.equal(recovered.sessionId, seed.sessionId);
        assert.equal(recovered.source?.kind, goal ? "goal" : "user");
        if (goal) {
          assert.equal(recovered.goal.id, seed.goal.id);
          assert.ok(recovered.goal.revision > seed.goal.revision);
        } else assert.deepEqual(recovered.content, [{ type: "text", text: "Continue." }]);
      } finally {
        if (child) await child.stop();
        await rm(root, { recursive: true, force: true });
      }
    });
  }
}
