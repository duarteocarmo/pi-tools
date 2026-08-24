import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { TUI } from "@earendil-works/pi-tui";
import {
  activityFromSessionEntries,
  agentRunFailed,
  summarizeToolCall,
  summarizeUserCommand,
  summarizeUserPrompt,
} from "./src/activity.ts";
import { readSessions, removeSession, type DisplaySession, type SessionRecord, writeSession } from "./src/registry.ts";
import { currentTmuxTarget, jumpToTmux } from "./src/tmux.ts";
import { renderSessionWidget, showJumper } from "./src/ui.ts";

const HEARTBEAT_MS = 5_000;
const WIDGET_KEY = "pi-jumper";
const WIDGET_VISIBILITY_ENTRY = "pi-jumper-widget-visibility";

export default function piJumper(pi: ExtensionAPI): void {
  let current: SessionRecord | undefined;
  let sessions: DisplaySession[] = [];
  let heartbeat: ReturnType<typeof setInterval> | undefined;
  let widgetTui: TUI | undefined;
  let widgetRegistered = false;
  let widgetVisible = true;
  let agentFailed = false;

  function refreshSessions(): void {
    try {
      sessions = readSessions();
      widgetTui?.requestRender();
    } catch (error) {
      console.error("pi-jumper: could not read session state", error);
    }
  }

  function updateCurrentSession(): void {
    if (!current) return;
    const currentSession: DisplaySession = { ...current, displayStatus: current.status };
    const index = sessions.findIndex((session) => session.pid === currentSession.pid);
    if (index === -1) sessions.push(currentSession);
    else sessions[index] = currentSession;
    widgetTui?.requestRender();
  }

  function persist({ refresh = false }: { refresh?: boolean } = {}): void {
    if (!current) return;
    current.updatedAt = Date.now();
    try {
      writeSession({ record: current });
      if (refresh) refreshSessions();
      else updateCurrentSession();
    } catch (error) {
      console.error("pi-jumper: could not write session state", error);
    }
  }

  function registerWidget({ ctx }: { ctx: ExtensionContext }): void {
    if (ctx.mode !== "tui" || widgetRegistered || !widgetVisible) return;
    ctx.ui.setWidget(
      WIDGET_KEY,
      (tui, theme) => {
        widgetTui = tui;
        return {
          render: (width: number) => renderSessionWidget({ sessions, theme, width }),
          invalidate: () => {},
        };
      },
      { placement: "belowEditor" },
    );
    widgetRegistered = true;
  }

  function removeWidget({ ctx }: { ctx: ExtensionContext }): void {
    if (widgetRegistered) ctx.ui.setWidget(WIDGET_KEY, undefined);
    widgetRegistered = false;
    widgetTui = undefined;
  }

  function restoreWidgetVisibility({ ctx }: { ctx: ExtensionContext }): void {
    widgetVisible = true;
    for (const entry of ctx.sessionManager.getBranch()) {
      if (entry.type !== "custom" || entry.customType !== WIDGET_VISIBILITY_ENTRY) continue;
      const visible = (entry.data as { visible?: unknown } | undefined)?.visible;
      if (typeof visible === "boolean") widgetVisible = visible;
    }
  }

  pi.on("session_start", (_event, ctx) => {
    clearInterval(heartbeat);
    const now = Date.now();
    const activity = activityFromSessionEntries({ entries: ctx.sessionManager.getBranch() });
    current = {
      version: 1,
      sessionId: ctx.sessionManager.getSessionId(),
      sessionFile: ctx.sessionManager.getSessionFile() || undefined,
      name: pi.getSessionName(),
      cwd: ctx.cwd,
      pid: process.pid,
      startedAt: now,
      updatedAt: now,
      status: "idle",
      ...activity,
      terminal: process.env.TERM_PROGRAM || process.env.TERM,
      tmux: currentTmuxTarget(),
    };
    agentFailed = false;
    restoreWidgetVisibility({ ctx });
    registerWidget({ ctx });
    persist({ refresh: true });
    heartbeat = setInterval(() => persist({ refresh: true }), HEARTBEAT_MS);
    heartbeat.unref();
  });

  pi.on("session_info_changed", (event) => {
    if (!current) return;
    current.name = event.name;
    persist();
  });

  pi.on("input", (event) => {
    if (!current || event.source === "extension") return;
    current.lastUserPrompt = summarizeUserPrompt({ prompt: event.text });
    persist();
  });

  pi.on("agent_start", () => {
    if (!current) return;
    agentFailed = false;
    current.status = "running";
    persist();
  });

  pi.on("tool_execution_start", (event) => {
    if (!current) return;
    current.lastCommand = summarizeToolCall({ toolName: event.toolName, args: event.args });
    persist();
  });

  pi.on("agent_end", (event) => {
    agentFailed = agentRunFailed({ messages: event.messages });
  });

  pi.on("user_bash", (event) => {
    if (!current) return;
    current.lastCommand = summarizeUserCommand({ command: event.command });
    persist();
  });

  pi.on("agent_settled", () => {
    if (!current) return;
    current.status = agentFailed ? "failed" : "idle";
    persist();
  });

  pi.on("session_shutdown", (_event, ctx) => {
    clearInterval(heartbeat);
    heartbeat = undefined;
    removeSession({ pid: process.pid });
    removeWidget({ ctx });
    current = undefined;
  });

  function toggleWidget({ ctx }: { ctx: ExtensionContext }): void {
    widgetVisible = !widgetVisible;
    pi.appendEntry(WIDGET_VISIBILITY_ENTRY, { visible: widgetVisible });
    if (widgetVisible) {
      registerWidget({ ctx });
      refreshSessions();
    } else {
      removeWidget({ ctx });
    }
    ctx.ui.notify(`Pi Jumper widget ${widgetVisible ? "shown" : "hidden"}`, "info");
  }

  async function openJumper({ ctx }: { ctx: ExtensionContext }): Promise<void> {
    if (ctx.mode !== "tui") {
      ctx.ui.notify("pi-jumper is available in interactive mode", "warning");
      return;
    }

    while (true) {
      refreshSessions();
      if (sessions.length === 0) {
        ctx.ui.notify("No live Pi sessions found", "info");
        return;
      }

      const selectedPid = await showJumper({ ctx, sessions, currentPid: process.pid });
      if (selectedPid === null) return;
      const selected = sessions.find((session) => session.pid === selectedPid);
      if (!selected) {
        ctx.ui.notify("That Pi session is no longer running", "warning");
        continue;
      }
      if (selected.pid === process.pid) {
        ctx.ui.notify("You are already in this Pi session", "info");
        continue;
      }
      if (!selected.tmux) {
        ctx.ui.notify("This Pi session is not inside tmux, so it cannot be focused reliably", "warning");
        continue;
      }

      const result = jumpToTmux({ target: selected.tmux, current: currentTmuxTarget() });
      if (result.ok) return;
      ctx.ui.notify(`Could not jump: ${result.error}`, "error");
    }
  }

  pi.registerShortcut("alt+j", {
    description: "Open Pi Jumper",
    handler: async (ctx) => openJumper({ ctx }),
  });

  pi.registerCommand("jumper", {
    description: "See live Pi sessions or toggle the sticky widget",
    handler: async (args, ctx) => {
      if (ctx.mode !== "tui") {
        ctx.ui.notify("pi-jumper is available in interactive mode", "warning");
        return;
      }

      const action = args.trim();
      if (action === "toggle") {
        toggleWidget({ ctx });
        return;
      }
      if (action) {
        ctx.ui.notify("Usage: /jumper [toggle]", "warning");
        return;
      }

      await openJumper({ ctx });
    },
  });
}
