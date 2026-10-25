//
//  RunInterruptions.swift
//  RunMirrorKit
//
//  What a phone call (or Siri, or another app taking the audio) does to a
//  run: it pauses one that's going, and when it's over picks it up again —
//  if iOS says it should, and only if it was the call that paused it. A run
//  you'd paused yourself stays paused.
//
//  Kept apart from the audio session so it can be tested without one.
//

import Foundation

public nonisolated struct RunInterruptions: Equatable, Sendable {
    public enum Action: Equatable, Sendable { case pause, resume }

    /// As the run last said.
    public private(set) var isPaused = false
    /// Paused by a call rather than by you, so it's ours to resume.
    public private(set) var pausedByInterruption = false

    public init() {}

    /// The run's own state, each time it changes. Resuming by hand during a
    /// call makes the call's pause no longer ours to undo.
    public mutating func runChanged(paused: Bool) {
        isPaused = paused
        if !paused { pausedByInterruption = false }
    }

    /// A call came in.
    public mutating func began() -> Action? {
        guard !isPaused else { return nil }
        pausedByInterruption = true
        return .pause
    }

    /// The call's over. `shouldResume` is iOS's say.
    public mutating func ended(shouldResume: Bool) -> Action? {
        guard pausedByInterruption, shouldResume else { return nil }
        pausedByInterruption = false
        return .resume
    }

    /// The run's gone.
    public mutating func reset() {
        pausedByInterruption = false
    }
}
