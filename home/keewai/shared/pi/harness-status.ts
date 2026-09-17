import { readFile } from "node:fs/promises";
import { join } from "node:path";
import {
	getAgentDir,
	type ExtensionAPI,
	VERSION,
} from "@earendil-works/pi-coding-agent";

function asObject(value: unknown): Record<string, unknown> | undefined {
	return value !== null && typeof value === "object" && !Array.isArray(value)
		? (value as Record<string, unknown>)
		: undefined;
}

async function readConfig(path: string) {
	try {
		return asObject(JSON.parse(await readFile(path, "utf8")));
	} catch {
		return undefined;
	}
}

function label(value: unknown): string {
	if (typeof value !== "string" || !value.trim()) return "不明";
	const text = value.replace(/[\u0000-\u001f\u007f]/g, " ");
	return text.length > 160 ? `${text.slice(0, 160)}…` : text;
}

export default function harnessStatus(pi: ExtensionAPI) {
	pi.registerCommand("harness-status", {
		description:
			"Show active Pi capabilities and compare saved global settings",
		handler: async (_args, ctx) => {
			const active = new Set(pi.getActiveTools());
			const registered = new Set(pi.getAllTools().map((tool) => tool.name));
			const model = ctx.model;
			const thinking = ctx.thinkingLevel;
			const mode = ctx.mode;
			const trusted = ctx.isProjectTrusted();
			const prompt = ctx.getSystemPrompt();
			const options = ctx.getSystemPromptOptions();
			const hasUI = ctx.hasUI;
			const ui = ctx.ui;
			const agentDir = getAgentDir();
			const [settings, mcp, appendPrompt] = await Promise.all([
				readConfig(join(agentDir, "settings.json")),
				readConfig(join(agentDir, "mcp.json")),
				readFile(join(agentDir, "APPEND_SYSTEM.md"), "utf8").catch(
					() => undefined,
				),
			]);
			const scriptMode = asObject(mcp?.settings)?.scriptMode;
			const scriptConfigured =
				typeof scriptMode === "boolean"
					? scriptMode
						? "有効"
						: "無効"
					: "不明";
			const appendIncluded = appendPrompt?.trim()
				? prompt.includes(appendPrompt.trim())
				: undefined;
			const toolState = (name: string) =>
				active.has(name)
					? "有効"
					: registered.has(name)
						? "登録済み・無効"
						: "未登録";
			const groups = [
				["MCP", ["mcp", "mcpScript"]],
				[
					"Web",
					["web_search", "fetch_content", "get_search_content", "source_check"],
				],
				["LSP", ["lsp_diagnostics", "lsp_fix"]],
				["委任", ["subagent", "bg_wait"]],
			] as const;
			const differences: string[] = [];
			if (
				typeof scriptMode === "boolean" &&
				scriptMode !== active.has("mcpScript")
			) {
				differences.push(
					"mcpScriptの有効状態が保存済みグローバル設定と異なります。",
				);
			}
			if (appendIncluded === false) {
				differences.push(
					"保存済みの追記指示が現在のPiプロンプトに見つかりません。",
				);
			}
			const report = [
				`Pi ${VERSION} / Node ${process.version} / ${mode}`,
				`現在のモデル: ${model ? `${label(model.provider)}/${label(model.id)}` : "未選択"} / 推論: ${label(thinking)}`,
				`保存済みグローバル既定: ${label(settings?.defaultProvider)}/${label(settings?.defaultModel)} / 推論: ${label(settings?.defaultThinkingLevel)}`,
				`現在のプロジェクト信頼: ${trusted ? "有効" : "無効"}`,
				`ツール: 有効 ${active.size} / 登録 ${registered.size}`,
				...groups.map(
					([group, names]) =>
						`${group}: ${names.map((name) => `${name}=${toolState(name)}`).join(", ")}`,
				),
				`コンテキストファイル: ${options.contextFiles?.length ?? 0} / 検出スキル（本文読込数ではない）: ${options.skills?.length ?? 0}`,
				`保存済み追記指示の一致: ${appendIncluded === undefined ? "不明・未設定" : appendIncluded ? "Piプロンプトに含まれる" : "含まれない"}`,
				`保存済みグローバルmcpScript: ${scriptConfigured}`,
				...differences,
				...(differences.length
					? [
							"プロジェクト設定・起動オプション・再読込の有無を確認してください。自動変更は行いません。",
						]
					: []),
				"ツールの有効状態は接続・認証・実行承認の証明ではありません。MCPの状態は /mcp で確認できます。",
			].join("\n");
			if (hasUI) {
				ui.notify(report, differences.length ? "warning" : "info");
			} else {
				process.stderr.write(`${report}\n`);
			}
		},
	});
}
