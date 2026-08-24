/**
 * Syncs pi theme with macOS system appearance (dark/light mode).
 * Checks on session start and polls every second.
 */

import { exec } from "node:child_process";
import { promisify } from "node:util";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const execAsync = promisify(exec);

const DARK_THEME = "modus-vivendi";
const LIGHT_THEME = "modus-operandi";
const POLL_INTERVAL_MS = 1000;

async function isDarkMode(): Promise<boolean> {
  try {
    const { stdout } = await execAsync(
      "osascript -e 'tell application \"System Events\" to tell appearance preferences to return dark mode'",
    );
    return stdout.trim() === "true";
  } catch {
    return false;
  }
}

export default function (pi: ExtensionAPI) {
  let intervalId: ReturnType<typeof setInterval> | null = null;

  pi.on("session_start", async (_event, ctx) => {
    let currentTheme = (await isDarkMode()) ? DARK_THEME : LIGHT_THEME;
    ctx.ui.setTheme(currentTheme);

    intervalId = setInterval(async () => {
      const newTheme = (await isDarkMode()) ? DARK_THEME : LIGHT_THEME;
      if (newTheme !== currentTheme) {
        currentTheme = newTheme;
        ctx.ui.setTheme(currentTheme);
      }
    }, POLL_INTERVAL_MS);
  });

  pi.on("session_shutdown", () => {
    if (intervalId) {
      clearInterval(intervalId);
      intervalId = null;
    }
  });
}
