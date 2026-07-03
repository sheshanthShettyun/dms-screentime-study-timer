import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSetting {
  id: root

  property int cardRadius: 14
  property int innerRadius: 10
  property color chipBg: Qt.rgba(1, 1, 1, 0.045)
  property color chipBorder: Qt.rgba(1, 1, 1, 0.07)
  property int goalSeconds: configuredGoalSeconds()

  function configuredGoalSeconds(): int {
    var raw = pluginData.dailyGoal
    if (raw === undefined || raw === null || raw === "") return 0
    var value = Number(raw)
    if (!isFinite(value) || value < 0) return 0
    return Math.floor(value)
  }

  function currentHours(): string {
    return String(Math.floor(goalSeconds / 3600))
  }

  function currentMinutes(): string {
    return String(Math.floor((goalSeconds % 3600) / 60))
  }

  function saveGoalFromInputs(): void {
    var hours = Number(hoursField.text)
    var minutes = Number(minutesField.text)
    if (!isFinite(hours) || hours < 0) hours = 0
    if (!isFinite(minutes) || minutes < 0) minutes = 0
    minutes = Math.floor(minutes % 60)
    hours = Math.floor(hours)
    var total = (hours * 3600) + (minutes * 60)
    goalSeconds = total
    pluginData.dailyGoal = total
  }

  Column {
    width: parent.width
    spacing: 12
    padding: 16

    Rectangle {
      width: parent.width - 32
      anchors.horizontalCenter: parent.horizontalCenter
      height: headerCol.implicitHeight + 28
      radius: cardRadius
      color: Theme.surfaceContainer
      border.color: chipBorder
      border.width: 1

      Column {
        id: headerCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14
        spacing: 6

        StyledText {
          text: "Screen Time Tracker"
          color: Theme.surfaceText
          font.pixelSize: 15
          font.bold: true
        }

        StyledText {
          text: "Set a daily goal and exclude apps you don't want tracked."
          color: Theme.surfaceVariantText
          font.pixelSize: 11
          wrapMode: Text.WordWrap
          width: parent.width
        }
      }
    }

    Rectangle {
      width: parent.width - 32
      anchors.horizontalCenter: parent.horizontalCenter
      height: goalCol.implicitHeight + 28
      radius: cardRadius
      color: Theme.surfaceContainer
      border.color: chipBorder
      border.width: 1

      Column {
        id: goalCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14
        spacing: 12

        StyledText {
          text: "Daily goal"
          color: Theme.surfaceText
          font.pixelSize: 12
          font.bold: true
        }

        Row {
          width: parent.width
          spacing: 12

          Rectangle {
            width: 100
            height: 74
            radius: innerRadius
            color: chipBg

            Column {
              anchors.fill: parent
              anchors.margins: 10
              spacing: 2

              StyledText {
                text: "Selected"
                color: Theme.surfaceVariantText
                font.pixelSize: 9
              }

              StyledText {
                text: Math.floor(goalSeconds / 3600) + "h"
                color: Theme.surfaceText
                font.pixelSize: 22
                font.bold: true
                font.letterSpacing: -0.5
              }

              StyledText {
                text: Math.floor((goalSeconds % 3600) / 60) + " min"
                color: Theme.surfaceVariantText
                font.pixelSize: 10
              }
            }
          }

          Column {
            width: parent.width - 112
            spacing: 8

            StyledText {
              text: "Set any goal you want. Leave both fields at 0 if you don't want a daily target."
              color: Theme.surfaceVariantText
              font.pixelSize: 10
              wrapMode: Text.WordWrap
              width: parent.width
            }

            Row {
              width: parent.width
              spacing: 8

              Column {
                width: (parent.width - 8) / 2
                spacing: 4

                StyledText {
                  text: "Hours"
                  color: Theme.surfaceVariantText
                  font.pixelSize: 9
                }

                TextField {
                  id: hoursField
                  width: parent.width
                  height: 36
                  text: root.currentHours()
                  color: Theme.surfaceText
                  inputMethodHints: Qt.ImhDigitsOnly
                  background: Rectangle {
                    radius: innerRadius
                    color: chipBg
                    border.color: chipBorder
                    border.width: 1
                  }
                  onEditingFinished: root.saveGoalFromInputs()
                  onTextChanged: if (activeFocus) root.saveGoalFromInputs()
                }
              }

              Column {
                width: (parent.width - 8) / 2
                spacing: 4

                StyledText {
                  text: "Minutes"
                  color: Theme.surfaceVariantText
                  font.pixelSize: 9
                }

                TextField {
                  id: minutesField
                  width: parent.width
                  height: 36
                  text: root.currentMinutes()
                  color: Theme.surfaceText
                  inputMethodHints: Qt.ImhDigitsOnly
                  background: Rectangle {
                    radius: innerRadius
                    color: chipBg
                    border.color: chipBorder
                    border.width: 1
                  }
                  onEditingFinished: root.saveGoalFromInputs()
                  onTextChanged: if (activeFocus) root.saveGoalFromInputs()
                }
              }
            }
          }
        }
      }
    }

    Rectangle {
      width: parent.width - 32
      anchors.horizontalCenter: parent.horizontalCenter
      height: ignoredCol.implicitHeight + 28
      radius: cardRadius
      color: Theme.surfaceContainer
      border.color: chipBorder
      border.width: 1

      Column {
        id: ignoredCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14
        spacing: 10

        StyledText {
          text: "Ignored apps"
          color: Theme.surfaceText
          font.pixelSize: 12
          font.bold: true
        }

        StyledText {
          text: "Comma-separated application identifiers to exclude from tracking."
          color: Theme.surfaceVariantText
          font.pixelSize: 10
          wrapMode: Text.WordWrap
          width: parent.width
        }

        TextField {
          width: parent.width
          height: 38
          placeholderText: "e.g. firefox, ghostty, discord"
          text: pluginData.ignoredApps || ""
          color: Theme.surfaceText
          placeholderTextColor: Theme.surfaceVariantText
          font.pixelSize: 12
          background: Rectangle {
            radius: innerRadius
            color: chipBg
            border.color: chipBorder
            border.width: 1
          }
          onTextChanged: pluginData.ignoredApps = text
        }

        Rectangle {
          width: parent.width
          radius: innerRadius
          color: chipBg
          height: tipText.implicitHeight + 16

          StyledText {
            id: tipText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            text: "Tip: exclude browsers or chat clients to track only focused work time."
            color: Theme.surfaceVariantText
            font.pixelSize: 9
            wrapMode: Text.WordWrap
          }
        }
      }
    }

    Rectangle {
      width: parent.width - 32
      anchors.horizontalCenter: parent.horizontalCenter
      height: pomoCol.implicitHeight + 28
      radius: cardRadius
      color: Theme.surfaceContainer
      border.color: chipBorder
      border.width: 1

      Column {
        id: pomoCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14
        spacing: 12

        StyledText {
          text: "Pomodoro / Study Mode"
          color: Theme.surfaceText
          font.pixelSize: 12
          font.bold: true
        }

        StyledText {
          text: "Configure Pomodoro timer durations."
          color: Theme.surfaceVariantText
          font.pixelSize: 10
          wrapMode: Text.WordWrap
          width: parent.width
        }

        // Focus duration
        Column {
          width: parent.width
          spacing: 4

          StyledText {
            text: "Focus session"
            color: Theme.surfaceVariantText
            font.pixelSize: 9
          }

          Row {
            width: parent.width
            spacing: 8

            TextField {
              id: focusField
              width: (parent.width - 8) / 2
              height: 36
              text: String(Math.floor((Number(pluginData.focusDuration) || 1500) / 60))
              color: Theme.surfaceText
              inputMethodHints: Qt.ImhDigitsOnly
              background: Rectangle {
                radius: innerRadius
                color: chipBg
                border.color: chipBorder
                border.width: 1
              }
              onEditingFinished: savePomodoro()
            }

            StyledText {
              text: "minutes"
              color: Theme.surfaceVariantText
              font.pixelSize: 10
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        // Short break duration
        Column {
          width: parent.width
          spacing: 4

          StyledText {
            text: "Short break"
            color: Theme.surfaceVariantText
            font.pixelSize: 9
          }

          Row {
            width: parent.width
            spacing: 8

            TextField {
              id: shortBreakField
              width: (parent.width - 8) / 2
              height: 36
              text: String(Math.floor((Number(pluginData.shortBreakDuration) || 300) / 60))
              color: Theme.surfaceText
              inputMethodHints: Qt.ImhDigitsOnly
              background: Rectangle {
                radius: innerRadius
                color: chipBg
                border.color: chipBorder
                border.width: 1
              }
              onEditingFinished: savePomodoro()
            }

            StyledText {
              text: "minutes"
              color: Theme.surfaceVariantText
              font.pixelSize: 10
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        // Long break duration
        Column {
          width: parent.width
          spacing: 4

          StyledText {
            text: "Long break"
            color: Theme.surfaceVariantText
            font.pixelSize: 9
          }

          Row {
            width: parent.width
            spacing: 8

            TextField {
              id: longBreakField
              width: (parent.width - 8) / 2
              height: 36
              text: String(Math.floor((Number(pluginData.longBreakDuration) || 900) / 60))
              color: Theme.surfaceText
              inputMethodHints: Qt.ImhDigitsOnly
              background: Rectangle {
                radius: innerRadius
                color: chipBg
                border.color: chipBorder
                border.width: 1
              }
              onEditingFinished: savePomodoro()
            }

            StyledText {
              text: "minutes"
              color: Theme.surfaceVariantText
              font.pixelSize: 10
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        Rectangle {
          width: parent.width
          radius: innerRadius
          color: chipBg
          height: tip2.implicitHeight + 16

          StyledText {
            id: tip2
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            text: "Cycle: focus → short break → focus → short break → focus → short break → focus → long break → repeat."
            color: Theme.surfaceVariantText
            font.pixelSize: 9
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  function savePomodoro(): void {
    var f = Math.floor(Number(focusField.text) || 25) * 60
    var s = Math.floor(Number(shortBreakField.text) || 5) * 60
    var l = Math.floor(Number(longBreakField.text) || 15) * 60
    pluginData.focusDuration = Math.max(f, 60)
    pluginData.shortBreakDuration = Math.max(s, 60)
    pluginData.longBreakDuration = Math.max(l, 60)
  }
}
