import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { processStartedAt, readSessions, removeSession, type SessionRecord, writeSession } from "./registry.ts";

function liveRecord({ updatedAt = Date.now() }: { updatedAt?: number } = {}): SessionRecord {
  return {
    version: 1,
    sessionId: "test-session",
    cwd: process.cwd(),
    pid: process.pid,
    startedAt: updatedAt,
    updatedAt,
    status: "idle",
  };
}

test("reads the current process start time", () => {
  assert.equal(typeof processStartedAt({ pid: process.pid }), "string");
  assert.equal(processStartedAt({ pid: 99_999_999 }), undefined);
});

test("writes and reads a live session", () => {
  const directory = mkdtempSync(join(tmpdir(), "pi-jumper-"));
  try {
    writeSession({ record: liveRecord({}), directory });
    const sessions = readSessions({ directory });
    assert.equal(sessions.length, 1);
    assert.equal(sessions[0]?.displayStatus, "idle");
    assert.equal(JSON.parse(readFileSync(join(directory, `${process.pid}.json`), "utf8")).pid, process.pid);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("derives stale status from the heartbeat", () => {
  const directory = mkdtempSync(join(tmpdir(), "pi-jumper-"));
  try {
    const updatedAt = Date.now() - 20_000;
    writeSession({ record: liveRecord({ updatedAt }), directory });
    const sessions = readSessions({ directory, now: Date.now(), staleAfterMs: 10_000 });
    assert.equal(sessions[0]?.displayStatus, "stale");
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("prunes records whose process has exited", () => {
  const directory = mkdtempSync(join(tmpdir(), "pi-jumper-"));
  try {
    const deadPid = 99_999_999;
    writeFileSync(
      join(directory, `${deadPid}.json`),
      JSON.stringify({ ...liveRecord({ updatedAt: Date.now() - 30_000 }), pid: deadPid }),
    );
    assert.deepEqual(readSessions({ directory }), []);
    assert.throws(() => readFileSync(join(directory, `${deadPid}.json`)));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("expires abandoned records even if the PID is alive", () => {
  const directory = mkdtempSync(join(tmpdir(), "pi-jumper-"));
  try {
    const updatedAt = Date.now() - 60_000;
    writeSession({ record: liveRecord({ updatedAt }), directory });
    assert.deepEqual(readSessions({ directory, now: Date.now(), expireAfterMs: 30_000 }), []);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("removes malformed records", () => {
  const directory = mkdtempSync(join(tmpdir(), "pi-jumper-"));
  try {
    const path = join(directory, "broken.json");
    writeFileSync(path, "not json");
    assert.deepEqual(readSessions({ directory }), []);
    assert.equal(existsSync(path), false);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("removes the current process record", () => {
  const directory = mkdtempSync(join(tmpdir(), "pi-jumper-"));
  try {
    writeSession({ record: liveRecord({}), directory });
    removeSession({ pid: process.pid, directory });
    assert.deepEqual(readSessions({ directory }), []);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
