//
//  WatchRunMessage.swift
//  RunMirrorKit
//
//  What the phone and the watch say to each other about a run. The phone
//  runs it and is the only source of truth; the watch mirrors it.
//
//  The phone sends a `WatchRunState` each time the run changes — a hold or
//  rest begins, a pause, a resume — never once a second: `endsAt` lets the
//  watch count down on its own. The watch sends back a `WatchRunCommand`,
//  the same ⏮ ⏯ ⏭ and End as the phone's own controls, its heart rate, and
//  why it didn't keep a run's workout in Health when it didn't.
//
//  Used by both the phone app and the watch app.
//

import Foundation

public nonisolated struct WatchRunState: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case running
        /// Ended for review on the phone — the workout's done.
        case finished
        /// Left with Later, to pick up another time.
        case left
    }

    /// One side of the exercise on — "R" done, "L" being held — so a glance
    /// says which sides are through this round.
    public struct Side: Codable, Equatable, Sendable {
        public enum Status: String, Codable, Sendable {
            case done, current, upcoming
        }

        /// "Right", for VoiceOver.
        public var name: String
        /// "R", for the badge.
        public var label: String
        public var status: Status

        public init(name: String, label: String, status: Status) {
            self.name = name
            self.label = label
            self.status = status
        }
    }

    /// One run: the workout and when it started. A new one is a new watch
    /// workout; the same one picked up later carries on under it.
    public var runID: String
    public var status: Status
    public var planName: String
    public var exercise: String
    /// "Right", "Left", a digit — empty for a hold with no sides.
    public var side: String
    public var isResting: Bool
    /// "Between sides" and the like; empty for a digit's rest.
    public var restLabel: String
    /// The sides of the exercise on — or, in a rest, the one coming up — this
    /// round, in the order they're held. Empty when there's no pair of sides
    /// to keep track of.
    public var sides: [Side]
    /// "Squat · Left" — the hold after this one, or the one a rest leads into.
    public var next: String?
    public var nextIsNewRound: Bool
    /// Counted from one.
    public var round: Int
    public var rounds: Int
    public var durationSec: Int
    /// When the hold or rest runs out. nil while paused.
    public var endsAt: Date?
    /// What was left when it paused. nil while running.
    public var pausedRemainingSec: Int?
    public var isPaused: Bool { endsAt == nil }
    /// Goes up each time a hold or rest begins — the same one again too — so
    /// a ⏮ restart is a change even though nothing else is.
    public var segment: Int
    /// The phone's "Save watch workout to Health" setting.
    public var saveToHealth: Bool
    /// Stamped as it's sent, so the watch can drop one that arrives after a
    /// newer one — a message and the application context can cross.
    public var sentAt: Date = .distantPast

    public init(runID: String, status: Status, planName: String, exercise: String, side: String,
                isResting: Bool, restLabel: String, sides: [Side] = [], next: String?, nextIsNewRound: Bool,
                round: Int, rounds: Int, durationSec: Int, endsAt: Date?, pausedRemainingSec: Int?,
                segment: Int, saveToHealth: Bool, sentAt: Date = .distantPast) {
        self.runID = runID
        self.status = status
        self.planName = planName
        self.exercise = exercise
        self.side = side
        self.isResting = isResting
        self.restLabel = restLabel
        self.sides = sides
        self.next = next
        self.nextIsNewRound = nextIsNewRound
        self.round = round
        self.rounds = rounds
        self.durationSec = durationSec
        self.endsAt = endsAt
        self.pausedRemainingSec = pausedRemainingSec
        self.segment = segment
        self.saveToHealth = saveToHealth
        self.sentAt = sentAt
    }

    /// A state from a phone that predates `sides` decodes with none.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runID = try c.decode(String.self, forKey: .runID)
        status = try c.decode(Status.self, forKey: .status)
        planName = try c.decode(String.self, forKey: .planName)
        exercise = try c.decode(String.self, forKey: .exercise)
        side = try c.decode(String.self, forKey: .side)
        isResting = try c.decode(Bool.self, forKey: .isResting)
        restLabel = try c.decode(String.self, forKey: .restLabel)
        sides = try c.decodeIfPresent([Side].self, forKey: .sides) ?? []
        next = try c.decodeIfPresent(String.self, forKey: .next)
        nextIsNewRound = try c.decode(Bool.self, forKey: .nextIsNewRound)
        round = try c.decode(Int.self, forKey: .round)
        rounds = try c.decode(Int.self, forKey: .rounds)
        durationSec = try c.decode(Int.self, forKey: .durationSec)
        endsAt = try c.decodeIfPresent(Date.self, forKey: .endsAt)
        pausedRemainingSec = try c.decodeIfPresent(Int.self, forKey: .pausedRemainingSec)
        segment = try c.decode(Int.self, forKey: .segment)
        saveToHealth = try c.decode(Bool.self, forKey: .saveToHealth)
        sentAt = try c.decode(Date.self, forKey: .sentAt)
    }

    /// Whole seconds left at `date`, as the phone's clock would show them.
    public func remainingSec(at date: Date) -> Int {
        guard let endsAt else { return pausedRemainingSec ?? 0 }
        return max(0, Int(endsAt.timeIntervalSince(date).rounded(.up)))
    }
}

