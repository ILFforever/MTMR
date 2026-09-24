//
//  Conditions.swift
//  Stripe
//
//  Conditional visibility for any item via a "when" object. All given checks
//  must pass for the item to show:
//
//    "when": {
//      "app": "Safari|Chrome",     // regex on the frontmost app's bundle ID or name
//      "notApp": "Finder",         // regex; hide while a matching app is frontmost
//      "time": "09:00-18:00",      // local time window; may wrap past midnight
//      "script": "pgrep -q docker",// shown while this shell command exits 0
//      "every": 10                 // seconds between script checks (default 10)
//    }
//
//  The legacy "matchAppId" key still works and behaves like "app".
//

import Cocoa

struct ItemCondition: Decodable {
    var app: String?
    var notApp: String?
    var time: String?
    var script: String?
    var every: TimeInterval?

    func isSatisfied(frontmost: NSRunningApplication?) -> Bool {
        if let app = app, !ItemCondition.matches(app, frontmost) { return false }
        if let notApp = notApp, ItemCondition.matches(notApp, frontmost) { return false }
        if let time = time, !ItemCondition.isNow(within: time) { return false }
        if let script = script, !ConditionMonitor.shared.result(for: script, every: every ?? 10) { return false }
        return true
    }

    private static func matches(_ pattern: String, _ app: NSRunningApplication?) -> Bool {
        guard let app = app,
              let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return [app.bundleIdentifier, app.localizedName].compactMap { $0 }.contains { candidate in
            regex.firstMatch(in: candidate, range: NSRange(candidate.startIndex..., in: candidate)) != nil
        }
    }

    /// "HH:mm-HH:mm"; a window whose end is before its start wraps past midnight.
    static func isNow(within window: String, now: Date = Date()) -> Bool {
        let parts = window.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let start = minutes(parts[0]), let end = minutes(parts[1]) else { return true }
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        let current = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return start <= end ? (current >= start && current < end) : (current >= start || current < end)
    }

    private static func minutes(_ hhmm: String) -> Int? {
        let hm = hhmm.split(separator: ":").compactMap { Int($0) }
        guard hm.count == 2, (0..<24).contains(hm[0]), (0..<60).contains(hm[1]) else { return nil }
        return hm[0] * 60 + hm[1]
    }
}

/// Runs "script" conditions in the background on their own intervals, caches
/// the results, and asks the bar to refresh when any result (or the minute,
/// for "time" conditions) changes.
final class ConditionMonitor {
    static let shared = ConditionMonitor()

    private struct ScriptState {
        var every: TimeInterval
        var result = false
        var lastRun: Date = .distantPast
        var running = false
    }

    private var scripts: [String: ScriptState] = [:]
    private var timer: Timer?
    private var lastMinute = -1
    private let queue = DispatchQueue(label: "com.ilfforever.stripe.conditions", attributes: .concurrent)

    /// Called by the bar whenever conditions may have changed.
    var onChange: (() -> Void)?

    /// The cached result for a script condition; registers it on first use.
    /// Until its first run completes, a script condition counts as false.
    func result(for script: String, every: TimeInterval) -> Bool {
        if scripts[script] == nil {
            scripts[script] = ScriptState(every: max(every, 1))
            startTimerIfNeeded()
            run(script)
        }
        return scripts[script]?.result ?? false
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    func start() {
        startTimerIfNeeded()
    }

    private func tick() {
        let now = Date()
        for (script, state) in scripts where !state.running && now.timeIntervalSince(state.lastRun) >= state.every {
            run(script)
        }
        let minute = Calendar.current.component(.minute, from: now)
        if minute != lastMinute {
            let first = lastMinute == -1
            lastMinute = minute
            if !first { onChange?() } // re-evaluate "time" windows each minute
        }
    }

    private func run(_ script: String) {
        scripts[script]?.running = true
        scripts[script]?.lastRun = Date()
        queue.async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", script]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            var ok = false
            do {
                try task.run()
                task.waitUntilExit()
                ok = task.terminationStatus == 0
            } catch {
                NSLog("Stripe: condition script failed to start: \(script) (\(error))")
            }
            DispatchQueue.main.async {
                let changed = self.scripts[script]?.result != ok
                self.scripts[script]?.result = ok
                self.scripts[script]?.running = false
                if changed { self.onChange?() }
            }
        }
    }

    /// Forget scripts from a previous preset.
    func reset() {
        scripts = [:]
    }
}
