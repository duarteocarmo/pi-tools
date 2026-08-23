# Duarte's tools for pi

Just stuff I use.

## Install all Pi tools

Install every Pi package in this repository from Git:

```sh
pi install git:github.com/duarteocarmo/pi-tools
```

A Git installation loads every Pi package listed below, except Pi Helicopter. To install only one package, use its npm installation command.

| Package | What it does |
| --- | --- |
| [`@duarteocarmo/pi-jumper`](./packages/pi-jumper) | Lists live Pi sessions and jumps between tmux panes. |
| [`@duarteocarmo/pi-no-sleep`](./packages/pi-no-sleep) | Prevents macOS display sleep while enabled. |
| [`@duarteocarmo/pi-preview`](./packages/pi-preview) | Opens the latest assistant response as HTML in a browser. |
| [`@duarteocarmo/pi-session-breakdown`](./packages/pi-session-breakdown) | Shows session, message, token, and cost statistics. |
| [`@duarteocarmo/pi-subagents`](./packages/pi-subagents) | Runs bounded isolated Pi subagents. |
| [`@duarteocarmo/pi-modus-themes`](./packages/pi-modus-themes) | Provides Modus themes and follows macOS light or dark appearance. |
| [`pi-helicopter`](./packages/pi-helicopter) | Shows local Pi usage in the macOS menu bar. |
