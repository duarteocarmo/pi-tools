import {
	CustomEditor,
	type ExtensionAPI,
	type ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { sliceByColumn, stripTerminalSequences, visibleWidth } from "@earendil-works/pi-tui";
import { spawn, type ChildProcess } from "node:child_process";

type EditorFactory = NonNullable<ReturnType<ExtensionContext["ui"]["getEditorComponent"]>>;

export default function noSleepExtension(pi: ExtensionAPI): void {
	let caffeinate: ChildProcess | undefined;
	let editorFactory: EditorFactory | undefined;
	let previousEditorFactory: EditorFactory | undefined;
	let requestEditorRender: (() => void) | undefined;

	function stop(): void {
		const child = caffeinate;
		caffeinate = undefined;
		requestEditorRender?.();
		if (child && child.exitCode === null && child.signalCode === null) {
			child.kill();
		}
	}

	function start({ ctx }: { ctx: ExtensionContext }): void {
		if (process.platform !== "darwin") {
			ctx.ui.notify("No Sleep requires macOS.", "error");
			return;
		}

		const child = spawn("caffeinate", ["-d", "-w", String(process.pid)], {
			stdio: "ignore",
		});
		child.unref();
		caffeinate = child;

		child.once("spawn", () => {
			if (caffeinate !== child) return;
			requestEditorRender?.();
			ctx.ui.notify("No Sleep on ☕.", "info");
		});

		child.once("error", (error) => {
			if (caffeinate !== child) return;
			caffeinate = undefined;
			requestEditorRender?.();
			ctx.ui.notify(`No Sleep failed: ${error.message}`, "error");
		});

		child.once("exit", (code, signal) => {
			if (caffeinate !== child) return;
			caffeinate = undefined;
			requestEditorRender?.();
			ctx.ui.notify(`No Sleep stopped unexpectedly (${code ?? signal ?? "unknown"}).`, "warning");
		});
	}

	pi.on("session_start", (_event, ctx) => {
		ctx.ui.setStatus("no-sleep", undefined);
		previousEditorFactory = ctx.ui.getEditorComponent();
		editorFactory = (tui, theme, keybindings) => {
			const editor = previousEditorFactory?.(tui, theme, keybindings) ?? new CustomEditor(tui, theme, keybindings);
			const render = editor.render.bind(editor);
			const borderColor =
				(editor as { borderColor?: (text: string) => string }).borderColor ?? theme.borderColor;
			requestEditorRender = () => tui.requestRender();

			editor.render = (width) => {
				const lines = render(width);
				if (!caffeinate || lines.length === 0) return lines;

				const topBorder = stripTerminalSequences(lines[0] ?? "");
				const trailingBorder = topBorder.match(/─+$/)?.[0];
				if (!trailingBorder) return lines;

				const label = width >= 20 ? " ☕ no sleep " : " ☕ ";
				const contentWidth = Math.max(2, visibleWidth(topBorder) - trailingBorder.length);
				const left = sliceByColumn(lines[0] ?? "", 0, contentWidth, true);
				const remaining = width - visibleWidth(left) - visibleWidth(label);
				if (remaining < 1) return lines;

				lines[0] = left + ctx.ui.theme.fg("dim", label) + borderColor("─".repeat(remaining));
				return lines;
			};
			return editor;
		};
		ctx.ui.setEditorComponent(editorFactory);
	});

	pi.on("session_shutdown", (_event, ctx) => {
		stop();
		if (ctx.ui.getEditorComponent() === editorFactory) {
			ctx.ui.setEditorComponent(previousEditorFactory);
		}
		requestEditorRender = undefined;
	});

	pi.registerCommand("no-sleep", {
		description: "Toggle macOS display sleep prevention",
		handler: async (_args, ctx) => {
			if (!caffeinate) {
				start({ ctx });
				return;
			}

			stop();
			ctx.ui.notify("No Sleep off.", "info");
		},
	});
}
