//
//  WatchRunMessageTests.swift
//  RunMirrorKitTests
//
//  What crosses between phone and watch survives the trip, the watch counts
//  down from the state alone, and the save rule tells an app's own workouts
//  from everyone else's.
//

import XCTest
@testable import RunMirrorKit

final class WatchRunMessageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func state(endsAt: Date?, paused: Int? = nil) -> WatchRunState {
        WatchRunState(runID: "r", status: .running, planName: "evening", exercise: "seiza", side: "",
                      isResting: false, restLabel: "", next: "kiza", nextIsNewRound: false,
                      round: 1, rounds: 2, durationSec: 40, endsAt: endsAt, pausedRemainingSec: paused,
                      segment: 3, saveToHealth: true, sentAt: now)
    }

    func testStateRoundTrips() {
        let s = state(endsAt: now.addingTimeInterval(30))
        XCTAssertEqual(WatchRunMessage.state(in: WatchRunMessage.encode(s)), s)
        XCTAssertTrue(WatchRunMessage.isRunMessage(WatchRunMessage.encode(s)))
    }

    /// The watch's "what's the run now?" is the run's, and nothing else.
    func testStateRequestIsARunMessage() {
        let request = WatchRunMessage.encodeStateRequest()
        XCTAssertTrue(WatchRunMessage.isStateRequest(request))
        XCTAssertTrue(WatchRunMessage.isRunMessage(request))
        XCTAssertNil(WatchRunMessage.state(in: request))
        XCTAssertNil(WatchRunMessage.command(in: request))
        XCTAssertFalse(WatchRunMessage.isStateRequest(WatchRunMessage.encode(.toggle)))
    }

    /// Every try of one press carries the same id, and when it was pressed.
    func testCommandCarriesIDAndSentAt() {
        let message = WatchRunMessage.encode(.toggle, id: "abc", sentAt: now)
        XCTAssertEqual(WatchRunMessage.command(in: message), .toggle)
        XCTAssertEqual(WatchRunMessage.commandID(in: message), "abc")
        XCTAssertEqual(WatchRunMessage.commandSentAt(in: message), now)
        XCTAssertNil(WatchRunMessage.commandID(in: WatchRunMessage.encode(.toggle)))
    }

    /// ⏯ pauses on the wrist at once, keeping what was left.
    func testToggleGuessPauses() throws {
        let running = state(endsAt: now.addingTimeInterval(12))
        let guess = try XCTUnwrap(running.applying(.toggle, at: now))
        XCTAssertTrue(guess.isPaused)
        XCTAssertEqual(guess.pausedRemainingSec, 12)
        XCTAssertGreaterThan(guess.sentAt, running.sentAt)
    }

    /// …and resumes from where it was.
    func testToggleGuessResumes() throws {
        let paused = state(endsAt: nil, paused: 12)
        let guess = try XCTUnwrap(paused.applying(.toggle, at: now))
        XCTAssertFalse(guess.isPaused)
        XCTAssertEqual(guess.endsAt, now.addingTimeInterval(12))
        XCTAssertNil(guess.pausedRemainingSec)
    }

    /// Only ⏯ on a run that's going is guessed.
    func testOnlyToggleIsGuessed() {
        let running = state(endsAt: now.addingTimeInterval(12))
        XCTAssertNil(running.applying(.forward, at: now))
        XCTAssertNil(running.applying(.back, at: now))
        var finished = running
        finished.status = .finished
        XCTAssertNil(finished.applying(.toggle, at: now))
    }

    func testSidesRoundTrip() {
        var s = state(endsAt: now.addingTimeInterval(30))
        s.sides = [.init(name: "Right", label: "R", status: .done),
                   .init(name: "Left", label: "L", status: .current)]
        XCTAssertEqual(WatchRunMessage.state(in: WatchRunMessage.encode(s))?.sides, s.sides)
    }

    /// A phone that predates sides still drives a watch that knows them.
    func testAStateWithoutSidesDecodesWithNone() throws {
        let s = state(endsAt: now.addingTimeInterval(30))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        XCTAssertNotNil(json.removeValue(forKey: "sides"))
        let old = try JSONSerialization.data(withJSONObject: json)
        let decoded = try XCTUnwrap(WatchRunMessage.state(in: [WatchRunMessage.stateKey: old]))
        XCTAssertEqual(decoded.sides, [])
        XCTAssertEqual(decoded, s)
    }

    func testCommandsHeartRateAndNotesRoundTrip() {
        XCTAssertEqual(WatchRunMessage.command(in: WatchRunMessage.encode(WatchRunCommand.back)), .back)
        XCTAssertEqual(WatchRunMessage.heartRate(in: WatchRunMessage.encode(heartRate: 64)), 64)
        let note = WatchWorkoutNote(runID: "r", text: "not saved")
        XCTAssertEqual(WatchRunMessage.workoutNote(in: WatchRunMessage.encode(note)), note)
        XCTAssertNil(WatchRunMessage.state(in: WatchRunMessage.encode(heartRate: 64)))
    }

    func testOtherFeaturesMessagesArentTheRuns() {
        XCTAssertFalse(WatchRunMessage.isRunMessage(["sitActive": true]))
        XCTAssertFalse(WatchRunMessage.isRunMessage(["checkIn": "tap", "t": 1.0]))
        XCTAssertFalse(WatchRunMessage.isRunMessage(["streaming": true]))
    }

    func testCountsDownFromEndsAtRoundingUp() {
        let s = state(endsAt: now.addingTimeInterval(30))
        XCTAssertFalse(s.isPaused)
        XCTAssertEqual(s.remainingSec(at: now), 30)
        XCTAssertEqual(s.remainingSec(at: now.addingTimeInterval(12.5)), 18)
        XCTAssertEqual(s.remainingSec(at: now.addingTimeInterval(99)), 0)
    }

    func testPausedHoldsWhatWasLeft() {
        let s = state(endsAt: nil, paused: 12)
        XCTAssertTrue(s.isPaused)
        XCTAssertEqual(s.remainingSec(at: now.addingTimeInterval(500)), 12)
    }

    func testOwnSourceAppIsTheAsker() {
        typealias W = WatchWorkoutSaveRule.OtherWorkout
        XCTAssertEqual(W(start: now, end: now, bundleID: "x", sourceApp: "meditate", ownSourceApp: "meditate").source,
                       .ownApp)
        XCTAssertEqual(W(start: now, end: now, bundleID: "x", sourceApp: "bioMechanic", ownSourceApp: "meditate").source,
                       .other)
        XCTAssertEqual(W(start: now, end: now, bundleID: "com.sphericalwave.jiujitsu.flow", sourceApp: nil,
                         ownSourceApp: "meditate").source, .flow)
    }

    func testOwnWorkoutDoesntBlockSaving() {
        let end = now.addingTimeInterval(600)
        let readings = stride(from: 0.0, to: 600, by: 5).map { now.addingTimeInterval($0) }
        let mine = WatchWorkoutSaveRule.OtherWorkout(start: now, end: end, source: .ownApp)
        XCTAssertEqual(WatchWorkoutSaveRule.decide(enabled: true, start: now, end: end, activeDuration: 600,
                                                   heartRateTimes: readings, others: [mine]), .save)
        let theirs = WatchWorkoutSaveRule.OtherWorkout(start: now, end: end, source: .other)
        XCTAssertEqual(WatchWorkoutSaveRule.decide(enabled: true, start: now, end: end, activeDuration: 600,
                                                   heartRateTimes: readings, others: [theirs]), .recordedElsewhere)
    }
}
