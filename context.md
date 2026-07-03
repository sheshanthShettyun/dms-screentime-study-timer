# Screen Time & Study Timer Tracker — Context

## Files
- `ScreenTimeWidget.qml` (1569 lines) — main plugin: backend tracker, bar pill, popout with two modes
- `ScreenTimeSettings.qml` (473 lines) — settings: daily goal, ignored apps, pomodoro durations
- `plugin.json` — plugin metadata
- `README.md` — docs with screenshots

## Architecture

### Modes
- **General** — screen time view (today summary, app list, week chart, goal input)
- **Study Mode** — Pomodoro + Timer, toggled via pill at top of popout

### Mode Switching
- Two `Column`s (`regularContent` + `studyContent`) are direct children of `contentArea` Item with `clip: true`
- Each slides via `x` binding: `generalContent.x = studyMode ? -width : 0`, `studyContent.x = studyMode ? 0 : width`
- `Behavior on x` with `NumberAnimation { duration: 300 }` creates the slide

### Study Mode Sub-Modes
- `studySubMode` property: `"pomodoro"` or `"timer"`
- Sub-mode toggle pill below summary card
- Pomodoro card has `visible: studySubMode === "pomodoro"`
- Timer card has `visible: studySubMode === "timer"`

### App Launching
- `__launcher` Process runs `gtk-launch` with `Paths.moddedAppId(appId)`
- `launchApp(appId)` function called from MouseArea in app list delegates
- Both main app list and selected-day detail list have click-to-open

### Animations
- **Mode switch**: slide (300ms, InOutQuad) via `Behavior on x` on Columns
- **Sub-mode switch**: no animation (visibility toggle)
- **App list items**: staggered slide-in from top (fade + translate y: -20)
  - 40ms stagger per item via Timer in delegates
  - `Behavior on opacity` (200ms) + `Behavior on Translate.y` (250ms, OutQuad)
- **Detail list items**: same pattern with 30ms stagger, smaller slide (-15px)

## Key Dependencies
- `gtk-launch` for opening apps from WM_CLASS
- `DesktopEntries.heuristicLookup` + `Paths.moddedAppId` for desktop file lookup
- `PluginGlobalVar` for cross-component state sync
- `Process` for window tracking and app launching

## Known Gotchas
- `pluginData` fields must be set directly (`pluginData.dailyGoal = value`)
- `PluginGlobalVar.onValueChanged` may fire during init before `root` properties are ready — defer with `Qt.callLater`
- `Paths.moddedAppId` converts raw WM_CLASS to desktop file name (e.g. `"zen-browser"` → `"zen-browser.desktop"`)
- Animation timers use `index * 40ms` stagger — max ~400ms for 10 items
