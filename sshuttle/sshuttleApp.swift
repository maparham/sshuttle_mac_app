import Cocoa
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var sshuttleTask: Process?
    var retryCount = 0
    let maxRetries = 5
    let retryDelay: TimeInterval = 5.0 // seconds

    var isStopping = false
    var retryWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("sshuttle menu app started")

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            print("Notification permission: \(granted), error: \(String(describing: error))")
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            DispatchQueue.main.async {
                button.title = "⚪️ sshuttle"
            }
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Start VPN", action: #selector(startVPN), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Stop VPN", action: #selector(stopVPN), keyEquivalent: "x"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func startVPN() {
        if sshuttleTask != nil {
            print("sshuttle is already running.")
            return
        }

        isStopping = false // reset on start

        print("Attempting to start sshuttle...")
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["/opt/homebrew/bin/sshuttle", "-Hr", "shahrood@3.77.50.122", "0.0.0.0/0", "--dns", "--no-latency-control"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            if let line = String(data: handle.availableData, encoding: .utf8), !line.isEmpty {
                print("sshuttle: \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        task.terminationHandler = { [weak self] process in
            guard let self = self else { return }
            print("sshuttle exited with status \(process.terminationStatus)")
            self.sshuttleTask = nil

            DispatchQueue.main.async {
                self.updateStatusItem(running: false)
            }

            if self.isStopping {
                self.isStopping = false
                print("sshuttle stopped by user, no retry.")
                return
            }

            if self.retryCount < self.maxRetries {
                self.retryCount += 1
                print("Retrying sshuttle in \(self.retryDelay) seconds (attempt \(self.retryCount))...")
                DispatchQueue.main.asyncAfter(deadline: .now() + self.retryDelay) {
                    if !self.isStopping {
                        self.startVPN()
                    } else {
                        print("Retry canceled due to stopVPN")
                    }
                }
            }

        }

        do {
            try task.run()
            sshuttleTask = task
            retryCount = 0
            DispatchQueue.main.async {
                self.updateStatusItem(running: true)
            }
            print("sshuttle started")
            showNotification(title: "sshuttle", body: "VPN started successfully")
        } catch {
            print("Failed to start sshuttle: \(error)")
            showNotification(title: "sshuttle error", body: "Failed to start VPN: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.updateStatusItem(running: false)
            }
        }
    }

    @objc func stopVPN() {
        isStopping = true
        if let task = sshuttleTask {
            retryWorkItem?.cancel()
            task.terminate()
            sshuttleTask = nil
            retryCount = 0
            DispatchQueue.main.async {
                self.updateStatusItem(running: false)
            }
            print("sshuttle stopped")
            showNotification(title: "sshuttle", body: "VPN stopped")
        } else {
            print("sshuttle is not running.")
        }
    }

    func updateStatusItem(running: Bool) {
        if let button = statusItem.button {
            button.title = running ? "🟢 sshuttle" : "⚪️ sshuttle"
        }
    }

    @objc func quitApp() {
        stopVPN()
        NSApp.terminate(nil)
    }

    func showNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    // So notifications show while app is running
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
}

import Cocoa

@main
struct SshuttleApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
