//
//  RunInterruptionsTests.swift
//  RunMirrorKitTests
//
//  A call pauses a run that's going and picks it up after — only when iOS
//  says to, and only a pause the call made.
//

import XCTest
@testable import RunMirrorKit

final class RunInterruptionsTests: XCTestCase {
    func testACallPausesARunningRunAndResumesItAfter() {
        var i = RunInterruptions()
        i.runChanged(paused: false)
        XCTAssertEqual(i.began(), .pause)
        i.runChanged(paused: true)
        XCTAssertEqual(i.ended(shouldResume: true), .resume)
        XCTAssertFalse(i.pausedByInterruption)
    }

    func testARunYouPausedStaysPaused() {
        var i = RunInterruptions()
        i.runChanged(paused: true)
        XCTAssertNil(i.began())
        XCTAssertNil(i.ended(shouldResume: true))
    }

    func testNoResumeWhenIOSSaysNot() {
        var i = RunInterruptions()
        XCTAssertEqual(i.began(), .pause)
        i.runChanged(paused: true)
        XCTAssertNil(i.ended(shouldResume: false))
        // Still ours: a later end that may resume does.
        XCTAssertEqual(i.ended(shouldResume: true), .resume)
    }

    func testResumingByHandDuringACallMakesThePauseNotOursToUndo() {
        var i = RunInterruptions()
        XCTAssertEqual(i.began(), .pause)
        i.runChanged(paused: true)
        i.runChanged(paused: false)
        i.runChanged(paused: true)
        XCTAssertNil(i.ended(shouldResume: true))
    }

    func testAnEndWithNoCallDoesNothing() {
        var i = RunInterruptions()
        XCTAssertNil(i.ended(shouldResume: true))
    }

    func testResetForgetsTheCall() {
        var i = RunInterruptions()
        XCTAssertEqual(i.began(), .pause)
        i.reset()
        XCTAssertNil(i.ended(shouldResume: true))
    }
}
