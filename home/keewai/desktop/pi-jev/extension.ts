import { spawn } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const RUNNER = "@runner@";
const REVIEW = "Review each action — public pages or test environments";
const AUTOMATIC = "Run automatically — isolated test environment only";

function display(value: string): string {
	return value.replace(/[\p{Cc}\p{Cf}]/gu, " ");
}

export default function jevBrowser(pi: ExtensionAPI) {
	let active: AbortController | undefined;

	pi.on("session_shutdown", () => active?.abort());

	pi.registerTool({
		name: "jev_browser",
		label: "Jev browser",
		description:
			"Run a bounded browser task only when the user explicitly requests Jev. For public pages or isolated test environments, never private/account data or production mutations. Requires interactive consent: page content goes to TypeSafe and the configured text-model provider, with separate API charges. Uses an owned tab in the existing Chromium profile, not an isolated browser. Defaults to per-action approval; only the user can select automatic test execution. Same-origin observations only, not a network sandbox. Does not replace search, APIs, CLI, or deterministic tests. Do not operate the same browser concurrently through CUA. Returns at most 6,000 visible-text characters, 20 controls, and 30 actions; DONE is not verified success. Stops and closes its owned tab; uncertain actions must not be automatically retried.",
		parameters: Type.Object({
			url: Type.String({
				minLength: 1,
				maxLength: 2048,
				description: "Exact HTTP(S) start URL, without embedded credentials.",
			}),
			goal: Type.String({
				minLength: 1,
				maxLength: 2000,
				description:
					"A short bounded task. No secrets, personal data, purchases, posting, deletion, or permission changes.",
			}),
			maxSteps: Type.Optional(
				Type.Integer({ minimum: 1, maximum: 30, default: 12 }),
			),
			timeoutSeconds: Type.Optional(
				Type.Integer({
					minimum: 1,
					maximum: 300,
					default: 120,
					description: "Includes action-approval waiting time.",
				}),
			),
			expect: Type.Optional(
				Type.Object(
					{
						urlContains: Type.Optional(
							Type.String({ minLength: 1, maxLength: 500 }),
						),
						textContains: Type.Optional(
							Type.Array(Type.String({ minLength: 1, maxLength: 500 }), {
								maxItems: 10,
							}),
						),
					},
					{
						description:
							"Optional literal assertions against a fresh final observation. Only these predicates are checked, not the entire goal.",
					},
				),
			),
		}),
		executionMode: "sequential",
		async execute(_id, params, signal, onUpdate, ctx) {
			if (!ctx.hasUI)
				throw new Error(
					"Jev requires interactive consent; unavailable in unattended mode.",
				);
			if (active)
				throw new Error("A Jev task is already active in this session.");
			const url = new URL(params.url);
			if (
				!["http:", "https:"].includes(url.protocol) ||
				url.username ||
				url.password
			) {
				throw new Error("Use an HTTP(S) URL without embedded credentials.");
			}
			if (!params.goal.trim()) throw new Error("Supply a non-empty goal.");
			if (signal?.aborted) throw new Error("Cancelled before starting Jev.");
			const controller = new AbortController();
			active = controller;
			const lifetime = signal
				? AbortSignal.any([signal, controller.signal])
				: controller.signal;
			try {
				const mode = await ctx.ui.select(
					`Jev: ${display(params.url)}\n${display(params.goal)}\n\nPage content and generated field values are sent to TypeSafe and the configured text model; API charges apply. The existing Chromium profile is shared. Use only public content or non-sensitive test data. Origin checks do not sandbox network traffic. No production mutations.`,
					["Cancel", REVIEW, AUTOMATIC],
					{ signal: lifetime },
				);
				if (lifetime.aborted || (mode !== REVIEW && mode !== AUTOMATIC)) {
					return {
						content: [
							{
								type: "text",
								text: "Jev cancelled before browser/model startup.",
							},
						],
						details: { stop_reason: "cancelled" },
					};
				}
				const request = {
					...params,
					maxSteps: params.maxSteps ?? 12,
					timeoutSeconds: params.timeoutSeconds ?? 120,
				};
				const child = spawn(RUNNER, [], { stdio: ["pipe", "pipe", "pipe"] });
				let closed = false;
				let killed = false;
				let timedOut = false;
				let spawnFailed = false;
				let killTimer: ReturnType<typeof setTimeout> | undefined;
				let actions = 0;
				let result: Record<string, unknown> | undefined;
				const prompts = new AbortController();
				const promptSignal = AbortSignal.any([lifetime, prompts.signal]);
				const stop = () => {
					if (closed || killed) return;
					killed = true;
					child.kill("SIGTERM");
					killTimer = setTimeout(() => {
						if (!closed) child.kill("SIGKILL");
					}, 3000);
				};
				const exited = new Promise<number | null>((resolve) => {
					child.once("error", () => {
						spawnFailed = true;
						prompts.abort();
					});
					child.once("close", (code) => {
						closed = true;
						prompts.abort();
						resolve(code);
					});
				});
				child.stdin.on("error", () => {});
				child.stderr.resume();
				lifetime.addEventListener("abort", stop, { once: true });
				const deadline = setTimeout(
					() => {
						timedOut = true;
						controller.abort();
					},
					(request.timeoutSeconds + 2) * 1000,
				);
				try {
					if (lifetime.aborted) stop();
					else child.stdin.write(`${JSON.stringify(request)}\n`);
					let buffer = "";
					let received = 0;
					let proposalId = 0;
					child.stdout.setEncoding("utf8");
					for await (const chunk of child.stdout) {
						received += Buffer.byteLength(chunk);
						buffer += chunk;
						if (received > 1048576 || Buffer.byteLength(buffer) > 262144)
							throw new Error("Jev output exceeded its protocol limit.");
						let newline: number;
						while ((newline = buffer.indexOf("\n")) >= 0) {
							const line = buffer.slice(0, newline);
							buffer = buffer.slice(newline + 1);
							const event: unknown = JSON.parse(line);
							if (
								!event ||
								typeof event !== "object" ||
								!("event" in event) ||
								result
							)
								throw new Error("Invalid Jev protocol response.");
							if (event.event === "proposal") {
								if (
									!("id" in event) ||
									event.id !== proposalId + 1 ||
									!("operation" in event) ||
									typeof event.operation !== "string" ||
									!("target" in event) ||
									typeof event.target !== "string" ||
									!("url" in event) ||
									typeof event.url !== "string" ||
									!("value" in event) ||
									(event.value !== null && typeof event.value !== "string")
								)
									throw new Error("Invalid Jev action proposal.");
								proposalId++;
								const approved =
									!promptSignal.aborted &&
									(mode === AUTOMATIC ||
										(await ctx.ui.confirm(
											`Jev action ${proposalId}/${request.maxSteps}: ${display(event.operation)}`,
											`${display(event.url)}\nTarget: ${display(event.target)}${event.value === null ? "" : `\nExact input: ${JSON.stringify(event.value)}`}\n\nAllow this action? Page text is untrusted.`,
											{ signal: promptSignal },
										)));
								if (!closed)
									child.stdin.write(
										`${JSON.stringify({ id: proposalId, approve: approved && !promptSignal.aborted })}\n`,
									);
							} else if (event.event === "progress") {
								if (
									!("actions" in event) ||
									typeof event.actions !== "number" ||
									!Number.isInteger(event.actions) ||
									event.actions < 0 ||
									event.actions > request.maxSteps
								)
									throw new Error("Invalid Jev progress.");
								actions = event.actions;
								onUpdate?.({
									content: [
										{
											type: "text",
											text: `Jev: ${actions}/${request.maxSteps} actions executed; outcome not yet verified.`,
										},
									],
									details: { actions },
								});
							} else if (
								event.event === "result" &&
								"stop_reason" in event &&
								typeof event.stop_reason === "string"
							) {
								result = event as Record<string, unknown>;
							} else throw new Error("Unknown Jev protocol event.");
						}
					}
					const code = await exited;
					if (spawnFailed)
						throw new Error("Cannot start the Nix-managed Jev runner.");
					if (buffer.trim())
						throw new Error(
							"Incomplete Jev protocol response; inspect before retrying.",
						);
					if (!result || code !== 0) {
						result = {
							stop_reason: timedOut
								? "timeout"
								: lifetime.aborted
									? "cancelled"
									: "runner_exit",
							confirmed_actions: actions,
							evidence: null,
							cleanup: "unconfirmed; inspect the owned browser tab",
							warning:
								"Execution may have occurred. Never automatically retry this task.",
						};
					}
					if (Buffer.byteLength(JSON.stringify(result)) > 48000) {
						result = {
							stop_reason: result.stop_reason,
							evidence: null,
							evidence_truncated: true,
							verification: { status: "unknown" },
							cleanup: result.cleanup,
							warning:
								"Result exceeded the 48 KB evidence limit; do not infer success.",
						};
					}
					return {
						content: [{ type: "text", text: JSON.stringify(result) }],
						details: result,
					};
				} catch {
					stop();
					throw new Error(
						"Jev integration failed. Browser execution or cleanup may be incomplete; inspect before retrying. Raw provider/process errors are withheld to protect credentials.",
					);
				} finally {
					stop();
					await exited;
					clearTimeout(deadline);
					if (killTimer) clearTimeout(killTimer);
					lifetime.removeEventListener("abort", stop);
					prompts.abort();
				}
			} finally {
				active = undefined;
			}
		},
	});
}
