import { createHash } from "node:crypto";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const requestFields = [
	"model",
	"prompt_cache_key",
	"service_tier",
	"instructions",
	"tools",
	"reasoning",
	"text",
	"parallel_tool_calls",
] as const;

export default function cacheAudit(pi: ExtensionAPI) {
	let previousFingerprints: Map<string, string> | undefined;
	let lastChangedFields: string[] = [];
	let configurationChanges = 0;

	pi.on("session_start", () => {
		previousFingerprints = undefined;
		lastChangedFields = [];
		configurationChanges = 0;
	});

	pi.on("before_provider_request", (event, ctx) => {
		if (
			ctx.model?.provider !== "openai-codex" ||
			ctx.model.id !== "gpt-6-astra"
		)
			return;
		const payload = event.payload as Record<string, unknown>;
		const fingerprints = new Map<string, string>();
		for (const field of requestFields) {
			fingerprints.set(
				field,
				createHash("sha256")
					.update(JSON.stringify(payload[field]) ?? "undefined")
					.digest("hex"),
			);
		}
		const previous = previousFingerprints;
		const changedFields = previous
			? requestFields.filter(
					(field) => previous.get(field) !== fingerprints.get(field),
				)
			: [];

		if (changedFields.length > 0) {
			configurationChanges++;
			lastChangedFields = changedFields;
			if (ctx.hasUI) {
				ctx.ui.notify(
					`Astra要求設定の変更: ${changedFields.join(", ")}。キャッシュ再利用が減る場合があります。`,
					"info",
				);
			}
		}
		previousFingerprints = fingerprints;
	});

	pi.registerCommand("cache", {
		description: "選択ブランチのキャッシュ再利用率と要求設定の変化を表示",
		handler: async (_args, ctx) => {
			let input = 0;
			let cacheRead = 0;
			let cacheWrite = 0;
			for (const entry of ctx.sessionManager.getBranch()) {
				let usage;
				if (entry.type === "message") {
					if (
						entry.message.role === "assistant" ||
						entry.message.role === "toolResult"
					) {
						usage = entry.message.usage;
					}
				} else if (
					entry.type === "compaction" ||
					entry.type === "branch_summary"
				) {
					usage = entry.usage;
				}
				if (!usage) continue;
				input += usage.input;
				cacheRead += usage.cacheRead;
				cacheWrite += usage.cacheWrite;
			}
			const total = input + cacheRead + cacheWrite;
			const rate =
				total > 0 ? `${((100 * cacheRead) / total).toFixed(1)}%` : "未計測";
			if (ctx.hasUI) {
				ctx.ui.notify(
					[
						`選択ブランチの入力トークン加重キャッシュ率: ${rate}`,
						`cache read: ${cacheRead.toLocaleString()} / write: ${cacheWrite.toLocaleString()} / uncached: ${input.toLocaleString()}`,
						`このセッション読込以降のAstra要求設定の変更: ${configurationChanges}回`,
						`直近の変更項目: ${lastChangedFields.join(", ") || "なし"}`,
						"指示・ツール・推論設定・キャッシュキーなどを比較しています。会話本文、期限切れ、サーバーの割り当ては判定しません。",
						"ChatGPT契約の実請求額や残り利用枠を表す数値ではありません。",
					].join("\n"),
					"info",
				);
			}
		},
	});
}
