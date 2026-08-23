import { execFileSync } from "node:child_process";
import type { TmuxTarget } from "./registry.ts";

interface CommandResult {
  ok: boolean;
  stdout: string;
  error?: string;
}

function run({ command, args }: { command: string; args: string[] }): CommandResult {
  try {
    const stdout = execFileSync(command, args, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      timeout: 3_000,
    });
    return { ok: true, stdout };
  } catch (error) {
    const failure = error as { stderr?: string | Buffer; message?: string };
    return {
      ok: false,
      stdout: "",
      error: String(failure.stderr || failure.message || error).trim(),
    };
  }
}

function runTmux({ socket, args }: { socket: string; args: string[] }): CommandResult {
  return run({ command: "tmux", args: ["-S", socket, ...args] });
}

function socketFromEnvironment(): string | undefined {
  return process.env.TMUX?.split(",")[0] || undefined;
}

function resolveTmuxTarget({ socket, pane }: Pick<TmuxTarget, "socket" | "pane">): TmuxTarget | undefined {
  const result = runTmux({
    socket,
    args: ["display-message", "-p", "-t", pane, "#{session_name}\t#{window_index}\t#{pane_id}"],
  });
  if (!result.ok) return undefined;
  const [session, window, resolvedPane] = result.stdout.trim().split("\t");
  if (!session || !window || !resolvedPane) return undefined;
  return { socket, session, window, pane: resolvedPane };
}

export function currentTmuxTarget(): TmuxTarget | undefined {
  const pane = process.env.TMUX_PANE;
  const socket = socketFromEnvironment();
  return pane && socket ? resolveTmuxTarget({ socket, pane }) : undefined;
}

function mostRecentClient({ socket }: { socket: string }): string | undefined {
  const result = runTmux({
    socket,
    args: ["list-clients", "-F", "#{client_activity}\t#{client_tty}"],
  });
  if (!result.ok) return undefined;
  return result.stdout
    .trim()
    .split("\n")
    .filter(Boolean)
    .sort((left, right) => Number(right.split("\t")[0]) - Number(left.split("\t")[0]))[0]
    ?.split("\t")[1];
}

function clientForCurrentPane({ current }: { current?: TmuxTarget }): string | undefined {
  if (!current) return undefined;
  const result = runTmux({
    socket: current.socket,
    args: ["display-message", "-p", "-t", current.pane, "#{client_tty}"],
  });
  return result.ok && result.stdout.trim() ? result.stdout.trim() : undefined;
}

export function jumpToTmux({ target, current }: { target: TmuxTarget; current?: TmuxTarget }): {
  ok: boolean;
  error?: string;
} {
  if (current?.socket === target.socket && current.pane === target.pane) return { ok: true };

  const resolvedTarget = resolveTmuxTarget(target);
  if (!resolvedTarget) return { ok: false, error: "The tmux pane is no longer available" };
  for (const args of [
    ["select-window", "-t", resolvedTarget.pane],
    ["select-pane", "-t", resolvedTarget.pane],
  ]) {
    const selection = runTmux({ socket: resolvedTarget.socket, args });
    if (!selection.ok) return { ok: false, error: selection.error || "The tmux pane is no longer available" };
  }

  const currentClient = current?.socket === resolvedTarget.socket ? clientForCurrentPane({ current }) : undefined;
  const client = currentClient || mostRecentClient({ socket: resolvedTarget.socket });
  if (!client) return { ok: false, error: "The target tmux server has no attached client" };

  const switched = runTmux({
    socket: resolvedTarget.socket,
    args: ["switch-client", "-c", client, "-t", `${resolvedTarget.session}:${resolvedTarget.window}`],
  });
  if (!switched.ok) return { ok: false, error: switched.error || "Could not switch tmux client" };

  if (!current && process.platform === "darwin") run({ command: "open", args: ["-a", "Ghostty"] });
  return { ok: true };
}
