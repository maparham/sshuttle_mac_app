import Cocoa
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var sshuttleTask: Process?
    var retryCount = 0
    let maxRetries = 5
    let retryDelay: TimeInterval = 5.0 // seconds

    var isStopping = false
    var sshUserHost = "user@host" // default, can be changed via menu

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("sshuttle menu app started")

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            print("Notification permission: \(granted), error: \(String(describing: error))")
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "⚪️ sshuttle"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Start VPN", action: #selector(startVPN), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Stop VPN", action: #selector(stopVPN), keyEquivalent: "x"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Set SSH user@host", action: #selector(promptSetSSHUserHost), keyEquivalent: "u"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func startVPN() {
        DispatchQueue.main.async {
            if self.sshuttleTask != nil {
                print("sshuttle is already running.")
                return
            }

            self.isStopping = false
            self.retryCount = 0
            self.updateStatusIndicator(running: false)

            print("Attempting to start sshuttle...")
            let task = Process()
            task.launchPath = "/usr/bin/env"
            task.arguments = ["/opt/homebrew/bin/sshuttle", "-Hr", self.sshUserHost, "0.0.0.0/0", "--dns", "--no-latency-control"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                if let line = String(data: handle.availableData, encoding: .utf8), !line.isEmpty {
                    DispatchQueue.main.async {
                        print("sshuttle: \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
                    }
                }
            }

            task.terminationHandler = { [weak self] process in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    print("sshuttle exited with status \(process.terminationStatus)")
                    self.sshuttleTask = nil
                    self.updateStatusIndicator(running: false)

                    if self.isStopping {
                        print("sshuttle stopped by user, no retry.")
                        self.isStopping = false
                        return
                    }

                    if self.retryCount < self.maxRetries {
                        self.retryCount += 1
                        print("Retrying sshuttle in \(self.retryDelay) seconds (attempt \(self.retryCount))...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + self.retryDelay) {
                            self.startVPN()
                        }
                    } else {
                        print("Max retries reached. Giving up.")
                        self.showNotification(title: "sshuttle", body: "Failed to start VPN after \(self.maxRetries) attempts.")
                    }
                }
            }

            do {
                try task.run()
                self.sshuttleTask = task
                self.updateStatusIndicator(running: true)
                print("sshuttle started")
                self.showNotification(title: "sshuttle", body: "VPN started successfully")
            } catch {
                print("Failed to start sshuttle: \(error)")
                self.showNotification(title: "sshuttle error", body: "Failed to start VPN: \(error.localizedDescription)")
                self.updateStatusIndicator(running: false)
            }
        }
    }

    @objc func stopVPN() {
        DispatchQueue.main.async {
            self.isStopping = true
            if let task = self.sshuttleTask {
                task.terminate()
                self.sshuttleTask = nil
                self.retryCount = 0
                print("sshuttle stopped")
                self.showNotification(title: "sshuttle", body: "VPN stopped")
                self.updateStatusIndicator(running: false)
            } else {
                print("sshuttle is not running.")
            }
        }
    }

    func updateStatusIndicator(running: Bool) {
        DispatchQueue.main.async {
            if running {
                self.statusItem.button?.title = "🟢 sshuttle"
            } else {
                self.statusItem.button?.title = "⚪️ sshuttle"
            }
        }
    }

    @objc func quitApp() {
        stopVPN()
        NSApp.terminate(nil)
    }

    @objc func promptSetSSHUserHost() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Set SSH user@host"
            alert.informativeText = "Enter SSH user and host (e.g. user@hostname):"
            alert.alertStyle = .informational

            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            input.stringValue = self.sshUserHost
            alert.accessoryView = input

            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let newValue = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !newValue.isEmpty {
                    self.sshUserHost = newValue
                    self.showNotification(title: "sshuttle", body: "SSH user@host set to \(self.sshUserHost)")
                    print("SSH user@host updated to: \(self.sshUserHost)")
                }
            }
        }
    }

    func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }

    // Show notifications while app is active
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
}

@main
struct SshuttleApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // hides dock icon
        app.run()
    }
}
