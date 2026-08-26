# Pi Helicopter

<p align="center">
  <img src="docs/screenshots/icon.png" width="96" alt="Pi Helicopter app icon">
</p>

Pi Helicopter shows local [Pi](https://pi.dev) usage in the macOS menu bar. It reads session data from `~/.pi/agent/sessions`.

<p align="center">
  <img src="docs/screenshots/menu.png" width="300" alt="Pi Helicopter menu">
</p>

## Features

- View costs, tokens, models, projects, languages, and tools.
- Filter usage by date range.
- Use Settings to choose the currency, launch at login, and show the Pi sessions folder in Finder.
- See when an update is available.

## Requirements

Pi Helicopter requires macOS 13 or later and Swift 5.10 or later to build.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/duarteocarmo/pi-tools/master/packages/pi-helicopter/install.sh | bash
```

To install it manually:

```sh
brew tap duarteocarmo/pi-tools https://github.com/duarteocarmo/pi-tools
brew install --cask duarteocarmo/pi-tools/pi-helicopter
```

Pi Helicopter is ad hoc signed. If macOS blocks the first launch, open System Settings and select Privacy & Security. Scroll to Security, click Open Anyway for Pi Helicopter, then confirm Open.

## Build

```sh
make build
open "build/Pi Helicopter.app"
```

Run the tests with `make test`.

The build uses an ad hoc signature. macOS may ask you to confirm that you want to open the app when you move it to another Mac.

## Release

The [release workflow](../../.github/workflows/release-pi-helicopter.yml) creates a patch release when app code reaches `master`. It also updates the [Homebrew cask](../../Casks/pi-helicopter.rb).

Part of [pi-tools](https://github.com/duarteocarmo/pi-tools).
