import { homedir } from "node:os";
import { basename } from "node:path";
import {
	DynamicBorder,
	type ExtensionCommandContext,
	type Theme,
} from "@earendil-works/pi-coding-agent";
import { Container, type SelectItem, SelectList, Text, truncateToWidth } from "@earendil-works/pi-tui";
import { cleanTerminalText } from "./activity.ts";
import type { DisplaySession, DisplayStatus } from "./registry.ts";

const STATUS_GLYPH: Record<DisplayStatus, string> = {
	running: "●",
	idle: "●",
	stale: "○",
	failed: "×",
};

const STATUS_COLOR: Record<DisplayStatus, "accent" | "success" | "dim" | "error"> = {
	running: "accent",
	idle: "success",
	stale: "dim",
	failed: "error",
};

function countStatuses({ sessions }: { sessions: DisplaySession[] }): Record<DisplayStatus, number> {
	const counts: Record<DisplayStatus, number> = { running: 0, idle: 0, stale: 0, failed: 0 };
	for (const session of sessions) counts[session.displayStatus]++;
	return counts;
}

function sessionName({ session }: { session: DisplaySession }): string {
	return cleanTerminalText({ text: session.name || basename(session.cwd) || `Pi ${session.pid}` });
}

function compactPath({ path }: { path: string }): string {
	const homeDirectory = homedir();
	return path.startsWith(`${homeDirectory}/`) ? `~/${path.slice(homeDirectory.length + 1)}` : path;
}

function tmuxLocation({ session }: { session: DisplaySession }): string {
	if (!session.tmux) return "direct · no jump";
	return `${session.tmux.session}:${session.tmux.window} ${session.tmux.pane}`;
}

function descriptionFor({ session }: { session: DisplaySession }): string {
	const command = cleanTerminalText({ text: session.lastCommand || "—" });
	return `Pi: ${command} · ${compactPath({ path: session.cwd })} · ${tmuxLocation({ session })}`;
}

function sortedSessions({
	sessions,
	currentPid,
}: {
	sessions: DisplaySession[];
	currentPid: number;
}): DisplaySession[] {
	const rank: Record<DisplayStatus, number> = { running: 0, failed: 1, idle: 2, stale: 3 };
	return [...sessions].sort((left, right) => {
		if (left.pid === currentPid) return -1;
		if (right.pid === currentPid) return 1;
		return rank[left.displayStatus] - rank[right.displayStatus] || right.updatedAt - left.updatedAt;
	});
}

export function renderSessionWidget({
	sessions,
	theme,
	width,
}: {
	sessions: DisplaySession[];
	theme: Theme;
	width: number;
}): string[] {
	const counts = countStatuses({ sessions });
	const total = sessions.length;
	const parts = [
		theme.fg("accent", "π"),
		theme.fg("text", `${total} ${total === 1 ? "session" : "sessions"}`),
		theme.fg("accent", `● ${counts.running} running`),
		theme.fg("success", `● ${counts.idle} idle`),
	];
	if (counts.stale) parts.push(theme.fg("dim", `○ ${counts.stale} stale`));
	if (counts.failed) parts.push(theme.fg("error", `× ${counts.failed} failed`));
	return [truncateToWidth(parts.join(theme.fg("dim", " · ")), width, "…")];
}

export async function showJumper({
	ctx,
	sessions,
	currentPid,
}: {
	ctx: ExtensionCommandContext;
	sessions: DisplaySession[];
	currentPid: number;
}): Promise<number | null> {
	return ctx.ui.custom<number | null>(
		(tui, theme, keybindings, done) => {
			const ordered = sortedSessions({ sessions, currentPid });
			const items: SelectItem[] = ordered.map((session) => {
				const status = session.displayStatus;
				const current = session.pid === currentPid ? theme.fg("muted", " ←") : "";
				const prompt = cleanTerminalText({ text: session.lastUserPrompt || "—" });
				return {
					value: String(session.pid),
					label: `${theme.fg(STATUS_COLOR[status], STATUS_GLYPH[status])} ${sessionName({ session })}${current} ${theme.fg("muted", `“${prompt}”`)}`,
					description: descriptionFor({ session }),
				};
			});

			const counts = countStatuses({ sessions });
			const container = new Container();
			container.addChild(new DynamicBorder((text: string) => theme.fg("borderAccent", text)));
			container.addChild(
				new Text(
					theme.fg("accent", theme.bold("Pi Jumper")) +
						theme.fg("muted", `  ${sessions.length} sessions · ${counts.running} running · ${counts.idle} idle`),
					1,
					0,
				),
			);
			const list = new SelectList(
				items,
				Math.min(items.length, 10),
				{
					selectedPrefix: (text) => theme.fg("accent", text),
					selectedText: (text) => theme.fg("accent", text),
					description: (text) => theme.fg("muted", text),
					scrollInfo: (text) => theme.fg("dim", text),
					noMatch: (text) => theme.fg("warning", text),
				},
				{ maxPrimaryColumnWidth: 50 },
			);
			let selectedIndex = 0;
			list.onSelect = (item) => done(Number(item.value));
			list.onCancel = () => done(null);
			container.addChild(list);
			container.addChild(new Text(theme.fg("dim", "k/↑ previous · j/↓ next · enter jump · esc close"), 1, 0));
			container.addChild(new DynamicBorder((text: string) => theme.fg("borderAccent", text)));

			return {
				render: (width: number) => container.render(width),
				invalidate: () => container.invalidate(),
				handleInput: (data: string) => {
					if (data === "k" || keybindings.matches(data, "tui.select.up")) {
						selectedIndex = selectedIndex === 0 ? items.length - 1 : selectedIndex - 1;
						list.setSelectedIndex(selectedIndex);
					} else if (data === "j" || keybindings.matches(data, "tui.select.down")) {
						selectedIndex = selectedIndex === items.length - 1 ? 0 : selectedIndex + 1;
						list.setSelectedIndex(selectedIndex);
					} else {
						list.handleInput(data);
					}
					tui.requestRender();
				},
			};
		},
		{
			overlay: true,
			overlayOptions: { anchor: "center", width: "80%", minWidth: 60, maxHeight: "80%", margin: 1 },
			onHandle: (handle) => handle.focus(),
		},
	);
}
