const MAX_COMMAND_LENGTH = 48;
const MAX_PROMPT_PREVIEW_LENGTH = 32;

export function cleanTerminalText({ text }: { text: string }): string {
  return (
    text
      // biome-ignore lint/suspicious/noControlCharactersInRegex: Terminal output may contain control characters.
      .replace(/[\u0000-\u001f\u007f-\u009f]/g, " ")
      .replace(/\s+/g, " ")
      .trim()
  );
}

function shorten({ text, maxLength = MAX_COMMAND_LENGTH }: { text: string; maxLength?: number }): string {
  const clean = cleanTerminalText({ text });
  return clean.length > maxLength ? `${clean.slice(0, maxLength - 1)}…` : clean;
}

function firstString({ args, keys }: { args: Record<string, unknown>; keys: string[] }): string | undefined {
  for (const key of keys) {
    const value = args[key];
    if (typeof value === "string" && value.trim()) return value;
  }
  return undefined;
}

export function summarizeToolCall({ toolName, args }: { toolName: string; args: unknown }): string {
  const toolArgs = args && typeof args === "object" ? (args as Record<string, unknown>) : {};
  const detail = firstString({
    args: toolArgs,
    keys: toolName === "bash" ? ["command"] : ["path", "query", "pattern", "subject", "url"],
  });
  return shorten({ text: detail ? `${toolName}: ${detail}` : toolName });
}

export function summarizeUserCommand({ command }: { command: string }): string {
  return shorten({ text: `shell: ${command}` });
}

export function summarizeUserPrompt({ prompt }: { prompt: string }): string {
  return shorten({ text: prompt, maxLength: MAX_PROMPT_PREVIEW_LENGTH });
}

export function agentRunFailed({ messages }: { messages: Array<{ role: string; stopReason?: string }> }): boolean {
  return messages.some((message) => message.role === "assistant" && message.stopReason === "error");
}

export function activityFromSessionEntries({ entries }: { entries: readonly unknown[] }): {
  lastUserPrompt?: string;
  lastCommand?: string;
} {
  let lastUserPrompt: string | undefined;
  let lastCommand: string | undefined;

  for (let index = entries.length - 1; index >= 0 && (!lastUserPrompt || !lastCommand); index--) {
    const entry = entries[index];
    if (!entry || typeof entry !== "object" || (entry as Record<string, unknown>).type !== "message") continue;
    const message = (entry as { message?: unknown }).message;
    if (!message || typeof message !== "object") continue;
    const { role, content } = message as { role?: unknown; content?: unknown };

    if (!lastUserPrompt && role === "user") {
      const text =
        typeof content === "string"
          ? content
          : Array.isArray(content)
            ? content
                .filter((part): part is { type: "text"; text: string } =>
                  Boolean(part && typeof part === "object" && part.type === "text" && typeof part.text === "string"),
                )
                .map((part) => part.text)
                .join("\n")
            : "";
      if (text.trim()) lastUserPrompt = summarizeUserPrompt({ prompt: text });
    }

    if (!lastCommand && role === "assistant" && Array.isArray(content)) {
      for (let partIndex = content.length - 1; partIndex >= 0; partIndex--) {
        const part = content[partIndex] as Record<string, unknown> | undefined;
        if (part?.type !== "toolCall" || typeof part.name !== "string") continue;
        lastCommand = summarizeToolCall({ toolName: part.name, args: part.arguments });
        break;
      }
    }
  }
  return { lastUserPrompt, lastCommand };
}
