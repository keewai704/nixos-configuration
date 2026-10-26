import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
const bundle = (await fs.readdir(directory)).find((name) => /^binCli-.*\.mjs$/.test(name));
const target = path.join(directory, "codex-recovery-test.mjs");
await fs.writeFile(
  target,
  `${await fs.readFile(path.join(directory, bundle), "utf8")}\n${runCodexRecoveryTests.toString()}\nawait runCodexRecoveryTests();\n`,
);
await import(pathToFileURL(target).href);

async function runCodexRecoveryTests() {
  for (const termination of ["exit", "SIGKILL"]) {
    await runPromiseWith(runSync(context()))(
      scoped(
        gen$1(function* () {
          const child = NodeChildProcess.spawn(
            process.execPath,
            [
              "-e",
              'process.on("message", () => process.exit(17)); process.send("ready");',
            ],
            {
              env: { ...process.env, ELECTRON_RUN_AS_NODE: "1" },
              stdio: ["pipe", "pipe", "pipe", "ipc"],
            },
          );
          const ready = new Promise((resolve, reject) => {
            child.once("message", resolve);
            child.once("error", reject);
          });
          const exited = new Promise((resolve) => {
            child.once("exit", (code, signal) => resolve({ code, signal }));
          });
          yield* addFinalizer(
            yield* Scope,
            sync$1(() => {
              if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
            }),
          );
          yield* tryPromise({ try: () => ready, catch: (cause) => cause });
          const handle = {
            pid: child.pid,
            stdin: drain$1,
            stdout: fromAsyncIterable(child.stdout, (cause) => cause),
            stderr: fromAsyncIterable(child.stderr, (cause) => cause),
            exitCode: tryPromise({ try: () => exited, catch: (cause) => cause }).pipe(
              flatMap$1(({ code, signal }) =>
                signal === null
                  ? succeed$1(code)
                  : fail$1(
                      systemError({
                        _tag: "Unknown",
                        module: "ChildProcess",
                        method: "exitCode",
                        cause: new Error(`Process interrupted due to receipt of signal: '${signal}'`),
                      }),
                    ),
              ),
            ),
          };
          const adapter = yield* makeCodexAdapterV2({
            instanceId: "codex",
            settings: {},
            environment: {},
            clientFactory: { open: () => makeChildProcessClient(handle, {}) },
          }).pipe(provideService(McpProviderSessions, { read: () => succeed$1(undefined) }));
          const runtime = yield* adapter.openSession({
            threadId: "recovery-test-thread",
            providerSessionId: "recovery-test-session",
            runtimePolicy: { cwd: process.cwd(), runtimeMode: "full-access" },
            modelSelection: { instanceId: "codex", model: "gpt-6.1-sol" },
          });
          yield* sync$1(() => {
            if (termination === "SIGKILL") child.kill("SIGKILL");
            else child.send("exit");
          });
          const result = yield* runtime.events.pipe(runDrain, exit$3, timeout("3 seconds"));
          if (!isFailure(result) || !pretty(result.cause).includes("ProviderAdapterEventStreamError")) {
            throw new Error(`Codex session did not report ${termination} to its session manager`);
          }
          const expected = termination === "SIGKILL" ? "SIGKILL" : "exited with code 17";
          if (!pretty(result.cause).includes(expected)) {
            throw new Error(`Codex session lost the ${termination} termination cause`);
          }
        }),
      ).pipe(timeout("8 seconds")),
    );
    console.log(`Codex session reports ${termination} and preserves its termination cause`);
  }
}
