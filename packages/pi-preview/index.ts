import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { writeFileSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { exec } from "node:child_process";
import { marked } from "marked";
import hljs from "highlight.js";

function escapeHtml(value: string) {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

const renderer = new marked.Renderer();

renderer.code = ({ text, lang, escaped }) => {
  const language = (lang || "").trim().split(/\s+/)[0];
  const escapedCode = escaped ? text : escapeHtml(text);

  if (language === "mermaid") {
    return `<pre><code class="language-mermaid">${escapedCode}</code></pre>\n`;
  }

  if (!language || !hljs.getLanguage(language)) {
    return `<pre><code>${escapedCode}</code></pre>\n`;
  }

  try {
    const highlighted = hljs.highlight(text, { language }).value;
    return `<pre><code class="hljs language-${escapeHtml(language)}">${highlighted}</code></pre>\n`;
  } catch {
    return `<pre><code class="language-${escapeHtml(language)}">${escapedCode}</code></pre>\n`;
  }
};

const HTML_TEMPLATE = (body: string) => `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Preview</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Crimson+Pro:ital,wght@0,400..700;1,400..700&family=IBM+Plex+Mono:wght@400;500;600&display=swap" rel="stylesheet">
<style>
:root {
  color-scheme: light dark;
  --page: #fffff8;
  --text: #24211b;
  --muted: #6e675e;
  --accent: #9b2f21;
  --rule: color-mix(in srgb, var(--text), transparent 84%);
  --code-bg: color-mix(in srgb, var(--text), transparent 95%);
  --code-text: #46372d;
  --syntax-comment: #8a8376;
  --syntax-keyword: #9b2f21;
  --syntax-string: #5e6d2d;
  --syntax-number: #8a4f17;
  --syntax-title: #1f5f7a;
  --syntax-meta: #6f5795;
  --measure: 100%;
  --wide: 100%;
}

@media (prefers-color-scheme: dark) {
  :root {
    --page: #11110e;
    --text: #eee8d8;
    --muted: #aaa392;
    --accent: #e28b7d;
    --rule: color-mix(in srgb, var(--text), transparent 82%);
    --code-bg: color-mix(in srgb, white, transparent 92%);
    --code-text: #f0d2b8;
    --syntax-comment: #8d877b;
    --syntax-keyword: #e28b7d;
    --syntax-string: #bfd38a;
    --syntax-number: #e0ad75;
    --syntax-title: #8fc7e8;
    --syntax-meta: #c1a0e8;
  }
}

* { box-sizing: border-box; }

html { background: var(--page); }

body {
  margin: 0;
  min-height: 100vh;
  background: var(--page);
  color: var(--text);
  font-family: "Crimson Pro", "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, serif;
  font-size: clamp(18px, 1.15vw, 21px);
  line-height: 1.62;
  letter-spacing: 0.003em;
}

main {
  width: 100%;
  padding: clamp(1.25rem, 4vw, 4rem) clamp(1rem, 4vw, 4rem) clamp(3rem, 6vw, 6rem);
}

main > :where(h1, h2, h3, h4, p, ul, ol, blockquote, hr, table) {
  max-width: var(--measure);
  margin-left: 0;
  margin-right: auto;
}

main > *:first-child { margin-top: 0; }
main > *:last-child { margin-bottom: 0; }

h1, h2, h3, h4 {
  color: var(--text);
  font-weight: 500;
  line-height: 1.08;
  letter-spacing: -0.025em;
}

h1 {
  margin-top: 0;
  margin-bottom: 1.35rem;
  font-size: clamp(2.8rem, 7vw, 5.8rem);
  max-width: 100%;
}

h2 {
  margin-top: 3rem;
  margin-bottom: 0.75rem;
  font-size: clamp(1.75rem, 3vw, 2.4rem);
}

h3 {
  margin-top: 2.2rem;
  margin-bottom: 0.55rem;
  font-size: clamp(1.35rem, 2vw, 1.7rem);
}

h4 {
  margin-top: 1.8rem;
  margin-bottom: 0.45rem;
  font-size: 1.1em;
  font-style: italic;
}

p { margin-top: 1rem; margin-bottom: 1rem; }

ul, ol {
  margin-top: 1rem;
  margin-bottom: 1.25rem;
  padding-left: 1.35rem;
}

li { padding-left: 0.25rem; }
li + li { margin-top: 0.42rem; }
li::marker { color: var(--accent); font-weight: 700; }

blockquote {
  margin-top: 2rem;
  margin-bottom: 2rem;
  padding-left: 1.15rem;
  border-left: 3px solid var(--accent);
  color: var(--text);
  font-size: 1.08em;
  font-style: italic;
}

blockquote p { margin: 0.6rem 0; }

a {
  color: var(--accent);
  text-decoration-color: color-mix(in srgb, var(--accent), transparent 58%);
  text-decoration-thickness: 0.08em;
  text-underline-offset: 0.16em;
}

hr {
  height: 1px;
  margin-top: 2.4rem;
  margin-bottom: 2.4rem;
  border: 0;
  background: var(--rule);
}

code {
  border-radius: 0.34em;
  padding: 0.1em 0.32em;
  background: var(--code-bg);
  color: var(--code-text);
  font-family: "IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.74em;
  line-height: 1.45;
}

pre {
  overflow: auto;
  width: 100%;
  min-width: 0;
  max-width: 100%;
  margin: 1.35rem auto 1.8rem 0;
  padding: 1.05rem 1.15rem;
  border: 0;
  border-radius: 0;
  background: var(--code-bg);
}

li > pre {
  margin-left: 0;
  margin-right: 0;
}

pre code {
  display: block;
  padding: 0;
  background: transparent;
  color: var(--code-text);
  font-size: 0.74em;
  line-height: 1.7;
  white-space: pre;
}

.hljs-comment,
.hljs-quote { color: var(--syntax-comment); font-style: italic; }
.hljs-keyword,
.hljs-selector-tag,
.hljs-subst { color: var(--syntax-keyword); }
.hljs-string,
.hljs-doctag,
.hljs-regexp { color: var(--syntax-string); }
.hljs-number,
.hljs-literal,
.hljs-symbol,
.hljs-bullet { color: var(--syntax-number); }
.hljs-title,
.hljs-section,
.hljs-name,
.hljs-selector-id,
.hljs-selector-class { color: var(--syntax-title); }
.hljs-attr,
.hljs-attribute,
.hljs-variable,
.hljs-template-variable,
.hljs-type { color: var(--syntax-meta); }
.hljs-built_in,
.hljs-params { color: var(--code-text); }
.hljs-emphasis { font-style: italic; }
.hljs-strong { font-weight: 600; }

table {
  width: 100%;
  border-collapse: collapse;
  margin-top: 1.5rem;
  margin-bottom: 1.5rem;
  font-size: 0.92em;
}

th, td {
  padding: 0.45rem 0.6rem;
  border-bottom: 1px solid var(--rule);
  text-align: left;
  vertical-align: top;
}

th { font-weight: 600; }

img {
  display: block;
  max-width: 100%;
  height: auto;
  margin: 1.8rem auto 1.8rem 0;
}

.mermaid {
  overflow: auto;
  width: 100%;
  max-width: 100%;
  margin: 1.8rem auto 1.8rem 0;
  padding: 1rem;
  border: 1px solid var(--rule);
  background: color-mix(in srgb, var(--page), var(--code-bg) 55%);
}

.mermaid svg {
  display: block;
  max-width: 100%;
  height: auto;
  margin: 0 auto;
}

@media (max-width: 680px) {
  body { font-size: 18px; }
  main { padding: 1.35rem 1.1rem 3rem; }
  :root { --measure: 100%; }
  main > :where(h1, h2, h3, h4, p, ul, ol, blockquote, hr, table) { max-width: 100%; }
  h1 { font-size: clamp(2.3rem, 13vw, 3.6rem); }
}
</style>
</head>
<body>
<main>${body}</main>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
<script>
(() => {
  const mermaidBlocks = document.querySelectorAll('pre > code.language-mermaid, pre > code.lang-mermaid');

  for (const code of mermaidBlocks) {
    const container = document.createElement('div');
    container.className = 'mermaid';
    container.textContent = code.textContent;
    code.parentElement.replaceWith(container);
  }

  if (!window.mermaid || mermaidBlocks.length === 0) {
    return;
  }

  const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  window.mermaid.initialize({
    startOnLoad: false,
    theme: prefersDark ? 'dark' : 'default',
    securityLevel: 'strict',
  });
  window.mermaid.run({ querySelector: '.mermaid' });
})();
</script>
</body>
</html>`;

const CLEANUP_DELAY_MS = 60_000;

export default function (pi: ExtensionAPI) {
  pi.registerCommand("preview", {
    description: "Preview last assistant message as HTML in the browser",
    handler: async (_args, ctx) => {
      const entries = ctx.sessionManager.getBranch();

      let lastAssistantText = "";
      for (let i = entries.length - 1; i >= 0; i--) {
        const entry = entries[i];
        if (entry.type === "message" && entry.message.role === "assistant") {
          const content = entry.message.content;
          if (typeof content === "string") {
            lastAssistantText = content;
          } else if (Array.isArray(content)) {
            lastAssistantText = content
              .filter((block) => block.type === "text")
              .map((block) => block.text)
              .join("\n");
          }
          break;
        }
      }

      if (!lastAssistantText) {
        ctx.ui.notify("No assistant message found", "warning");
        return;
      }

      const html = HTML_TEMPLATE(await marked.parse(lastAssistantText, { renderer }));
      const filepath = join(tmpdir(), `pi-preview-${Date.now()}.html`);
      writeFileSync(filepath, html, "utf-8");
      exec(`open "${filepath}"`);
      ctx.ui.notify("Opened preview in browser", "info");

      setTimeout(() => {
        try {
          unlinkSync(filepath);
        } catch {}
      }, CLEANUP_DELAY_MS);
    },
  });
}
