import { homedir } from "node:os";
import { basename } from "node:path";
import type { ExtensionContext, Theme } from "@earendil-works/pi-coding-agent";
import { Container, type SelectItem, SelectList, Text, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { cleanTerminalText } from "./activity.ts";
import type { DisplaySession, DisplayStatus } from "./registry.ts";

const STATUS_GLYPH: Record<DisplayStatus, string> = {
  running: "▶",
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

function tmuxSessionFor({ session, theme }: { session: DisplaySession; theme: Theme }): string {
  if (!session.tmux) return theme.fg("dim", "direct");
  const name = cleanTerminalText({ text: session.tmux.session });
  return theme.fg("muted", name);
}

function descriptionFor({ session, theme }: { session: DisplaySession; theme: Theme }): string {
  const separator = theme.fg("dim", " · ");
  const location = session.tmux ? theme.fg("accent", `window ${session.tmux.window}`) : theme.fg("dim", "no tmux");
  const prompt = cleanTerminalText({ text: session.lastUserPrompt || "—" });
  return [
    theme.fg("muted", compactPath({ path: session.cwd })),
    location,
    theme.fg("text", theme.italic(`“${prompt}”`)),
  ].join(separator);
}

function sortedSessions({
  sessions,
  currentPid,
}: {
  sessions: DisplaySession[];
  currentPid: number;
}): DisplaySession[] {
  const rank: Record<DisplayStatus, number> = { running: 0, idle: 1, failed: 2, stale: 3 };
  return [...sessions].sort((left, right) => {
    if (left.pid === currentPid && right.pid === currentPid) return 0;
    if (left.pid === currentPid) return 1;
    if (right.pid === currentPid) return -1;
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
    theme.fg("accent", `${STATUS_GLYPH.running} ${counts.running} running`),
    theme.fg("success", `${STATUS_GLYPH.idle} ${counts.idle} idle`),
  ];
  if (counts.stale) parts.push(theme.fg("dim", `○ ${counts.stale} stale`));
  if (counts.failed) parts.push(theme.fg("error", `× ${counts.failed} failed`));
  return [truncateToWidth(parts.join(theme.fg("dim", " · ")), width, "…")];
}

export interface JumperAction {
  action: "jump" | "kill";
  pid: number;
}

export async function showJumper({
  ctx,
  sessions,
  currentPid,
}: {
  ctx: ExtensionContext;
  sessions: DisplaySession[];
  currentPid: number;
}): Promise<JumperAction | null> {
  return ctx.ui.custom<JumperAction | null>(
    (tui, theme, keybindings, done) => {
      const ordered = sortedSessions({ sessions, currentPid });
      const items: SelectItem[] = ordered.map((session) => {
        const status = session.displayStatus;
        const current = session.pid === currentPid ? theme.fg("warning", " ← current") : "";
        return {
          value: String(session.pid),
          label: `${theme.fg(STATUS_COLOR[status], STATUS_GLYPH[status])} ${theme.bold(sessionName({ session }))}${current}${theme.fg("dim", " · ")}${tmuxSessionFor({ session, theme })}`,
          description: descriptionFor({ session, theme }),
        };
      });

      const counts = countStatuses({ sessions });
      const container = new Container();
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
        { minPrimaryColumnWidth: 24, maxPrimaryColumnWidth: 42 },
      );
      let selectedIndex = 0;
      list.onSelect = (item) => done({ action: "jump", pid: Number(item.value) });
      list.onCancel = () => done(null);
      container.addChild(list);
      container.addChild(new Text(theme.fg("dim", "k/↑ j/↓ navigate · enter jump · x kill Pi · esc close"), 1, 0));

      return {
        render: (width: number) => {
          if (width < 2) return container.render(width);
          const innerWidth = width - 2;
          const border = (text: string) => theme.fg("borderAccent", text);
          const lines = container
            .render(innerWidth)
            .map(
              (line) =>
                `${border("│")}${line}${" ".repeat(Math.max(0, innerWidth - visibleWidth(line)))}${border("│")}`,
            );
          return [border(`┌${"─".repeat(innerWidth)}┐`), ...lines, border(`└${"─".repeat(innerWidth)}┘`)];
        },
        invalidate: () => container.invalidate(),
        handleInput: (data: string) => {
          if (data === "k" || keybindings.matches(data, "tui.select.up")) {
            selectedIndex = selectedIndex === 0 ? items.length - 1 : selectedIndex - 1;
            list.setSelectedIndex(selectedIndex);
          } else if (data === "j" || keybindings.matches(data, "tui.select.down")) {
            selectedIndex = selectedIndex === items.length - 1 ? 0 : selectedIndex + 1;
            list.setSelectedIndex(selectedIndex);
          } else if (data === "x") {
            const selected = list.getSelectedItem();
            if (selected) done({ action: "kill", pid: Number(selected.value) });
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
