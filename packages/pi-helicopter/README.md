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
- Convert costs to USD, EUR, JPY, GBP, or CNY.
- Start the app when you log in.

## Requirements

Pi Helicopter requires macOS 13 or later and Swift 5.10 or later to build.

## Install

```sh
brew install --cask duarteocarmo/tap/pi-helicopter
```

After installation, open Applications in Finder. Control-click Pi Helicopter, select Open, then confirm Open.

## Build

```sh
make build
open "build/Pi Helicopter.app"
```

Run the tests with `make test`.

The build uses an ad hoc signature. macOS may ask you to confirm that you want to open the app when you move it to another Mac.
