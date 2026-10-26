import { homedir } from "node:os";
import { createInterface } from "node:readline";

export async function withAppServer(ctx, executable, parentSignal, operation) {
  const signal = AbortSignal.any([parentSignal, AbortSignal.timeout(20_000)]);
  signal.throwIfAborted();
  const child = ctx.subprocess.spawn({
    argv: [executable, "app-server"],
    cwd: homedir(),
    env: {},
    stdio: { stdin: "pipe", stdout: "pipe", stderr: { maxBytes: 16_384 } },
    graceMs: 3_000,
    signal,
  });
  const pending = new Map();
  let nextId = 1;
  let failure;
  const rejectPending = (error) => {
    failure = error;
    for (const waiter of pending.values()) waiter.reject(error);
    pending.clear();
  };
  const lines = createInterface({ input: child.stdout, crlfDelay: Infinity });
  const reading = (async () => {
    try {
      for await (const line of lines) {
        if (!line.trim()) continue;
        if (line.length > 8 * 1024 * 1024) throw new Error("Codex control response exceeded its size limit");
        const message = JSON.parse(line);
        const waiter = pending.get(message.id);
        if (!waiter) continue;
        pending.delete(message.id);
        if (message.error) waiter.reject(new Error(`Codex control request failed (${message.error.code})`));
        else waiter.resolve(message.result);
      }
    } catch (error) {
      rejectPending(error);
    } finally {
      rejectPending(new Error("Codex control connection closed"));
    }
  })();
  const abort = () => rejectPending(signal.reason);
  signal.addEventListener("abort", abort, { once: true });
  const write = (message) => child.stdin.write(`${JSON.stringify(message)}\n`);
  const client = {
    request(method, params = {}) {
      if (failure) return Promise.reject(failure);
      const id = nextId++;
      return new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
        write({ id, method, params });
      });
    },
  };
  try {
    await client.request("initialize", {
      clientInfo: { name: "dsh-chatgpt-subscription", version: "0.1.0" },
      capabilities: { experimentalApi: true },
    });
    write({ method: "initialized", params: {} });
    const account = await client.request("account/read", { refreshToken: false });
    if (account.account?.type !== "chatgpt") throw new Error("Sign in to the Codex CLI with ChatGPT to use this provider");
    return await operation(client, account.account);
  } finally {
    signal.removeEventListener("abort", abort);
    child.stdin.end();
    child.terminate();
    try {
      if (!await child.waitForExit(AbortSignal.timeout(6_000))) throw new Error("Codex control process did not exit");
    } finally {
      lines.close();
      await reading;
    }
  }
}
