# Screen Time Tracker

Track time spent in applications on Dank Material Shell. View daily and weekly screen time breakdowns with per-app stats, progress toward daily goals, and focus mode awareness.

## Features

- **Automatic tracking** — polls active window every 2 seconds via `hyprctl` / `niri msg`
- **Daily & weekly stats** — bar pill shows today's total; popout shows per-app breakdown and weekly heatmap
- **Daily goal** — configurable target with progress ring indicator
- **App ignore list** — exclude browsers, chat apps, etc. from tracking
- **Data persistence** — 30-day rolling history stored in plugin state
- **IPC commands** — `dms ipc call screenTimeTracker getStatus` / `resetToday`

## Installation

```bash
# Clone or copy to DMS plugins directory
cp -r screen-time-tracker ~/.config/DankMaterialShell/plugins/screenTimeTracker

# Restart DMS
dms restart
```

Then enable the plugin from **Settings → Plugins** and add the widget to your bar.

## Requirements

- DMS >= 1.5.0
- Hyprland or Niri (for window focus detection)

## Usage

- The bar pill shows today's total time with a progress ring
- Click to open the popout showing per-app breakdown and weekly heatmap
- Configure daily goal and ignored apps in **Settings → Plugins → Screen Time Tracker**
- `dms ipc call screenTimeTracker resetToday` to reset today's data

## Data Storage

Data is stored in `~/.local/state/DankMaterialShell/plugins/screenTimeTracker_state.json`. Old entries (>30 days) are automatically pruned.
