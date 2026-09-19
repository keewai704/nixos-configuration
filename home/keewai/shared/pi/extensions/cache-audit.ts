import { createHash } from "node:crypto";
import {
	DynamicBorder,
	type ExtensionAPI,
	type ExtensionCommandContext,
	type SessionEntry,
	type ThemeColor,
} from "@earendil-works/pi-coding-agent";
import { matchesKey, Text, truncateToWidth } from "@earendil-works/pi-tui";

const requestFields = {
	model: "モデル",
	prompt_cache_key: "キャッシュキー",
	service_tier: "サービス階層",
	instructions: "指示",
	tools: "ツール定義",
	reasoning: "推論設定",
	text: "テキスト設定",
	parallel_tool_calls: "並列ツール",
} as const;

type RequestField = keyof typeof requestFields;
type Tokens = { input: number; cacheRead: number; cacheWrite: number };
type Totals = Tokens & { samples: number };
type ReportLine = { text: string; color?: ThemeColor };

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isTokenCount(value: unknown): value is number {
	return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

function readTokens(value: unknown): Tokens | undefined {
	if (
		!isRecord(value) ||
		!isTokenCount(value.input) ||
		!isTokenCount(value.cacheRead) ||
		!isTokenCount(value.cacheWrite)
	)
		return;
	return {
		input: value.input,
		cacheRead: value.cacheRead,
		cacheWrite: value.cacheWrite,
	};
}

function readNativeTokens(details: unknown): Tokens | undefined {
	if (
		!isRecord(details) ||
		details.strategy !== "openai-responses-compaction-v2" ||
		!isRecord(details.usage)
	)
		return;
	const { inputTokens, cachedInputTokens, cacheWriteInputTokens } =
		details.usage;
	if (
		!isTokenCount(inputTokens) ||
		!isTokenCount(cachedInputTokens) ||
		!isTokenCount(cacheWriteInputTokens) ||
		cachedInputTokens + cacheWriteInputTokens > inputTokens
	)
		return;
	return {
		input: inputTokens - cachedInputTokens - cacheWriteInputTokens,
		cacheRead: cachedInputTokens,
		cacheWrite: cacheWriteInputTokens,
	};
}

function totalInput(tokens: Tokens): number {
	return tokens.input + tokens.cacheRead + tokens.cacheWrite;
}

function emptyTotals(): Totals {
	return { input: 0, cacheRead: 0, cacheWrite: 0, samples: 0 };
}

function addUsage(target: Totals, tokens: Tokens | undefined): void {
	if (!tokens || totalInput(tokens) === 0) return;
	target.input += tokens.input;
	target.cacheRead += tokens.cacheRead;
	target.cacheWrite += tokens.cacheWrite;
	target.samples++;
}

function summarizeBranch(entries: SessionEntry[]) {
	const groups = {
		応答: emptyTotals(),
		ツール内呼び出し: emptyTotals(),
		Pi要約: emptyTotals(),
		"Remote圧縮 V2": emptyTotals(),
	};
	let latest: { model: string; tokens: Tokens | undefined } | undefined;
	for (const entry of entries) {
		if (entry.type === "message") {
			const message = entry.message;
			if (message.role === "assistant") {
				const tokens = readTokens(message.usage);
				latest = { model: `${message.provider}/${message.model}`, tokens };
				addUsage(groups.応答, tokens);
			} else if (message.role === "toolResult") {
				addUsage(groups.ツール内呼び出し, readTokens(message.usage));
			}
		} else if (entry.type === "compaction") {
			addUsage(groups.Pi要約, readTokens(entry.usage));
			addUsage(groups["Remote圧縮 V2"], readNativeTokens(entry.details));
		} else if (entry.type === "branch_summary") {
			addUsage(groups.Pi要約, readTokens(entry.usage));
		}
	}
	const total = emptyTotals();
	for (const group of Object.values(groups)) {
		total.input += group.input;
		total.cacheRead += group.cacheRead;
		total.cacheWrite += group.cacheWrite;
		total.samples += group.samples;
	}
	return { groups, total, latest };
}

function count(value: number): string {
	return value.toLocaleString("en-US");
}

function rate(tokens: Tokens | undefined): string {
	return tokens && totalInput(tokens) > 0
		? `${((100 * tokens.cacheRead) / totalInput(tokens)).toFixed(1)}%`
		: "未計測";
}

function bar(tokens: Tokens): string {
	if (totalInput(tokens) === 0) return "入力使用量の報告を待っています";
	const filled = Math.round((20 * tokens.cacheRead) / totalInput(tokens));
	return `${"█".repeat(filled)}${"░".repeat(20 - filled)}`;
}

function fieldNames(fields: RequestField[]): string {
	return fields.map((field) => requestFields[field]).join("・");
}

async function showReport(ctx: ExtensionCommandContext, lines: ReportLine[]) {
	if (ctx.mode !== "tui") {
		const text = lines.map((line) => line.text).join("\n");
		if (ctx.hasUI) ctx.ui.notify(text, "info");
		else
			console.log(
				ctx.mode === "json"
					? JSON.stringify({ type: "cache_report", text })
					: text,
			);
		return;
	}
	await ctx.ui.custom<void>(
		(tui, theme, _keybindings, done) => {
			let offset = 0;
			let pageSize = 1;
			let maxOffset = 0;
			const border = new DynamicBorder((text: string) =>
				theme.fg("borderAccent", text),
			);
			return {
				render(width: number) {
					const body = new Text(
						lines
							.map((line) => theme.fg(line.color ?? "text", line.text))
							.join("\n"),
						1,
						0,
					).render(width);
					pageSize = Math.max(1, Math.min(22, tui.terminal.rows - 6));
					maxOffset = Math.max(0, body.length - pageSize);
					offset = Math.min(offset, maxOffset);
					const position = `${offset + 1}–${Math.min(offset + pageSize, body.length)}/${body.length}`;
					const help = "Esc / Enter 閉じる · ↑↓ / PgUp PgDn スクロール";
					return [
						...border.render(width),
						...body.slice(offset, offset + pageSize),
						theme.fg("dim", truncateToWidth(` ${help} · ${position}`, width)),
						...border.render(width),
					];
				},
				invalidate() {
					border.invalidate();
				},
				handleInput(data: string) {
					if (
						matchesKey(data, "escape") ||
						matchesKey(data, "enter") ||
						matchesKey(data, "ctrl+c")
					) {
						done();
						return;
					}
					if (matchesKey(data, "up")) offset--;
					else if (matchesKey(data, "down")) offset++;
					else if (matchesKey(data, "pageUp")) offset -= pageSize;
					else if (matchesKey(data, "pageDown")) offset += pageSize;
					else if (matchesKey(data, "home")) offset = 0;
					else if (matchesKey(data, "end")) offset = maxOffset;
					offset = Math.max(0, Math.min(offset, maxOffset));
					tui.requestRender();
				},
			};
		},
		{ overlay: true, overlayOptions: { width: 78, margin: 1 } },
	);
}

export default function cacheAudit(pi: ExtensionAPI) {
	let previousFingerprints: Map<string, string> | undefined;
	let lastChangedFields: RequestField[] = [];
	let latestChangedFields: RequestField[] = [];
	let configurationChanges = 0;
	let observations = 0;

	pi.on("session_start", () => {
		previousFingerprints = undefined;
		lastChangedFields = [];
		latestChangedFields = [];
		configurationChanges = 0;
		observations = 0;
	});

	pi.on("before_provider_request", (event, ctx) => {
		if (
			ctx.model?.provider !== "openai-codex" ||
			ctx.model.id !== "gpt-6-astra" ||
			!isRecord(event.payload)
		)
			return;
		const fingerprints = new Map<string, string>();
		const fields = Object.keys(requestFields) as RequestField[];
		for (const field of fields) {
			fingerprints.set(
				field,
				createHash("sha256")
					.update(JSON.stringify(event.payload[field]) ?? "undefined")
					.digest("hex"),
			);
		}
		const previous = previousFingerprints;
		latestChangedFields = previous
			? fields.filter(
					(field) => previous.get(field) !== fingerprints.get(field),
				)
			: [];
		observations++;
		if (latestChangedFields.length > 0) {
			configurationChanges++;
			lastChangedFields = latestChangedFields;
			if (ctx.hasUI) {
				ctx.ui.notify(
					`Astra要求設定の変更: ${fieldNames(latestChangedFields)}。/cache で確認できます。`,
					"info",
				);
			}
		}
		previousFingerprints = fingerprints;
	});

	pi.registerCommand("cache", {
		description:
			"キャッシュの直近・累計・Remote圧縮の内訳と要求設定の変化を表示",
		handler: async (_args, ctx) => {
			const { groups, total, latest } = summarizeBranch(
				ctx.sessionManager.getBranch(),
			);
			const latestStatus =
				observations === 0
					? "まだ要求を観測していません"
					: observations === 1
						? "初回の比較基準を記録しました"
						: latestChangedFields.length > 0
							? `前回から変更: ${fieldNames(latestChangedFields)}`
							: "前回との設定差分なし";
			await showReport(ctx, [
				{ text: "CACHE · キャッシュ再利用", color: "accent" },
				{ text: "" },
				{ text: `直近応答  ${rate(latest?.tokens)}`, color: "accent" },
				{ text: latest?.model ?? "まだ応答がありません", color: "muted" },
				...(latest?.tokens && totalInput(latest.tokens) > 0
					? [
							{
								text: `再利用 ${count(latest.tokens.cacheRead)} / 入力 ${count(totalInput(latest.tokens))} tokens`,
							},
						]
					: []),
				{ text: "" },
				{
					text: `ブランチ累計  ${rate(total)}  ${bar(total)}`,
					color: "accent",
				},
				{
					text: `入力合計 ${count(totalInput(total))} tokens · 入力計測 ${count(total.samples)}件`,
				},
				{ text: `再利用       ${count(total.cacheRead)} tokens` },
				{ text: `新規書き込み ${count(total.cacheWrite)} tokens` },
				{ text: `未キャッシュ ${count(total.input)} tokens` },
				{ text: "" },
				{ text: "使用量の内訳 · 入力加重の再利用率", color: "accent" },
				...Object.entries(groups).map(([name, group]) => ({
					text: `${name}: ${rate(group)} · 入力 ${count(totalInput(group))} · ${count(group.samples)}件`,
				})),
				{ text: "" },
				{ text: "Astra要求の設定監視 · 今回の読み込み以降", color: "accent" },
				{
					text: `観測 ${count(observations)}件 / 設定変更 ${count(configurationChanges)}回`,
				},
				{
					text: latestStatus,
					color: latestChangedFields.length > 0 ? "warning" : "muted",
				},
				...(lastChangedFields.length > 0
					? [
							{
								text: `最後に変化した項目: ${fieldNames(lastChangedFields)}`,
								color: "muted" as const,
							},
						]
					: []),
				{ text: "" },
				{
					text: "累計は選択ブランチの全モデル・圧縮前も含む報告済み使用量です。",
					color: "dim",
				},
				{
					text: "再利用率 = cache read ÷ (uncached + cache read + cache write)。",
					color: "dim",
				},
				{
					text: "設定差分はミス原因の確定ではありません。会話・期限・サーバー割当は判定しません。",
					color: "dim",
				},
				{ text: "ChatGPTの残り利用枠・実請求額ではありません。", color: "dim" },
			]);
		},
	});
}
