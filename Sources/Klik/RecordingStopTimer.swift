import Foundation

/// Monotonic, recording-session-owned timer. Klik currently has no pause operation:
/// all elapsed time after capture starts counts, including microphone mute.
@MainActor
final class RecordingStopTimer {
    private var timer: Timer?
    private var deadline: TimeInterval?
    private var generation = UUID()
    private var onTimeout: (() -> Void)?
    private let now: () -> TimeInterval

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    var remaining: TimeInterval? { deadline.map { max(0, $0 - now()) } }

    func start(duration: TimeInterval?, onTimeout: @escaping () -> Void) {
        cancel()
        guard let duration, duration.isFinite, duration > 0 else { return }
        deadline = now() + duration
        self.onTimeout = onTimeout
        let token = generation
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.checkDeadline()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func checkDeadline() {
        guard let remaining, remaining <= 0 else { return }
        let callback = onTimeout
        cancel() // Invalidate before callback, including reentrant stop/start.
        callback?()
    }

    func cancel() {
        generation = UUID()
        timer?.invalidate()
        timer = nil
        deadline = nil
        onTimeout = nil
    }

    deinit { timer?.invalidate() }
}

struct RecordingStopSettings {
    static let maximumMinutes = 1440
    var enabled = false
    var seconds = 600

    static func duration(minutes: String, seconds: String) -> Int? {
        func integer(_ text: String) -> Int? {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return Int(value)
        }
        guard let minutes = integer(minutes), let seconds = integer(seconds),
              (0...maximumMinutes).contains(minutes), (0...59).contains(seconds) else { return nil }
        let total = minutes * 60 + seconds
        return (1...maximumMinutes * 60).contains(total) ? total : nil
    }

    var duration: TimeInterval? { enabled ? TimeInterval(seconds) : nil }

    init(defaults: UserDefaults = .standard) {
        let stored = defaults.object(forKey: "recordingStopSeconds") as? Int
        if let stored, (1...Self.maximumMinutes * 60).contains(stored) {
            seconds = stored
            enabled = defaults.bool(forKey: "recordingStopEnabled")
        }
    }

    func save(defaults: UserDefaults = .standard) {
        guard (1...Self.maximumMinutes * 60).contains(seconds) else {
            defaults.set(false, forKey: "recordingStopEnabled")
            return
        }
        defaults.set(seconds, forKey: "recordingStopSeconds")
        defaults.set(enabled, forKey: "recordingStopEnabled")
    }
}
