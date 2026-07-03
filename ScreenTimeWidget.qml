import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
  id: root

  property string currentAppTitle: ""
  property string todayKey: getDateKey()
  property var dayData: ({})
  property int displayTodayTotal: 0

  // ── display state (rebuilt from dayData) ──
  property var sortedApps: []
  property var weekItems: []
  property string selectedDayKey: ""
  property var selectedDayApps: []

  // ── settings ──
  property int dailyGoal: configuredDailyGoal()
  property string ignoredApps: pluginData.ignoredApps ? String(pluginData.ignoredApps) : ""
  property int cardRadius: 14
  property color accentColor: "#c79ae6"
  property color dangerColor: "#ff7a90"
  property color panelBorder: Qt.rgba(1, 1, 1, 0.07)
  property color mutedFill: Qt.rgba(1, 1, 1, 0.045)

  // Goal-input field state. Bound from dailyGoal so changes from presets,
  // IPC, or settings all keep the inputs in sync.
  property string goalInputText: dailyGoal > 0 ? fmtShort(dailyGoal) : ""
  onDailyGoalChanged: { goalInputText = dailyGoal > 0 ? fmtShort(dailyGoal) : "" }

  // ── modes ──
  property bool studyMode: false
  property int focusTimeToday: 0

  // ── pomodoro ──
  property string pomodoroState: "idle"
  property int pomodoroRemaining: 0
  property int pomodoroDuration: 0
  property int pomodoroCycle: 0
  property bool pomodoroRunning: false

  // ── study timer ──
  property string studyTimerState: "idle"
  property int studyTimerRemaining: 0
  property int studyTimerDuration: 0
  property bool studyTimerRunning: false
  property string studySubMode: "pomodoro"
  property string studyTimerInput: ""

  PluginGlobalVar { id: globalTodayTotal; varName: "todayTotal"; defaultValue: 0 }
  PluginGlobalVar { id: globalCurrentApp; varName: "currentApp"; defaultValue: "" }
  PluginGlobalVar { id: globalTodayBreakdown; varName: "todayBreakdown"; defaultValue: "{}" }
  PluginGlobalVar { id: globalWeekData; varName: "weekData"; defaultValue: "{}" }
  PluginGlobalVar { id: globalDailyGoal; varName: "dailyGoal"; defaultValue: 28800 }

  // ═══════════════════════════════════════
  //  INIT
  // ═══════════════════════════════════════

  Component.onCompleted: {
    todayKey = getDateKey()
    __loadSavedState()
    rebuildDisplay()
  }

  // ═══════════════════════════════════════
  //  TIMERS
  // ═══════════════════════════════════════

  SystemClock {
    id: clock
    precision: SystemClock.Seconds
    onDateChanged: {
      var newKey = getDateKey()
      if (newKey !== root.todayKey) {
        root.todayKey = newKey
        root.dayData = ({})
        root.focusTimeToday = 0
        root.rebuildDisplay()
      }
    }
  }

  Timer {
    id: rebuildTimer
    interval: 3000
    running: true
    repeat: true
    onTriggered: rebuildDisplay()
  }

  function configuredDailyGoal(): int {
    var raw = pluginData.dailyGoal
    if (raw === undefined || raw === null || raw === "") {
      raw = globalDailyGoal.value
    }
    if (raw === undefined || raw === null || raw === "") return 0
    var value = Number(raw)
    if (!isFinite(value) || value < 0) return 0
    return Math.floor(value)
  }

  function getFocusDuration(): int {
    var raw = pluginData.focusDuration
    if (raw === undefined || raw === null || raw === "") return 1500
    return Math.floor(Number(raw)) || 1500
  }

  function getShortBreakDuration(): int {
    var raw = pluginData.shortBreakDuration
    if (raw === undefined || raw === null || raw === "") return 300
    return Math.floor(Number(raw)) || 300
  }

  function getLongBreakDuration(): int {
    var raw = pluginData.longBreakDuration
    if (raw === undefined || raw === null || raw === "") return 900
    return Math.floor(Number(raw)) || 900
  }

  function isAppIgnored(appId: string): bool {
    if (!ignoredApps || ignoredApps.trim() === "") return false
    var list = ignoredApps.split(",")
    for (var i = 0; i < list.length; i++) {
      if (list[i].trim().toLowerCase() === appId.toLowerCase()) return true
    }
    return false
  }

  Timer {
    id: pomodoroTimer
    interval: 1000
    running: pomodoroRunning
    repeat: true
    onTriggered: {
      if (pomodoroRemaining <= 0) {
        pomodoroRunning = false
        root.advancePomodoro()
        return
      }
      pomodoroRemaining--
      if (pomodoroState === "focus") root.focusTimeToday++
    }
  }

  function startPomodoro(): void {
    if (pomodoroState === "idle") {
      pomodoroState = "focus"
      pomodoroCycle = 0
    }
    var dur = pomodoroState === "focus" ? getFocusDuration()
      : pomodoroState === "shortBreak" ? getShortBreakDuration()
      : getLongBreakDuration()
    pomodoroRemaining = dur
    pomodoroDuration = dur
    pomodoroRunning = true
  }

  function pausePomodoro(): void {
    pomodoroRunning = false
  }

  function resetPomodoro(): void {
    pomodoroRunning = false
    pomodoroState = "idle"
    pomodoroRemaining = 0
    pomodoroDuration = 0
    pomodoroCycle = 0
  }

  function advancePomodoro(): void {
    if (pomodoroState === "focus") {
      pomodoroCycle++
      if (pomodoroCycle >= 4) {
        pomodoroState = "longBreak"
      } else {
        pomodoroState = "shortBreak"
      }
    } else {
      if (pomodoroState === "longBreak") pomodoroCycle = 0
      pomodoroState = "focus"
    }
    var dur = pomodoroState === "focus" ? getFocusDuration()
      : pomodoroState === "shortBreak" ? getShortBreakDuration()
      : getLongBreakDuration()
    pomodoroRemaining = dur
    pomodoroDuration = dur
    pomodoroRunning = true
  }

  function formatCountdown(seconds: int): string {
    if (seconds <= 0 && pomodoroState === "idle") return "00:00"
    if (seconds <= 0) return "00:00"
    var m = Math.floor(seconds / 60)
    var s = seconds % 60
    return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
  }

  function pomodoroProgress(): real {
    if (pomodoroDuration <= 0) return 0
    return 1 - (pomodoroRemaining / pomodoroDuration)
  }

  function pomodoroLabel(): string {
    if (pomodoroState === "idle") return "Ready"
    if (pomodoroState === "focus") return "Focus"
    if (pomodoroState === "shortBreak") return "Short Break"
    return "Long Break"
  }

  // ── study timer ──

  Timer {
    id: studyTimer
    interval: 1000
    running: studyTimerRunning
    repeat: true
    onTriggered: {
      if (studyTimerRemaining <= 0) {
        studyTimerRunning = false
        studyTimerState = "idle"
        return
      }
      studyTimerRemaining--
      root.focusTimeToday++
    }
  }

  function startStudyTimer(): void {
    if (studyTimerState === "idle") {
      studyTimerRemaining = studyTimerDuration
    }
    studyTimerRunning = true
    studyTimerState = "running"
  }

  function pauseStudyTimer(): void {
    studyTimerRunning = false
    studyTimerState = "paused"
  }

  function resetStudyTimer(): void {
    studyTimerRunning = false
    studyTimerState = "idle"
    studyTimerRemaining = 0
    studyTimerDuration = 0
  }

  function setStudyTimerPreset(seconds: int): void {
    studyTimerDuration = seconds
    studyTimerRemaining = seconds
    studyTimerState = "idle"
    studyTimerRunning = false
  }

  function applyStudyTimerInput(): void {
    var raw = studyTimerInput.trim().toLowerCase()
    if (!raw) return
    var hMatch = raw.match(/(\d+)\s*h/)
    var mMatch = raw.match(/(\d+)\s*m(?!\s*h)/)
    var h = hMatch ? parseInt(hMatch[1]) : 0
    var m = mMatch ? parseInt(mMatch[1]) : 0
    if (h > 0 || m > 0) {
      var total = (h * 3600) + (m * 60)
      setStudyTimerPreset(total)
      return
    }
    var num = Number(raw)
    if (isFinite(num) && num >= 0) {
      setStudyTimerPreset(Math.floor(num))
    }
  }

  // ═══════════════════════════════════════
  //  DATA PERSISTENCE
  // ═══════════════════════════════════════

  function getDateKey(): string {
    var d = new Date()
    return d.getFullYear() + "-" +
      String(d.getMonth() + 1).padStart(2, "0") + "-" +
      String(d.getDate()).padStart(2, "0")
  }

  function liveTodayTotal(): int {
    return displayTodayTotal
  }

  function rebuildDisplay(): void {
    dailyGoal = configuredDailyGoal()
    currentAppTitle = String(globalCurrentApp.value || "")
    displayTodayTotal = sanitizeSeconds(globalTodayTotal.value)

    var list = []
    for (var key in dayData) {
      if (key !== "total") {
        var seconds = sanitizeSeconds(dayData[key])
        if (seconds > 0) list.push({ app: key, time: seconds })
      }
    }
    list.sort(function(a, b) { return b.time - a.time })
    sortedApps = list

    var weekSource = parseJsonValue(globalWeekData.value)
    var items = []
    var d = new Date()
    for (var i = 6; i >= 0; i--) {
      var date = new Date(d)
      date.setDate(d.getDate() - i)
      var k = date.getFullYear() + "-" +
        String(date.getMonth() + 1).padStart(2, "0") + "-" +
        String(date.getDate()).padStart(2, "0")
      var saved = weekSource[k]
      var dayTotal = 0
      if (saved && typeof saved === "object") {
        for (var app in saved) {
          if (app !== "total") dayTotal += sanitizeSeconds(saved[app])
        }
      }
      if (k === todayKey) dayTotal = displayTodayTotal
      items.push({ key: k, total: dayTotal, label: getWeekdayLabel(k) })
    }
    var maxVal = 1
    for (var j = 0; j < items.length; j++) {
      maxVal = Math.max(maxVal, items[j].total)
    }
    for (var j2 = 0; j2 < items.length; j2++) {
      items[j2].max = maxVal
    }
    weekItems = items
    if (selectedDayKey) {
      var found = false
      for (var i = 0; i < items.length; i++) {
        if (items[i].key === selectedDayKey) { found = true; break }
      }
      if (!found) { selectedDayKey = ""; selectedDayApps = [] }
    }
  }

  function selectDay(key: string): void {
    if (key === selectedDayKey) {
      selectedDayKey = ""
      selectedDayApps = []
      return
    }
    selectedDayKey = key
    var weekSource = parseJsonValue(globalWeekData.value)
    var raw = weekSource[key]
    if (key === todayKey) raw = dayData
    var list = []
    if (raw && typeof raw === "object") {
      for (var app in raw) {
        if (app !== "total") {
          var seconds = sanitizeSeconds(raw[app])
          if (seconds > 0) list.push({ app: app, time: seconds })
        }
      }
      list.sort(function(a, b) { return b.time - a.time })
    }
    selectedDayApps = list
  }

  // ═══════════════════════════════════════
  //  FORMATTING HELPERS
  // ═══════════════════════════════════════

  function fmtShort(s: int): string {
    if (s <= 0) return "0m"
    var h = Math.floor(s / 3600)
    var m = Math.floor((s % 3600) / 60)
    return h > 0 ? h + "h " + m + "m" : m + "m"
  }

  function fmtLong(s: int): string {
    var h = Math.floor(s / 3600)
    var m = Math.floor((s % 3600) / 60)
    var sec = s % 60
    return String(h).padStart(2, "0") + ":" +
      String(m).padStart(2, "0") + ":" +
      String(sec).padStart(2, "0")
  }

  function progress(): real {
    if (dailyGoal <= 0) return 0
    var goal = dailyGoal
    return Math.min(liveTodayTotal() / goal, 1.0)
  }

  function progressPercent(): int {
    return Math.round(progress() * 100)
  }

  function applyGoalFromInput(): void {
    var raw = goalInputText.trim().toLowerCase()
    if (!raw) { dailyGoal = 0; pluginData.dailyGoal = 0; return }

    var hMatch = raw.match(/(\d+)\s*h/)
    var mMatch = raw.match(/(\d+)\s*m(?!\s*h)/)
    var h = hMatch ? parseInt(hMatch[1]) : 0
    var m = mMatch ? parseInt(mMatch[1]) : 0
    if (h > 0 || m > 0) {
      dailyGoal = (h * 3600) + (m * 60)
      pluginData.dailyGoal = dailyGoal
      return
    }

    var num = Number(raw)
    if (isFinite(num) && num >= 0) {
      dailyGoal = Math.floor(num)
      pluginData.dailyGoal = Math.floor(num)
    }
  }

  function sanitizeSeconds(value): int {
    var n = Number(value)
    if (!isFinite(n) || n < 0) return 0
    return Math.floor(n)
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

  function parseJsonValue(raw): var {
    if (!raw || raw === "") return ({})
    if (typeof raw === "object") return raw
    try {
      return JSON.parse(String(raw))
    } catch (_) {
      return ({})
    }
  }

  function remainingToGoal(): int {
    if (dailyGoal <= 0) return 0
    return Math.max(dailyGoal - liveTodayTotal(), 0)
  }

  function topShare(seconds: int): int {
    var total = Math.max(liveTodayTotal(), 1)
    return Math.round((seconds / total) * 100)
  }

  function appName(key: string): string {
    if (key === "unknown") return "Other"
    return key.charAt(0).toUpperCase() + key.slice(1)
  }

  function getWeekdayLabel(k: string): string {
    var parts = k.split("-")
    if (parts.length !== 3) return k
    var dt = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]))
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][dt.getDay()]
  }

  // ═══════════════════════════════════════
  //  IPC
  // ═══════════════════════════════════════

  IpcHandler {
    function getStatus(): string {
      return JSON.stringify({
        currentApp: root.currentAppTitle,
        todayTotal: root.liveTodayTotal(),
        breakdown: root.dayData,
        dailyGoal: root.dailyGoal
      })
    }
    function resetToday(): string {
      pluginService.savePluginState(root.pluginId, "day_" + root.todayKey, ({}))
      root.dayData = ({})
      var now = Date.now()
      root.__sessionStart = now
      root.__lastTick = now
      root.rebuildDisplay()
      return "Today's data reset"
    }
    target: "screenTimeTracker"
  }

  // ═══════════════════════════════════════════
  //  BACKEND — window focus tracking
  // ═══════════════════════════════════════════

  property string __currentAppId: ""
  property string __currentAppClass: ""
  property var __sessionStart: 0
  property var __lastTick: 0
  property bool __initialized: false

  SystemClock {
    id: __clock
    precision: SystemClock.Seconds
    onDateChanged: {
      var k = getDateKey()
      if (k !== root.todayKey) {
        __flushState()
        root.todayKey = k
        root.dayData = ({})
        root.__initialized = false
        root.__loadSavedState()
      }
    }
  }

  Timer {
    id: __flushTimer
    interval: 15000
    running: true
    repeat: true
    onTriggered: __flushState()
  }

  property var __tracker: Process {
    running: true
    command: ["sh", "-c",
      "while true; do " +
        "hyprctl activewindow -j 2>/dev/null | jq -c . 2>/dev/null || " +
        "(niri msg focused-window 2>/dev/null | jq -c . 2>/dev/null) || " +
        "echo '{\"class\":\"unknown\",\"title\":\"\"}'; " +
      "sleep 2; done"
    ]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: data => {
        var raw = data.trim()
        if (!raw || raw.charAt(0) !== "{") return
        try {
          root.__onWindow(JSON.parse(raw))
        } catch (_) {}
      }
    }
  }

  Process {
    id: __launcher
    running: false
  }

  function launchApp(appId: string): void {
    if (!appId || appId === "unknown") return
    try {
      var desktopName = Paths.moddedAppId(appId)
      if (!desktopName) desktopName = appId
      __launcher.command = ["gtk-launch", desktopName]
      __launcher.running = true
    } catch (_) {}
  }

  function __onWindow(info: var): void {
    var appId = String(info.class || "unknown").toLowerCase()
    var now = Date.now()

    if (__currentAppId && __sessionStart > 0) {
      var elapsed = Math.floor((now - __sessionStart) / 1000)
      if (elapsed > 0 && elapsed < 86400 && !isAppIgnored(__currentAppId)) {
        if (!dayData[__currentAppId]) dayData[__currentAppId] = 0
        dayData[__currentAppId] += elapsed
      }
    }

    __currentAppId = appId
    __currentAppClass = info.class || "unknown"
    __sessionStart = now
    currentAppTitle = root.getDisplayAppName(appId)
    __updateGlobals()
  }

  function getDisplayAppName(appId: string): string {
    if (appId === "unknown") return "Other"
    var entry = DesktopEntries.heuristicLookup(Paths.moddedAppId(appId))
    return entry?.name || appName(appId)
  }

  function __safePluginService(): var {
    return typeof pluginService !== "undefined" && pluginService ? pluginService : null
  }

  function __loadSavedState(): void {
    if (__initialized) return
    __initialized = true
    var ps = __safePluginService()
    if (ps) {
      try {
        var saved = ps.loadPluginState(root.pluginId, "day_" + todayKey)
        if (saved && typeof saved === "object") {
          for (var k in saved) {
            if (k !== "total") dayData[k] = Number(saved[k]) || 0
          }
        }
      } catch (_) {}
    }
    var now = Date.now()
    __sessionStart = now
    __lastTick = now
    __updateGlobals()
  }

  function __computeTotal(): int {
    var t = 0
    if (!dayData) return 0
    for (var k in dayData) {
      if (k !== "total") t += Number(dayData[k]) || 0
    }
    return t
  }

  function __updateGlobals(): void {
    var total = __computeTotal()
    globalTodayTotal.set(total)
    globalCurrentApp.set(currentAppTitle)
    globalTodayBreakdown.set(JSON.stringify(dayData || ({})))
    globalDailyGoal.set(dailyGoal > 0 ? dailyGoal : 28800)

    var ps = __safePluginService()
    var weekSource = ({})
    var d = new Date()
    for (var i = 0; i < 7; i++) {
      var date = new Date(d)
      date.setDate(d.getDate() - i)
      var k = date.getFullYear() + "-" +
        String(date.getMonth() + 1).padStart(2, "0") + "-" +
        String(date.getDate()).padStart(2, "0")
      if (k !== todayKey) {
        if (ps) {
          try {
            var saved = ps.loadPluginState(root.pluginId, "day_" + k)
            if (saved && typeof saved === "object") weekSource[k] = saved
          } catch (_) {}
        }
      } else {
        weekSource[k] = JSON.parse(JSON.stringify(dayData || ({})))
      }
    }
    globalWeekData.set(JSON.stringify(weekSource))
  }

  function __flushState(): void {
    var ps = __safePluginService()
    if (!ps || !dayData) return
    var copy = JSON.parse(JSON.stringify(dayData))
    copy["total"] = __computeTotal()
    ps.savePluginState(root.pluginId, "day_" + todayKey, copy)
    for (var i = 31; i <= 60; i++) {
      var dt = new Date()
      dt.setDate(dt.getDate() - i)
      var k = dt.getFullYear() + "-" +
        String(dt.getMonth() + 1).padStart(2, "0") + "-" +
        String(dt.getDate()).padStart(2, "0")
      ps.removePluginStateKey(root.pluginId, "day_" + k)
    }
  }

  // ═══════════════════════════════════════════════════════
  //  UI
  // ═══════════════════════════════════════════════════════

  horizontalBarPill: Component {
    Item {
      implicitWidth: pillRow.width + 12
      implicitHeight: 22
      width: implicitWidth
      height: 22

      Rectangle {
        anchors.fill: parent
        radius: 11
        color: Theme.withAlpha(Theme.primary, 0.08)
      }

      Row {
        id: pillRow
        anchors.centerIn: parent
        spacing: 3

        DankIcon {
          anchors.verticalCenter: parent.verticalCenter
          name: root.pomodoroState !== "idle" ? "timer" : "schedule"
          size: Theme.barIconSize(root.barThickness, -2)
          color: root.pomodoroState === "focus" ? root.accentColor : Theme.widgetIconColor
        }

        StyledText {
          text: root.pomodoroState !== "idle"
            ? root.formatCountdown(root.pomodoroRemaining)
            : root.fmtShort(root.liveTodayTotal())
          color: Theme.surfaceText
          font.pixelSize: 11
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }

  verticalBarPill: Component {
    Item {
      width: 14
      height: parent.height

      Canvas {
        anchors.centerIn: parent
        width: 12
        height: 12
        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          var cx = width / 2, cy = height / 2, r = 4.8, lw = 1.4
          ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2)
          ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.18)
          ctx.lineWidth = lw
          ctx.stroke()
          var ratio = root.progress()
          if (ratio > 0) {
            ctx.beginPath()
            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * ratio)
            ctx.strokeStyle = ratio >= 1 ? root.dangerColor : root.accentColor
            ctx.lineWidth = lw
            ctx.lineCap = "round"
            ctx.stroke()
          }
        }
        Timer {
          interval: 5000; running: true; repeat: true
          onTriggered: parent.requestPaint()
        }
      }
    }
  }

  popoutContent: Component {
    PopoutComponent {
      id: popout

      Column {
        id: col
        width: 360
        spacing: 0
        padding: 0

        Rectangle {
          width: parent.width
          height: 30
          radius: 15
          color: Qt.rgba(1, 1, 1, 0.045)

          Item {
            anchors.fill: parent

            Rectangle {
              width: parent.width / 2
              height: parent.height
              radius: 15
              color: !root.studyMode ? root.accentColor : "transparent"
              Behavior on color { ColorAnimation { duration: 200 } }

              StyledText {
                anchors.centerIn: parent
                text: "General"
                color: !root.studyMode ? "#fff" : Theme.surfaceVariantText
                font.pixelSize: 11
                font.bold: !root.studyMode
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.studyMode = false
              }
            }

            Rectangle {
              anchors.left: parent.horizontalCenter
              width: parent.width / 2
              height: parent.height
              radius: 15
              color: root.studyMode ? root.accentColor : "transparent"
              Behavior on color { ColorAnimation { duration: 200 } }

              StyledText {
                anchors.centerIn: parent
                text: "Study Mode"
                color: root.studyMode ? "#fff" : Theme.surfaceVariantText
                font.pixelSize: 11
                font.bold: root.studyMode
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.studyMode = true
              }
            }
          }
        }

        Item {
          id: contentArea
          width: parent.width
          height: Math.max(regularContent.height, studyContent.height)
          clip: true

          Row {
            x: root.studyMode ? -parent.width : 0
            Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

            Column {
              id: regularContent
              width: col.width
              spacing: 12
              padding: Theme.spacingMD

              Rectangle {
                width: parent.width
                radius: root.cardRadius
                color: Theme.surfaceContainer
                border.color: root.panelBorder
                border.width: 1
                implicitHeight: summaryCol.implicitHeight + 24

          Column {
            id: summaryCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 10

            Row {
              width: parent.width
              spacing: 12

              Column {
                width: parent.width - 92
                spacing: 3

                StyledText {
                  text: "Today"
                  color: Theme.surfaceVariantText
                  font.pixelSize: 11
                }

                StyledText {
                  text: root.fmtLong(root.liveTodayTotal())
                  color: Theme.surfaceText
                  font.pixelSize: 24
                  font.bold: true
                }

                StyledText {
                  text: root.dailyGoal <= 0
                    ? "No daily goal set"
                    : root.progress() >= 1
                    ? "Daily goal reached"
                    : root.fmtShort(root.remainingToGoal()) + " left to hit your goal"
                  color: Theme.surfaceVariantText
                  font.pixelSize: 10
                }
              }

              Item {
                width: 80
                height: 80

                Canvas {
                  id: bigRing
                  anchors.centerIn: parent
                  width: 68
                  height: 68
                  onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    var cx = width / 2, cy = height / 2, r = 30, lw = 5
                    ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2)
                    ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.10); ctx.lineWidth = lw; ctx.stroke()
                    var ratio = root.progress()
                    if (ratio > 0) {
                      ctx.beginPath()
                      ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * ratio)
                      ctx.strokeStyle = ratio >= 1 ? root.dangerColor : root.accentColor
                      ctx.lineWidth = lw
                      ctx.lineCap = "round"
                      ctx.stroke()
                    }
                  }
                  Timer {
                    interval: 5000; running: true; repeat: true
                    onTriggered: bigRing.requestPaint()
                  }
                }

                StyledText {
                  anchors.centerIn: parent
                  text: root.progressPercent() + "%"
                  color: Theme.surfaceText
                  font.pixelSize: 12
                  font.bold: true
                }
              }
            }

            Row {
              width: parent.width
              spacing: 8

              Rectangle {
                width: (parent.width - 8) / 2
                height: 48
                radius: 10
                color: root.mutedFill

                Column {
                  anchors.fill: parent
                  anchors.margins: 8
                  spacing: 2

                  StyledText {
                    text: "Goal"
                    color: Theme.surfaceVariantText
                    font.pixelSize: 9
                  }

                  StyledText {
                    text: root.dailyGoal > 0 ? root.fmtShort(root.dailyGoal) : "Not set"
                    color: Theme.surfaceText
                    font.pixelSize: 12
                    font.bold: true
                  }
                }
              }

              Rectangle {
                width: (parent.width - 8) / 2
                height: 48
                radius: 10
                color: root.mutedFill

                Column {
                  anchors.fill: parent
                  anchors.margins: 8
                  spacing: 2

                  StyledText {
                    text: "Now"
                    color: Theme.surfaceVariantText
                    font.pixelSize: 9
                  }

                  StyledText {
                    text: root.currentAppTitle || "No active app"
                    color: Theme.surfaceText
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                  }
                }
              }
            }

            Row {
              width: parent.width
              spacing: 6

              DankTextField {
                width: parent.width
                height: 32
                text: root.goalInputText
                placeholderText: "e.g. 2h 30m or 90m or 8h"
                font.pixelSize: 12
                backgroundColor: root.mutedFill
                normalBorderColor: "transparent"
                cornerRadius: 8
                onTextEdited: root.goalInputText = text
                onEditingFinished: root.applyGoalFromInput()
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          radius: root.cardRadius
          color: Theme.surfaceContainer
          border.color: root.panelBorder
          border.width: 1
          implicitHeight: appsCol.implicitHeight + 24

          Column {
            id: appsCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 10

            StyledText {
              text: "Apps today"
              color: Theme.surfaceText
              font.pixelSize: 12
              font.bold: true
            }

            StyledText {
              visible: root.sortedApps.length === 0
              text: "No tracked activity yet."
              color: Theme.surfaceVariantText
              font.pixelSize: 10
            }

            Repeater {
              model: root.sortedApps

              delegate: Rectangle {
                width: appsCol.width
                height: 54
                radius: 10
                color: root.mutedFill
                opacity: 0
                transform: Translate {
                  id: appSlide
                  y: -20
                  Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }
                }

                Timer {
                  interval: index * 40
                  running: true
                  onTriggered: {
                    parent.opacity = 1
                    appSlide.y = 0
                  }
                }

                Behavior on opacity { NumberAnimation { duration: 200 } }

                Column {
                  anchors.fill: parent
                  anchors.margins: 8
                  spacing: 6

                  Row {
                    width: parent.width
                    spacing: 6

                    AppIconRenderer {
                      width: 20
                      height: 20
                      iconValue: {
                        var entry = DesktopEntries.heuristicLookup(Paths.moddedAppId(modelData.app))
                        return entry?.icon || modelData.app
                      }
                      iconSize: 20
                      fallbackText: root.getDisplayAppName(modelData.app).charAt(0)
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                      text: root.getDisplayAppName(modelData.app)
                      color: Theme.surfaceText
                      font.pixelSize: 12
                      font.bold: true
                      width: parent.width - 80
                      elide: Text.ElideRight
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                      text: root.fmtShort(modelData.time)
                      color: Theme.surfaceVariantText
                      font.pixelSize: 10
                      width: 46
                      horizontalAlignment: Text.AlignRight
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  Rectangle {
                    width: parent.width
                    height: 8
                    radius: 4
                    color: Qt.rgba(1, 1, 1, 0.08)

                    Rectangle {
                      width: Math.max(8, parent.width * (modelData.time / Math.max(root.liveTodayTotal(), 1)))
                      height: parent.height
                      radius: 4
                      color: root.accentColor
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.launchApp(modelData.app)
                }
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          radius: root.cardRadius
          color: Theme.surfaceContainer
          border.color: root.panelBorder
          border.width: 1
          implicitHeight: weekCol.implicitHeight + 24

          Column {
            id: weekCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 10

            StyledText {
              text: "This week"
              color: Theme.surfaceText
              font.pixelSize: 12
              font.bold: true
            }

            Row {
              width: parent.width
              spacing: 0

              Repeater {
                model: root.weekItems
                delegate: Column {
                  width: weekCol.width / Math.max(root.weekItems.length, 1)
                  spacing: 4

                  Item {
                    width: parent.width
                    height: 70

                    Rectangle {
                      width: 18
                      height: Math.max(6, (modelData.total / Math.max(modelData.max, 1)) * 58)
                      radius: 6
                      color: modelData.key === root.selectedDayKey
                        ? Theme.primary
                        : modelData.key === root.todayKey
                        ? (root.progress() >= 1 ? root.dangerColor : root.accentColor)
                        : Qt.rgba(199 / 255, 154 / 255, 230 / 255, modelData.total > 0 ? 0.65 : 0.15)
                      anchors.bottom: parent.bottom
                      anchors.horizontalCenter: parent.horizontalCenter
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.selectDay(modelData.key)
                    }
                  }

                  StyledText {
                    text: modelData.key === root.selectedDayKey ? "▼" : modelData.label.substring(0, 2)
                    color: modelData.key === root.selectedDayKey ? Theme.primary : Theme.surfaceVariantText
                    font.pixelSize: 10
                    anchors.horizontalCenter: parent.horizontalCenter
                  }

                  StyledText {
                    text: modelData.total > 0 ? Math.floor(modelData.total / 3600) + "h" : "0h"
                    color: modelData.key === root.selectedDayKey ? Theme.primary : Theme.surfaceVariantText
                    font.pixelSize: 9
                    anchors.horizontalCenter: parent.horizontalCenter
                  }
                }
              }
            }

            // ── selected day detail ──
            StyledText {
              visible: root.selectedDayApps.length > 0
              text: root.selectedDayKey === root.todayKey
                ? "Today"
                : root.getWeekdayLabel(root.selectedDayKey) + " " + root.selectedDayKey
              color: Theme.surfaceText
              font.pixelSize: 11
              font.bold: true
            }

            Repeater {
              visible: root.selectedDayApps.length > 0
              model: root.selectedDayApps

                delegate: Rectangle {
                  width: parent.width
                  height: 32
                  radius: 8
                  color: root.mutedFill
                  opacity: 0
                  transform: Translate {
                    id: detailSlide
                    y: -15
                    Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                  }

                  Timer {
                    interval: index * 30
                    running: true
                    onTriggered: {
                      parent.opacity = 1
                      detailSlide.y = 0
                    }
                  }

                  Behavior on opacity { NumberAnimation { duration: 180 } }

                  Row {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 6

                    AppIconRenderer {
                      width: 18
                      height: 18
                      iconValue: {
                        var entry = DesktopEntries.heuristicLookup(Paths.moddedAppId(modelData.app))
                        return entry?.icon || modelData.app
                      }
                      iconSize: 18
                      fallbackText: root.getDisplayAppName(modelData.app).charAt(0)
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                      text: root.getDisplayAppName(modelData.app)
                      color: Theme.surfaceText
                      font.pixelSize: 11
                      width: parent.width - 80
                      elide: Text.ElideRight
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                      text: root.fmtShort(modelData.time)
                      color: Theme.surfaceVariantText
                      font.pixelSize: 10
                      width: 40
                  horizontalAlignment: Text.AlignRight
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.launchApp(modelData.app)
              }
            }
          }
        }
      }
    }

            Column {
              id: studyContent
              width: col.width
              spacing: 12
              padding: Theme.spacingMD

              Rectangle {
                width: parent.width
                radius: root.cardRadius
                color: Theme.surfaceContainer
                border.color: root.panelBorder
                border.width: 1
                implicitHeight: studySummary.implicitHeight + 24

                Column {
                  id: studySummary
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: 12
                  spacing: 10

                  StyledText {
                    text: "Today's Focus"
                    color: Theme.surfaceVariantText
                    font.pixelSize: 11
                  }

                  StyledText {
                    text: root.fmtLong(root.focusTimeToday)
                    color: root.accentColor
                    font.pixelSize: 24
                    font.bold: true
                  }

                  StyledText {
                    text: root.pomodoroState !== "idle" || root.studyTimerState !== "idle"
                      ? "Studying now"
                      : "Start a session below"
                    color: Theme.surfaceVariantText
                    font.pixelSize: 10
                  }
                }
              }

              Rectangle {
                width: parent.width
                height: 30
                radius: 15
                color: Qt.rgba(1, 1, 1, 0.045)

                Item {
                  anchors.fill: parent

                  Rectangle {
                    width: parent.width / 2
                    height: parent.height
                    radius: 15
                    color: root.studySubMode === "pomodoro" ? root.accentColor : "transparent"
                    Behavior on color { ColorAnimation { duration: 200 } }

                    StyledText {
                      anchors.centerIn: parent
                      text: "Pomodoro"
                      color: root.studySubMode === "pomodoro" ? "#fff" : Theme.surfaceVariantText
                      font.pixelSize: 11
                      font.bold: root.studySubMode === "pomodoro"
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.studySubMode = "pomodoro"
                    }
                  }

                  Rectangle {
                    anchors.left: parent.horizontalCenter
                    width: parent.width / 2
                    height: parent.height
                    radius: 15
                    color: root.studySubMode === "timer" ? root.accentColor : "transparent"
                    Behavior on color { ColorAnimation { duration: 200 } }

                    StyledText {
                      anchors.centerIn: parent
                      text: "Timer"
                      color: root.studySubMode === "timer" ? "#fff" : Theme.surfaceVariantText
                      font.pixelSize: 11
                      font.bold: root.studySubMode === "timer"
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.studySubMode = "timer"
                    }
                  }
                }
              }

              // ── Pomodoro sub-mode ──
              Rectangle {
                visible: root.studySubMode === "pomodoro"
                width: parent.width
                radius: root.cardRadius
                color: Theme.surfaceContainer
                border.color: root.panelBorder
                border.width: 1
                implicitHeight: 200

                Column {
                  anchors.centerIn: parent
                  spacing: 12

                  StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.pomodoroLabel()
                    color: root.pomodoroState === "focus"
                      ? root.accentColor
                      : root.pomodoroState === "longBreak"
                      ? root.dangerColor
                      : Theme.surfaceText
                    font.pixelSize: 16
                    font.bold: true
                  }

                  StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.pomodoroState !== "idle"
                      ? root.formatCountdown(root.pomodoroRemaining)
                      : root.formatCountdown(root.getFocusDuration())
                    color: Theme.surfaceText
                    font.pixelSize: 48
                    font.bold: true
                    font.letterSpacing: 2
                  }

                  Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    Repeater {
                      model: 4
                      delegate: Rectangle {
                        width: 10; height: 10; radius: 5
                        color: index < root.pomodoroCycle
                          ? root.accentColor
                          : Qt.rgba(1, 1, 1, 0.12)
                      }
                    }
                  }

                  Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12

                    Rectangle {
                      width: 90; height: 36; radius: 18
                      color: root.pomodoroRunning
                        ? Qt.rgba(1, 1, 1, 0.10)
                        : root.accentColor
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (root.pomodoroRunning) root.pausePomodoro()
                          else root.startPomodoro()
                        }
                      }
                      StyledText {
                        anchors.centerIn: parent
                        text: root.pomodoroRunning ? "Pause" : "Start"
                        color: root.pomodoroRunning ? Theme.surfaceText : "#fff"
                        font.pixelSize: 12
                        font.bold: true
                      }
                    }

                    Rectangle {
                      width: 80; height: 36; radius: 18
                      color: Qt.rgba(1, 1, 1, 0.045)
                      visible: root.pomodoroState !== "idle"
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.resetPomodoro()
                      }
                      StyledText {
                        anchors.centerIn: parent
                        text: "Reset"
                        color: Theme.surfaceText
                        font.pixelSize: 12
                      }
                    }
                  }
                }
              }

              // ── Timer sub-mode ──
              Rectangle {
                visible: root.studySubMode === "timer"
                width: parent.width
                radius: root.cardRadius
                color: Theme.surfaceContainer
                border.color: root.panelBorder
                border.width: 1
                implicitHeight: 260

                Column {
                  anchors.centerIn: parent
                  spacing: 12

                  StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.studyTimerState === "idle"
                      ? "Study Timer"
                      : root.studyTimerState === "running"
                      ? "Running"
                      : "Paused"
                    color: root.studyTimerState === "running"
                      ? root.accentColor
                      : Theme.surfaceVariantText
                    font.pixelSize: 14
                    font.bold: true
                  }

                  StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.studyTimerRemaining > 0
                      ? root.formatCountdown(root.studyTimerRemaining)
                      : root.studyTimerDuration > 0
                      ? root.formatCountdown(root.studyTimerDuration)
                      : "00:00"
                    color: Theme.surfaceText
                    font.pixelSize: 48
                    font.bold: true
                    font.letterSpacing: 2
                  }

                  Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    DankTextField {
                      width: 180
                      height: 32
                      text: root.studyTimerInput
                      placeholderText: "e.g. 30m, 1h 30m, 45m"
                      font.pixelSize: 12
                      backgroundColor: root.mutedFill
                      normalBorderColor: "transparent"
                      cornerRadius: 8
                      onTextEdited: root.studyTimerInput = text
                      onEditingFinished: root.applyStudyTimerInput()
                    }
                  }

                  Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12

                    Rectangle {
                      width: 90; height: 36; radius: 18
                      color: root.studyTimerRunning
                        ? Qt.rgba(1, 1, 1, 0.10)
                        : root.accentColor
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (root.studyTimerRunning) root.pauseStudyTimer()
                          else root.startStudyTimer()
                        }
                      }
                      StyledText {
                        anchors.centerIn: parent
                        text: root.studyTimerRunning ? "Pause" : "Start"
                        color: root.studyTimerRunning ? Theme.surfaceText : "#fff"
                        font.pixelSize: 12
                        font.bold: true
                      }
                    }

                    Rectangle {
                      width: 80; height: 36; radius: 18
                      color: Qt.rgba(1, 1, 1, 0.045)
                      visible: root.studyTimerState !== "idle"
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.resetStudyTimer()
                      }
                      StyledText {
                        anchors.centerIn: parent
                        text: "Reset"
                        color: Theme.surfaceText
                        font.pixelSize: 12
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
