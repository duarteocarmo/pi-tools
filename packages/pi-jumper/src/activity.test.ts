import assert from "node:assert/strict";
import test from "node:test";
import {
	activityFromSessionEntries,
	agentRunFailed,
	cleanTerminalText,
	summarizeToolCall,
	summarizeUserCommand,
	summarizeUserPrompt,
} from "./activity.ts";

test("summarizes bash commands on one line", () => {
	assert.equal(
		summarizeToolCall({ toolName: "bash", args: { command: "uv run pytest\n--quiet" } }),
		"bash: uv run pytest --quiet",
	);
});

test("summarizes path-based tools", () => {
	assert.equal(
		summarizeToolCall({ toolName: "read", args: { path: "/tmp/example.ts" } }),
		"read: /tmp/example.ts",
	);
});

test("removes terminal control characters", () => {
	assert.equal(cleanTerminalText({ text: "safe\u001b[31m red" }), "safe [31m red");
	assert.equal(summarizeUserCommand({ command: "git status" }), "shell: git status");
});

test("summarizes the latest user prompt", () => {
	assert.equal(
		summarizeUserPrompt({ prompt: "Fix picker\nand run tests" }),
		"Fix picker and run tests",
	);
});

test("limits user prompts to a short preview", () => {
	const preview = summarizeUserPrompt({ prompt: "x".repeat(100) });
	assert.equal(preview.length, 32);
	assert.equal(preview.endsWith("…"), true);
});

test("only treats agent response errors as failed runs", () => {
	assert.equal(
		agentRunFailed({ messages: [{ role: "toolResult" }, { role: "assistant", stopReason: "stop" }] }),
		false,
	);
	assert.equal(agentRunFailed({ messages: [{ role: "assistant", stopReason: "error" }] }), true);
});

test("restores the latest prompt and tool call from session history", () => {
	const activity = activityFromSessionEntries({
		entries: [
			{ type: "message", message: { role: "user", content: [{ type: "text", text: "Older prompt" }] } },
			{
				type: "message",
				message: {
					role: "assistant",
					content: [{ type: "toolCall", name: "read", arguments: { path: "/tmp/old.ts" } }],
				},
			},
			{ type: "message", message: { role: "user", content: [{ type: "text", text: "Latest prompt" }] } },
			{
				type: "message",
				message: {
					role: "assistant",
					content: [{ type: "toolCall", name: "bash", arguments: { command: "npm test" } }],
				},
			},
		],
	});
	assert.deepEqual(activity, { lastUserPrompt: "Latest prompt", lastCommand: "bash: npm test" });
});
