import { execFile, spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const RUNNER = "@runner@";
const SYSTEMD_RUN = "@systemdRun@";
const SYSTEMCTL = "@systemctl@";
const exec = promisify(execFile);
const REVIEW = "Review each action — public pages or test environments";
const AUTOMATIC = "Run automatically — isolated test environment only";

function display(value: string): string {
	return value.replace(/[\p{Cc}\p{Cf}]/gu, " ");
}

async function closeRunnerScope(unit: string, workspace: string) {
	try {
		await exec(SYSTEMCTL, ["--user", "stop", unit], { timeout: 6000 });
	} catch {
		const { stdout } = await exec(
			SYSTEMCTL,
			[
				"--user",
				"show",
				unit,
				"--property=LoadState",
				"--property=ActiveState",
			],
			{ timeout: 3000 },
		);
		if (!stdout.split("\n").includes("ActiveState=inactive")) {
			throw new Error("The Jev runner scope is still active.");
		}
	}
	await rm(workspace, { recursive: true, force: true });
}

export default function jevBrowser(pi: ExtensionAPI) {
	let active: AbortController | undefined;

	pi.on("session_shutdown", () => active?.abort());

	pi.registerTool({
		name: "jev_browser",
		label: "Jev browser",
		description:
			"Run a bounded browser task only when the user explicitly requests Jev. For public pages or isolated test environments, never private/account data or production mutations. Requires interactive consent: page content goes to TypeSafe and the configured text-model provider, with separate API charges. Starts or reuses normal Brave with its usual profile and no added browser flags. Existing login state is shared. Remote-debugging setup and connection approval must be performed by the user; never change browser preferences automatically. Defaults to per-action approval; only the user can select automatic test execution. Same-origin observations only, not a network sandbox. Does not replace search, APIs, CLI, or deterministic tests. Do not operate the same browser concurrently through CUA. Returns at most 6,000 visible-text characters, 20 controls, and 30 actions; DONE is not verified success. Closes only its owned tab and stops its connection daemon; leaves normal Brave, other tabs, and its profile in place. Uncertain actions must not be automatically retried.",
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
					`Jev: ${display(params.url)}\n${display(params.goal)}\n\nPage content and generated field values are sent to TypeSafe and the configured text model; API charges apply. Normal Brave will be started or reused without extra browser flags. Its usual profile and login state are shared. Only the owned task tab is closed afterward; the browser and profile are preserved. You must approve remote debugging yourself if required. Use only public content or non-sensitive test data. Origin checks do not sandbox network traffic. No production mutations.`,
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
				const workspace = await mkdtemp(join(tmpdir(), "pi-jev-"));
				const unit = `pi-jev-${randomUUID()}.scope`;
				const child = spawn(
					SYSTEMD_RUN,
					[
						"--user",
						"--scope",
						"--quiet",
						"--collect",
						`--unit=${unit}`,
						`--property=RuntimeMaxSec=${request.timeoutSeconds + 8}s`,
						"--property=TimeoutStopSec=3s",
						RUNNER,
						workspace,
					],
					{ stdio: ["pipe", "pipe", "pipe"] },
				);
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
							cleanup:
								"owned-tab cleanup unconfirmed; normal Brave is left running",
							warning:
								"Execution may have occurred. Never automatically retry this task.",
						};
					}
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
					try {
						await closeRunnerScope(unit, workspace);
					} catch {
						throw new Error(
							`Jev runner cleanup could not be confirmed. Inspect ${unit} and ${workspace}; do not automatically retry.`,
						);
					}
				}
				if (!result) throw new Error("Jev returned no result.");
				result.browser_cleanup = "normal_browser_and_profile_preserved";
				result.runner_cleanup = "stopped_and_temporary_files_removed";
				if (Buffer.byteLength(JSON.stringify(result)) > 48000) {
					result = {
						stop_reason: result.stop_reason,
						evidence: null,
						evidence_truncated: true,
						verification: { status: "unknown" },
						cleanup: result.cleanup,
						browser_cleanup: result.browser_cleanup,
						runner_cleanup: result.runner_cleanup,
						warning:
							"Result exceeded the 48 KB evidence limit; do not infer success.",
					};
				}
				return {
					content: [{ type: "text", text: JSON.stringify(result) }],
					details: result,
				};
			} finally {
				active = undefined;
			}
		},
	});
}
