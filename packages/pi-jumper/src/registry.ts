import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export type SessionStatus = "running" | "idle" | "failed";
export type DisplayStatus = SessionStatus | "stale";

export interface TmuxTarget {
  socket: string;
  session: string;
  window: string;
  pane: string;
}

export interface SessionRecord {
  version: 1;
  sessionId: string;
  sessionFile?: string;
  name?: string;
  cwd: string;
  pid: number;
  processStartedAt?: string;
  startedAt: number;
  updatedAt: number;
  status: SessionStatus;
  lastUserPrompt?: string;
  lastCommand?: string;
  terminal?: string;
  tmux?: TmuxTarget;
}

export interface DisplaySession extends SessionRecord {
  displayStatus: DisplayStatus;
}

export const STATE_DIRECTORY = join(homedir(), ".pi", "agent", "pi-jumper");
export const STALE_AFTER_MS = 20_000;
export const EXPIRE_AFTER_MS = 24 * 60 * 60 * 1_000;

function statePathFor({ directory, pid }: { directory: string; pid: number }): string {
  return join(directory, `${pid}.json`);
}

function isTmuxTarget(value: unknown): value is TmuxTarget {
  if (!value || typeof value !== "object") return false;
  const target = value as Record<string, unknown>;
  return (
    typeof target.socket === "string" &&
    typeof target.session === "string" &&
    typeof target.window === "string" &&
    typeof target.pane === "string"
  );
}

function isSessionRecord(value: unknown): value is SessionRecord {
  if (!value || typeof value !== "object") return false;
  const record = value as Record<string, unknown>;
  return (
    record.version === 1 &&
    typeof record.sessionId === "string" &&
    typeof record.cwd === "string" &&
    typeof record.pid === "number" &&
    (record.processStartedAt === undefined || typeof record.processStartedAt === "string") &&
    typeof record.startedAt === "number" &&
    typeof record.updatedAt === "number" &&
    (record.status === "running" || record.status === "idle" || record.status === "failed") &&
    (record.lastUserPrompt === undefined || typeof record.lastUserPrompt === "string") &&
    (record.lastCommand === undefined || typeof record.lastCommand === "string") &&
    (record.tmux === undefined || isTmuxTarget(record.tmux))
  );
}

export function processStartedAt({ pid }: { pid: number }): string | undefined {
  try {
    return (
      execFileSync("ps", ["-o", "lstart=", "-p", String(pid)], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
        timeout: 1_000,
      }).trim() || undefined
    );
  } catch {
    return undefined;
  }
}

function processIsAlive({ pid }: { pid: number }): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === "EPERM";
  }
}

export function writeSession({
  record,
  directory = STATE_DIRECTORY,
}: {
  record: SessionRecord;
  directory?: string;
}): void {
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const destination = statePathFor({ directory, pid: record.pid });
  const temporary = `${destination}.${process.pid}.tmp`;
  writeFileSync(temporary, `${JSON.stringify(record)}\n`, { encoding: "utf8", mode: 0o600 });
  renameSync(temporary, destination);
}

export function removeSession({ pid, directory = STATE_DIRECTORY }: { pid: number; directory?: string }): void {
  try {
    unlinkSync(statePathFor({ directory, pid }));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
}

export function readSessions({
  directory = STATE_DIRECTORY,
  now = Date.now(),
  staleAfterMs = STALE_AFTER_MS,
  expireAfterMs = EXPIRE_AFTER_MS,
}: {
  directory?: string;
  now?: number;
  staleAfterMs?: number;
  expireAfterMs?: number;
} = {}): DisplaySession[] {
  if (!existsSync(directory)) return [];

  const sessions: DisplaySession[] = [];
  for (const filename of readdirSync(directory)) {
    if (!filename.endsWith(".json")) continue;
    const sessionPath = join(directory, filename);
    try {
      const record: unknown = JSON.parse(readFileSync(sessionPath, "utf8"));
      if (!isSessionRecord(record)) {
        unlinkSync(sessionPath);
        continue;
      }
      const age = now - record.updatedAt;
      if (age > expireAfterMs || (age > staleAfterMs && !processIsAlive({ pid: record.pid }))) {
        unlinkSync(sessionPath);
        continue;
      }
      sessions.push({
        ...record,
        displayStatus: age > staleAfterMs ? "stale" : record.status,
      });
    } catch (error) {
      if (error instanceof SyntaxError) unlinkSync(sessionPath);
      else console.error(`pi-jumper: could not read ${sessionPath}`, error);
    }
  }
  return sessions;
}
