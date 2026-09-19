import { createHash } from "node:crypto";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function astraCache(pi: ExtensionAPI) {
	pi.on("before_provider_request", (event, ctx) => {
		if (
			ctx.model?.provider !== "openai-codex" ||
			ctx.model.id !== "gpt-6-astra"
		)
			return;
		const digest = createHash("sha256")
			.update(ctx.cwd)
			.update("\0")
			.update(ctx.model.id)
			.digest("hex")
			.slice(0, 48);
		return {
			...(event.payload as Record<string, unknown>),
			prompt_cache_key: `pi-astra-${digest}`,
		};
	});
}
