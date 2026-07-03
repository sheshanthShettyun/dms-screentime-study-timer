import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
  id: root

  property string currentAppId: ""
  property string currentAppClass: ""
  property string todayKey: ""
  property var dayData: ({})
  property var sessionStartTime: 0

  property int dailyGoal: configuredDailyGoal()
  property string ignoredApps: pluginData.ignoredApps ? String(pluginData.ignoredApps) : ""

  PluginGlobalVar { id: globalTodayTotal; varName: "todayTotal"; defaultValue: 0 }
  PluginGlobalVar { id: globalCurrentApp; varName: "currentApp"; defaultValue: "" }
  PluginGlobalVar { id: globalCurrentAppClass; varName: "currentAppClass"; defaultValue: "" }
  PluginGlobalVar { id: globalTodayBreakdown; varName: "todayBreakdown"; defaultValue: "{}" }
  PluginGlobalVar { id: globalWeekData; varName: "weekData"; defaultValue: "{}" }
  PluginGlobalVar { id: globalDailyGoal; varName: "dailyGoal"; defaultValue: 0 }

  PropertyGroup {
    id: tracked
    property var apps: ({})
  }

  SystemClock {
    id: clock
    precision: SystemClock.Seconds
    onDateChanged: {
      if (todayKey !== getDateKey()) checkDayRollover()
    }
  }

  Timer {
    id: pollTimer
    interval: 2000
    running: true
    repeat: true
    onTriggered: pollActiveWindow()
  }

  Timer {
    id: flushTimer
    interval: 15000
    running: true
    repeat: true
    onTriggered: flushState()
  }

  Timer {
    id: syncGlobalsTimer
    interval: 3000
    running: true
    repeat: true
    onTriggered: syncGlobals()
  }

  Component.onCompleted: {
    todayKey = getDateKey()
    loadState()
    pollActiveWindow()
    syncGlobals()
  }

  function getDateKey(): string {
    var d = new Date()
    return d.getFullYear() + "-" +
      String(d.getMonth() + 1).padStart(2, "0") + "-" +
      String(d.getDate()).padStart(2, "0")
  }

  function getWeekKey(): string {
    var d = new Date()
    var start = new Date(d)
    start.setDate(d.getDate() - d.getDay())
    return start.getFullYear() + "-" +
      String(start.getMonth() + 1).padStart(2, "0") + "-" +
      String(start.getDate()).padStart(2, "0")
  }

  function configuredDailyGoal(): int {
    var raw = pluginData.dailyGoal
    if (raw === undefined || raw === null || raw === "") return 0
    var value = Number(raw)
    if (!isFinite(value) || value < 0) return 0
    return Math.floor(value)
  }

  function checkDayRollover(): void {
    var newKey = getDateKey()
    if (newKey !== todayKey) {
      flushState()
      todayKey = newKey
      if (!dayData) dayData = ({})
      syncGlobals()
    }
  }

  function isAppIgnored(appId: string): bool {
    if (!ignoredApps || ignoredApps.trim() === "") return false
    var list = ignoredApps.split(",")
    for (var i = 0; i < list.length; i++) {
      if (list[i].trim().toLowerCase() === appId.toLowerCase()) return true
    }
    return false
  }

  function pollActiveWindow(): void {
    var proc = activeWindowProcessComponent.createObject(root)
    proc.running = true
  }

  Component {
    id: activeWindowProcessComponent
    Process {
      command: [
        "sh", "-c",
        "hyprctl activewindow -j 2>/dev/null || " +
        "(niri msg focused-window 2>/dev/null && echo '') || " +
        "echo '{\"class\":\"unknown\",\"title\":\"Unknown\"}'"
      ]
      stdout: SplitParser {
        onRead: data => {
          var result = data.trim()
          if (!result || result === "") return
          var parsed = parseWindowInfo(result)
          if (parsed && parsed.class) {
            root.onWindowChanged(parsed.class, parsed.title)
          }
        }
      }
      onExited: destroy()
    }
  }

  function parseWindowInfo(raw: string): var {
    if (raw.charAt(0) === "{") {
      try {
        var obj = JSON.parse(raw)
        return { class: obj.class || "unknown", title: obj.title || "" }
      } catch (_) {
        return { class: "unknown", title: "" }
      }
    }
    var lines = raw.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line.startsWith("Window") || line.startsWith("Focused")) {
        var parts = line.split(/\s+/)
        if (parts.length >= 2) return { class: parts[1], title: line }
      }
    }
    return { class: "unknown", title: "" }
  }

  function onWindowChanged(appClass: string, appTitle: string): void {
    var appId = appClass.toLowerCase()
    if (!appId || appId === "") appId = "unknown"

    var now = Date.now()
    if (currentAppId && currentAppId !== "" && sessionStartTime > 0) {
      var elapsed = Math.floor((now - sessionStartTime) / 1000)
      if (elapsed < 0 || elapsed > 86400) elapsed = 0
      if (elapsed > 0 && !isAppIgnored(currentAppId)) {
        if (!dayData[currentAppId]) dayData[currentAppId] = 0
        dayData[currentAppId] += elapsed
      }
    }

    currentAppId = appId
    currentAppClass = appClass
    sessionStartTime = now
    globalCurrentApp.setValue(appTitle || appClass)
    globalCurrentAppClass.setValue(appClass)
  }

  function computeTodayTotal(): int {
    var total = 0
    if (!dayData) return 0
    for (var key in dayData) {
      if (key !== "total" && dayData.hasOwnProperty(key)) total += sanitizeSeconds(dayData[key])
    }
    return total
  }

  function sanitizeSeconds(value): int {
    var n = Number(value)
    if (!isFinite(n) || n < 0) return 0
    return Math.floor(n)
  }

  function computeWeekData(): string {
    var weekKey = getWeekKey()
    var result = {}
    var d = new Date()
    for (var i = 0; i < 7; i++) {
      var date = new Date(d)
      date.setDate(d.getDate() - i)
      var key = date.getFullYear() + "-" +
        String(date.getMonth() + 1).padStart(2, "0") + "-" +
        String(date.getDate()).padStart(2, "0")
      var dayEntry = pluginService.loadPluginState(root.pluginId, "day_" + key)
      result[key] = dayEntry ? dayEntry : {}
    }
    result[weekKey + "_weekTotal"] = 0
    var weekTotal = 0
    for (var dk in result) {
      if (result.hasOwnProperty(dk) && typeof result[dk] === "object") {
        for (var app in result[dk]) {
          if (result[dk].hasOwnProperty(app)) weekTotal += sanitizeSeconds(result[dk][app])
        }
      }
    }
    result["_weekTotal"] = weekTotal
    return JSON.stringify(result)
  }

  function syncGlobals(): void {
    if (!dayData) dayData = ({})
    var liveElapsed = sessionStartTime > 0 ? Math.floor((Date.now() - sessionStartTime) / 1000) : 0
    if (liveElapsed < 0 || liveElapsed > 86400) liveElapsed = 0
    globalTodayTotal.setValue(computeTodayTotal() + liveElapsed)
    globalTodayBreakdown.setValue(JSON.stringify(dayData))
    globalWeekData.setValue(computeWeekData())
    globalDailyGoal.setValue(dailyGoal)
  }

  function loadState(): void {
    var saved = pluginService.loadPluginState(root.pluginId, "day_" + todayKey)
    if (saved) {
      try {
        dayData = sanitizeDayData(saved)
      } catch (_) {
        dayData = ({})
      }
    } else {
      dayData = ({})
    }
  }

  function flushState(): void {
    if (!dayData) return
    var total = computeTodayTotal()
    dayData["total"] = total
    pluginService.savePluginState(root.pluginId, "day_" + todayKey, dayData)

    var cutoff = new Date()
    cutoff.setDate(cutoff.getDate() - 30)
    for (var i = 31; i <= 60; i++) {
      var date = new Date()
      date.setDate(date.getDate() - i)
      var key = date.getFullYear() + "-" +
        String(date.getMonth() + 1).padStart(2, "0") + "-" +
        String(date.getDate()).padStart(2, "0")
      pluginService.removePluginStateKey(root.pluginId, "day_" + key)
    }
  }

  function sanitizeDayData(source): var {
    var result = ({})
    if (!source) return result
    for (var key in source) {
      if (key === "total") continue
      var seconds = sanitizeSeconds(source[key])
      if (seconds > 0) result[key] = seconds
    }
    return result
  }

  IpcHandler {
    function getStatus(): string {
      return JSON.stringify({
        currentApp: root.currentAppClass,
        todayTotal: root.computeTodayTotal(),
        breakdown: root.dayData
      })
    }
    function resetToday(): string {
      dayData = ({})
      currentAppId = ""
      sessionStartTime = 0
      pluginService.savePluginState(root.pluginId, "day_" + todayKey, ({}))
      syncGlobals()
      return "Today's data reset"
    }
    target: "screenTimeTracker"
  }
}
