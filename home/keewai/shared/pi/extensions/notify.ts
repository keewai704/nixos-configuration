import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	pi.on("agent_settled", (_event, ctx) => {
		if (
			ctx.mode !== "tui" ||
			!ctx.isIdle() ||
			!process.stdout.isTTY ||
			!process.env.KITTY_WINDOW_ID
		) {
			return;
		}

		process.stdout.write(
			"\x1b]99;i=pi-ready:d=0;Pi\x1b\\" +
				"\x1b]99;i=pi-ready:p=body;Ready for input\x1b\\",
		);
	});
}
