import type { AssistantMessage, Usage } from "@earendil-works/pi-ai";
import {
  createAgentSession,
  type AgentSession,
  type ExtensionAPI,
  getMarkdownTheme,
  keyHint,
  SessionManager,
  truncateHead,
  type Theme,
} from "@earendil-works/pi-coding-agent";
import { Container, Markdown, Spacer, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const CONFIG_PATH = fileURLToPath(new URL("./config.json", import.meta.url));
const RESULT_MAX_BYTES = 16 * 1024;
const EXCLUDED_TOOLS = new Set(["subagent", "ask_user", "ask_question"]);
const THINKING_LEVELS = ["off", "minimal", "low", "medium", "high", "xhigh", "max"] as const;
const TIMELINE_LIMIT = 60;
const CHILD_POLICY =
  "Perform one current inspection or task and report promptly. Do not sleep, poll, or wait for external changes; this policy overrides any delegated request to monitor for a long period.";

type ThinkingLevel = (typeof THINKING_LEVELS)[number];
type RunStatus = "running" | "done" | "error";
type TimelineStatus = "running" | "done" | "error";

interface Config {
  model: string;
  thinkingLevel: ThinkingLevel;
}

interface TimelineEvent {
  type: "tool" | "assistant";
  text: string;
  status?: TimelineStatus;
  toolCallId?: string;
}

interface RunState {
  title: string;
  prompt: string;
  model: string;
  tools: string[];
  status: RunStatus;
  activity: string;
  latestText: string;
  timeline: TimelineEvent[];
  activeToolIds: Set<string>;
  startedAt: number;
  finishedAt?: number;
  turns: number;
  toolUses: number;
  usage: Usage;
  contextTokens: number;
  contextWindow: number;
  error?: string;
  lastPreviewAt: number;
}

interface SubagentDetails {
  status: RunStatus;
  title: string;
  prompt: string;
  model: string;
  tools: string[];
  activity: string;
  output: string;
  timeline: TimelineEvent[];
  startedAt: number;
  durationMs: number;
  turns: number;
  toolUses: number;
  usage: Usage;
  contextTokens: number;
  contextWindow: number;
  error?: string;
}

function emptyUsage(): Usage {
  return {
    input: 0,
    output: 0,
    cacheRead: 0,
    cacheWrite: 0,
    totalTokens: 0,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
  };
}

function addUsage(total: Usage, next: Usage) {
  total.input += next.input;
  total.output += next.output;
  total.cacheRead += next.cacheRead;
  total.cacheWrite += next.cacheWrite;
  total.totalTokens += next.totalTokens;
  total.cost.input += next.cost.input;
  total.cost.output += next.cost.output;
  total.cost.cacheRead += next.cost.cacheRead;
  total.cost.cacheWrite += next.cost.cacheWrite;
  total.cost.total += next.cost.total;
  if (next.cacheWrite1h !== undefined) total.cacheWrite1h = (total.cacheWrite1h ?? 0) + next.cacheWrite1h;
  if (next.reasoning !== undefined) total.reasoning = (total.reasoning ?? 0) + next.reasoning;
}

function copyUsage(usage: Usage): Usage {
  return { ...usage, cost: { ...usage.cost } };
}

function readConfig(): Config {
  const value = JSON.parse(readFileSync(CONFIG_PATH, "utf8")) as Partial<Config>;
  if (!value.model || !value.model.includes("/")) {
    throw new Error(`Invalid subagent model in ${CONFIG_PATH}. Use provider/model-id.`);
  }
  if (!value.thinkingLevel || !THINKING_LEVELS.includes(value.thinkingLevel)) {
    throw new Error(`Invalid subagent thinkingLevel in ${CONFIG_PATH}.`);
  }
  return { model: value.model, thinkingLevel: value.thinkingLevel };
}

function assistantText(message: AssistantMessage) {
  return message.content
    .filter((part) => part.type === "text")
    .map((part) => part.text)
    .join("\n")
    .trim();
}

function finalAssistantMessage(session: AgentSession) {
  for (let index = session.messages.length - 1; index >= 0; index--) {
    const message = session.messages[index];
    if (message.role === "assistant") return message as AssistantMessage;
  }
  return undefined;
}

function flatten(text: string) {
  return text.replace(/\s+/g, " ").trim();
}

function previewText(text: string, maxLength = 160) {
  const flattened = flatten(text);
  if (!flattened) return "";
  return flattened.length > maxLength ? `${flattened.slice(0, maxLength - 1)}…` : flattened;
}

function describeTool(options: { toolName: string; args: unknown }) {
  const args = options.args as Record<string, unknown> | undefined;
  if (!args) return options.toolName;
  if (options.toolName === "bash" && typeof args.command === "string") {
    return `$ ${previewText(args.command.split("\n")[0], 90)}`;
  }
  const path = args.path ?? args.file_path;
  if (typeof path === "string") return `${options.toolName} ${path}`;
  if (typeof args.pattern === "string") return `${options.toolName} /${args.pattern}/`;
  return options.toolName;
}

function toolResultPreview(value: unknown) {
  if (!value || typeof value !== "object") return "";
  const content = (value as { content?: unknown }).content;
  if (!Array.isArray(content)) return "";
  const text = content
    .filter((part): part is { type: "text"; text: string } =>
      Boolean(part && typeof part === "object" && (part as { type?: unknown }).type === "text"),
    )
    .map((part) => part.text)
    .join(" ");
  return previewText(text, 240);
}

function addTimelineEvent(options: { run: RunState; event: TimelineEvent }) {
  options.run.timeline.push(options.event);
  while (options.run.timeline.length > TIMELINE_LIMIT) {
    const removableIndex = options.run.timeline.findIndex((event) => event.status !== "running");
    if (removableIndex === -1) break;
    options.run.timeline.splice(removableIndex, 1);
  }
}

function currentActivity(run: RunState) {
  const active = run.timeline.filter(
    (event) => event.type === "tool" && event.status === "running" && event.toolCallId && run.activeToolIds.has(event.toolCallId),
  );
  if (active.length === 0) return "thinking";
  if (active.length === 1) return active[0].text;
  return `${active[0].text} · +${active.length - 1} more`;
}

function elapsedMs(run: RunState) {
  return (run.finishedAt ?? Date.now()) - run.startedAt;
}

function detailsFor(run: RunState): SubagentDetails {
  return {
    status: run.status,
    title: run.title,
    prompt: run.prompt,
    model: run.model,
    tools: [...run.tools],
    activity: run.activity,
    output: run.latestText,
    timeline: run.timeline.map((event) => ({ ...event })),
    startedAt: run.startedAt,
    durationMs: elapsedMs(run),
    turns: run.turns,
    toolUses: run.toolUses,
    usage: copyUsage(run.usage),
    contextTokens: run.contextTokens,
    contextWindow: run.contextWindow,
    error: run.error,
  };
}

function boundedResult(output: string) {
  const result = truncateHead(output || "(no output)", {
    maxBytes: RESULT_MAX_BYTES,
    maxLines: 500,
  });
  return result.truncated
    ? `${result.content}\n\n[Subagent output truncated at 16 KB.]`
    : result.content;
}

function formatTokens(count: number) {
  if (count < 1_000) return String(count);
  if (count < 10_000) return `${(count / 1_000).toFixed(1)}k`;
  if (count < 1_000_000) return `${Math.round(count / 1_000)}k`;
  return `${(count / 1_000_000).toFixed(1)}M`;
}

function formatDuration(durationMs: number) {
  if (durationMs < 60_000) return `${(durationMs / 1_000).toFixed(1)}s`;
  return `${Math.floor(durationMs / 60_000)}m${Math.floor((durationMs % 60_000) / 1_000)}s`;
}

function formatStats(details: SubagentDetails) {
  const stats = [
    `${details.turns} turn${details.turns === 1 ? "" : "s"}`,
    `${details.toolUses} tool use${details.toolUses === 1 ? "" : "s"}`,
    formatDuration(details.durationMs),
  ];
  if (details.contextTokens > 0) {
    const context = details.contextWindow > 0
      ? `${Math.round((details.contextTokens / details.contextWindow) * 100)}% ctx`
      : `${formatTokens(details.contextTokens)} ctx`;
    stats.splice(2, 0, context);
  }
  if (details.usage.cost.total > 0) stats.push(`$${details.usage.cost.total.toFixed(4)}`);
  return stats.join(" · ");
}

function statusIcon(details: SubagentDetails, theme: Theme) {
  if (details.status === "running") return theme.fg("warning", "⟳");
  if (details.status === "error") return theme.fg("error", "✗");
  return theme.fg("success", "✓");
}

function renderTimelineEvent(event: TimelineEvent, theme: Theme) {
  if (event.type === "assistant") {
    return theme.fg("toolOutput", `  ${event.text}`);
  }
  const icon = event.status === "running"
    ? theme.fg("warning", "▸")
    : event.status === "error"
      ? theme.fg("error", "✗")
      : theme.fg("muted", "✓");
  return `${icon} ${theme.fg(event.status === "running" ? "text" : "muted", event.text)}`;
}

function renderSubagentResult(
  result: { content: Array<{ type: string; text?: string }>; details?: unknown },
  expanded: boolean,
  theme: Theme,
) {
  const details = result.details as SubagentDetails | undefined;
  if (!details) {
    const content = result.content[0];
    return new Text(content?.type === "text" ? content.text ?? "(no output)" : "(no output)", 0, 0);
  }

  const header = `${statusIcon(details, theme)} ${theme.fg("toolTitle", theme.bold(details.title))} ${theme.fg("muted", `(${details.model})`)} ${theme.fg("dim", `· ${formatStats(details)}`)}`;
  if (!expanded) {
    const activity = details.status === "running"
      ? details.activity
      : details.error
        ? details.error
        : previewText(details.output) || "completed";
    const hint = details.timeline.length > 0 ? ` · ${keyHint("app.tools.expand", "details")}` : "";
    return new Text(`${header}\n${theme.fg("dim", "⎿  ")}${theme.fg(details.status === "error" ? "error" : "toolOutput", activity)}${theme.fg("dim", hint)}`, 0, 0);
  }

  const container = new Container();
  container.addChild(new Text(header, 0, 0));
  container.addChild(new Spacer(1));
  container.addChild(new Text(theme.fg("muted", "Task"), 0, 0));
  container.addChild(new Text(details.prompt, 0, 0));

  if (details.timeline.length > 0) {
    container.addChild(new Spacer(1));
    container.addChild(new Text(theme.fg("muted", "Timeline"), 0, 0));
    for (const event of details.timeline) {
      container.addChild(new Text(renderTimelineEvent(event, theme), 0, 0));
    }
  }

  if (details.status === "running" && details.activity === "responding" && details.output) {
    container.addChild(new Spacer(1));
    container.addChild(new Text(theme.fg("muted", "Live output"), 0, 0));
    container.addChild(new Text(details.output, 0, 0));
  } else if (details.status !== "running" && details.output) {
    container.addChild(new Spacer(1));
    container.addChild(new Text(theme.fg("muted", "Output"), 0, 0));
    container.addChild(new Markdown(details.output, 0, 0, getMarkdownTheme()));
  }

  if (details.error) {
    container.addChild(new Spacer(1));
    container.addChild(new Text(theme.fg("error", `Error: ${details.error}`), 0, 0));
  }
  return container;
}

export default function subagentsExtension(pi: ExtensionAPI) {
  const sessions = new Set<AgentSession>();

  pi.on("session_shutdown", async () => {
    const activeSessions = [...sessions];
    sessions.clear();
    await Promise.all(activeSessions.map((session) => session.abort().catch(() => undefined)));
  });

  pi.registerTool({
    name: "subagent",
    label: "Subagent",
    description:
      "Run one bounded, isolated subagent using the configured model. The child performs one current inspection or task and reports promptly; it must not sleep, poll, or wait for external changes. The child cannot see the parent conversation, so provide a complete prompt. Omit tools to inherit the parent's active tools, or provide a smaller subset. Call this tool multiple times in one response to run subagents in parallel.",
    promptSnippet: "Delegate one self-contained task to an isolated subagent",
    promptGuidelines: [
      "Use subagent for independent tasks that benefit from a separate context window.",
      "Give subagent a complete prompt because it cannot see the parent conversation.",
      "Call subagent multiple times in the same response when independent tasks can run in parallel.",
      "Delegate one current inspection or task only; never delegate sleeping, polling, waiting for external state, or long-running monitoring. Handle follow-up checks in the parent.",
    ],
    parameters: Type.Object({
      title: Type.String({ minLength: 1, maxLength: 80, description: "Short title shown in live progress" }),
      prompt: Type.String({ minLength: 1, description: "Complete, self-contained task for the subagent" }),
      tools: Type.Optional(
        Type.Array(Type.String(), {
          minItems: 1,
          maxItems: 32,
          description: "Optional subset of the parent's active tools. Omit to inherit all compatible parent tools.",
        }),
      ),
    }),

    async execute(_toolCallId, params, signal, onUpdate, ctx) {
      const config = readConfig();
      const separator = config.model.indexOf("/");
      const model = ctx.modelRegistry.find(config.model.slice(0, separator), config.model.slice(separator + 1));
      if (!model) throw new Error(`Subagent model is not available: ${config.model}`);

      const parentTools = pi.getActiveTools();
      const requestedTools = params.tools ?? parentTools;
      const unknownTools = requestedTools.filter((name) => !parentTools.includes(name));
      if (unknownTools.length > 0) throw new Error(`Subagent requested inactive tools: ${unknownTools.join(", ")}`);
      const blockedTools = requestedTools.filter((name) => EXCLUDED_TOOLS.has(name));
      if (params.tools && blockedTools.length > 0) throw new Error(`Subagents cannot use: ${blockedTools.join(", ")}`);
      const tools = [...new Set(requestedTools.filter((name) => !EXCLUDED_TOOLS.has(name)))];

      const run: RunState = {
        title: params.title.trim(),
        prompt: params.prompt,
        model: `${model.provider}/${model.id}`,
        tools,
        status: "running",
        activity: "starting",
        latestText: "",
        timeline: [],
        activeToolIds: new Set(),
        startedAt: Date.now(),
        turns: 0,
        toolUses: 0,
        usage: emptyUsage(),
        contextTokens: 0,
        contextWindow: model.contextWindow,
        lastPreviewAt: 0,
      };

      const emitProgress = () => {
        onUpdate?.({
          content: [{ type: "text", text: "(running...)" }],
          details: detailsFor(run),
        });
      };
      emitProgress();
      const progressTimer = setInterval(emitProgress, 1_000);
      progressTimer.unref?.();

      let child: AgentSession | undefined;
      const abortChild = () => void child?.abort().catch(() => undefined);
      signal?.addEventListener("abort", abortChild, { once: true });

      try {
        if (signal?.aborted) throw new Error("Subagent was aborted.");
        const created = await createAgentSession({
          cwd: ctx.cwd,
          model,
          thinkingLevel: config.thinkingLevel,
          tools,
          excludeTools: [...EXCLUDED_TOOLS],
          sessionManager: SessionManager.inMemory(ctx.cwd),
        });
        child = created.session;
        sessions.add(child);
        if (signal?.aborted) {
          await child.abort().catch(() => undefined);
          throw new Error("Subagent was aborted.");
        }
        await child.bindExtensions({ mode: "print" });

        const unsubscribe = child.subscribe((event) => {
          if (event.type === "agent_start") {
            run.activity = "thinking";
            emitProgress();
          } else if (event.type === "turn_end") {
            run.turns += 1;
          } else if (event.type === "tool_execution_start") {
            const text = describeTool({ toolName: event.toolName, args: event.args });
            run.toolUses += 1;
            run.activeToolIds.add(event.toolCallId);
            addTimelineEvent({
              run,
              event: { type: "tool", text, status: "running", toolCallId: event.toolCallId },
            });
            run.activity = currentActivity(run);
            emitProgress();
          } else if (event.type === "tool_execution_end") {
            run.activeToolIds.delete(event.toolCallId);
            const timelineEvent = run.timeline.find((item) => item.toolCallId === event.toolCallId);
            if (timelineEvent) {
              timelineEvent.status = event.isError ? "error" : "done";
              const preview = toolResultPreview(event.result);
              if (preview) timelineEvent.text = `${timelineEvent.text} — ${preview}`;
            }
            run.activity = currentActivity(run);
            emitProgress();
          } else if (event.type === "message_start" && event.message.role === "assistant") {
            run.latestText = "";
          } else if (event.type === "message_update" && event.assistantMessageEvent.type === "text_delta") {
            run.latestText = `${run.latestText}${event.assistantMessageEvent.delta}`.slice(-8_000);
            const now = Date.now();
            if (now - run.lastPreviewAt >= 200) {
              run.lastPreviewAt = now;
              run.activity = "responding";
              emitProgress();
            }
          } else if (event.type === "message_end" && event.message.role === "assistant") {
            const message = event.message as AssistantMessage;
            const text = assistantText(message);
            run.model = `${message.provider}/${message.responseModel ?? message.model}`;
            run.latestText = text || run.latestText;
            run.contextTokens = message.usage.totalTokens;
            addUsage(run.usage, message.usage);
            if (text) {
              addTimelineEvent({
                run,
                event: { type: "assistant", text: previewText(text, 500) },
              });
            }
            run.activity = run.activeToolIds.size > 0 ? currentActivity(run) : "thinking";
            emitProgress();
          }
        });

        try {
          await child.prompt(`${CHILD_POLICY}\n\nTask:\n${params.prompt}`);
        } finally {
          unsubscribe();
        }

        const final = finalAssistantMessage(child);
        if (!final) throw new Error("Subagent returned no assistant message.");
        if (final.stopReason === "error") throw new Error(final.errorMessage ?? "Subagent failed.");
        if (final.stopReason === "aborted" || signal?.aborted) throw new Error("Subagent was aborted.");

        run.latestText = assistantText(final);
        const finalPreview = previewText(run.latestText, 500);
        const lastTimelineEvent = run.timeline.at(-1);
        if (lastTimelineEvent?.type === "assistant" && lastTimelineEvent.text === finalPreview) {
          run.timeline.pop();
        }
        run.status = "done";
        run.activity = "completed";
        run.finishedAt = Date.now();
        emitProgress();

        return {
          content: [{ type: "text", text: boundedResult(run.latestText) }],
          details: detailsFor(run),
          usage: copyUsage(run.usage),
        };
      } catch (error) {
        run.status = "error";
        run.activity = "failed";
        run.error = error instanceof Error ? error.message : String(error);
        run.finishedAt = Date.now();
        emitProgress();
        throw error;
      } finally {
        clearInterval(progressTimer);
        signal?.removeEventListener("abort", abortChild);
        if (child) {
          sessions.delete(child);
          try {
            if (child.extensionRunner.hasHandlers("session_shutdown")) {
              await child.extensionRunner.emit({ type: "session_shutdown", reason: "quit" });
            }
          } catch {
            // Child extension shutdown is best-effort.
          }
          try {
            child.dispose();
          } catch {
            // Child may already be disposed after cancellation.
          }
        }
      }
    },

    renderCall(args, theme) {
      let model = "configured model";
      try {
        model = readConfig().model;
      } catch {
        // The execute error reports invalid configuration.
      }
      return new Text(
        `${theme.fg("toolTitle", theme.bold("subagent "))}${theme.fg("accent", args.title || "...")} ${theme.fg("muted", `(${model})`)}`,
        0,
        0,
      );
    },

    renderResult(result, { expanded }, theme) {
      return renderSubagentResult(result, expanded, theme);
    },
  });
}