public nonisolated enum WatchRunCommand: String, Codable, Sendable {
    case back, toggle, forward, end
}

/// The dictionaries WatchConnectivity carries.
public nonisolated enum WatchRunMessage {
    public static let stateKey = "runState"
    public static let commandKey = "runCommand"
    public static let heartRateKey = "bpm"
    public static let workoutNoteKey = "workoutNote"
    public static let noteRunIDKey = "noteRunID"

    public static func encode(_ state: WatchRunState) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(state) else { return [:] }
        return [stateKey: data]
    }

    public static func state(in message: [String: Any]) -> WatchRunState? {
        guard let data = message[stateKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchRunState.self, from: data)
    }

    public static func encode(_ command: WatchRunCommand) -> [String: Any] {
        [commandKey: command.rawValue]
    }

    public static func command(in message: [String: Any]) -> WatchRunCommand? {
        (message[commandKey] as? String).flatMap(WatchRunCommand.init(rawValue:))
    }

    public static func encode(heartRate bpm: Int) -> [String: Any] {
        [heartRateKey: bpm]
    }

    public static func heartRate(in message: [String: Any]) -> Int? {
        message[heartRateKey] as? Int
    }

    public static func encode(_ note: WatchWorkoutNote) -> [String: Any] {
        [workoutNoteKey: note.text, noteRunIDKey: note.runID]
    }

    public static func workoutNote(in message: [String: Any]) -> WatchWorkoutNote? {
        guard let text = message[workoutNoteKey] as? String,
              let runID = message[noteRunIDKey] as? String else { return nil }
        return WatchWorkoutNote(runID: runID, text: text)
    }

    /// Whether a message or context is any of the above. Anything else is
    /// another feature's, for whoever else is listening on the session.
    public static func isRunMessage(_ message: [String: Any]) -> Bool {
        message[stateKey] != nil || message[commandKey] != nil || message[heartRateKey] != nil
            || message[workoutNoteKey] != nil
    }
}

/// Why the watch didn't keep a run's workout in Health, for the run's review.
public nonisolated struct WatchWorkoutNote: Equatable, Sendable {
    public let runID: String
    public let text: String

    public init(runID: String, text: String) {
        self.runID = runID
        self.text = text
    }
}

/// The phone's say on whether the watch keeps its workout in Health.
public nonisolated enum WatchWorkoutSettings {
    public static let saveToHealthKey = "watchSaveWorkoutToHealth"

    /// On unless turned off.
    public static var saveToHealth: Bool {
        UserDefaults.standard.object(forKey: saveToHealthKey) as? Bool ?? true
    }
}
