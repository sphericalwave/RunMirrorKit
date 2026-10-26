//
//  CueDuckerTests.swift
//  RunMirrorPhoneTests
//
//  With the AirPods & lock-screen controls off the music plays at full
//  volume and dips only while a cue is said; on, the session never changes.
//

#if os(iOS)
import AVFoundation
import XCTest
@testable import RunMirrorPhone

final class CueDuckerTests: XCTestCase {
    private var applied: [AVAudioSession.CategoryOptions] = []
    private var scheduled: [(delay: TimeInterval, work: @MainActor () -> Void)] = []
    private var ducker: CueDucker!

    private let mix: AVAudioSession.CategoryOptions = [.mixWithOthers]
    private let duck: AVAudioSession.CategoryOptions = [.mixWithOthers, .duckOthers]

    override func setUp() {
        super.setUp()
        applied = []
        scheduled = []
        ducker = CueDucker(apply: { [unowned self] in
            XCTAssertEqual($0.category, .playback)
            applied.append($0.options)
        }, schedule: { [unowned self] in scheduled.append(($0, $1)) })
    }

    /// Runs whatever's been scheduled, as the clock would.
    private func elapse() {
        let due = scheduled
        scheduled = []
        due.forEach { $0.work() }
    }

    func testOffTheRunStartsMixingWithoutDucking() {
        ducker.begin(remoteControls: false)
        XCTAssertEqual(applied, [mix])
    }

    func testOffACueDucksThenTheMusicComesBack() {
        ducker.begin(remoteControls: false)
        ducker.cueStarted()
        XCTAssertEqual(applied, [mix, duck])
        ducker.cueEnded()
        XCTAssertEqual(applied, [mix, duck], "Held a moment in case another cue follows")
        XCTAssertEqual(scheduled.map(\.delay), [CueDucker.hold])
        elapse()
        XCTAssertEqual(applied, [mix, duck, mix])
    }

    func testCuesCloseTogetherShareOneDip() {
        ducker.begin(remoteControls: false)
        ducker.cueStarted()
        ducker.cueEnded()
        ducker.cueStarted()
        ducker.cueStarted()
        ducker.cueEnded()
        elapse()
        XCTAssertEqual(applied, [mix, duck, mix])
    }

    func testEachCueApartGetsItsOwnDip() {
        ducker.begin(remoteControls: false)
        for _ in 0..<2 {
            ducker.cueStarted()
            ducker.cueEnded()
            elapse()
        }
        XCTAssertEqual(applied, [mix, duck, mix, duck, mix])
    }

    func testAnEndWithoutAStartChangesNothing() {
        ducker.begin(remoteControls: false)
        ducker.cueEnded()
        XCTAssertTrue(scheduled.isEmpty)
        XCTAssertEqual(applied, [mix])
    }

    func testEndingTheRunCallsOffTheRelease() {
        ducker.begin(remoteControls: false)
        ducker.cueStarted()
        ducker.cueEnded()
        ducker.end()
        elapse()
        XCTAssertEqual(applied, [mix, duck], "The session's released by the caller instead")
    }

    func testOnTheSessionNeverChanges() {
        ducker.begin(remoteControls: true)
        ducker.cueStarted()
        ducker.cueEnded()
        elapse()
        XCTAssertEqual(applied, [[]])
        XCTAssertTrue(scheduled.isEmpty)
    }

    func testANewRunForgetsTheLastOnesDip() {
        ducker.begin(remoteControls: false)
        ducker.cueStarted()
        ducker.cueEnded()
        ducker.begin(remoteControls: false)
        elapse()
        XCTAssertEqual(applied, [mix, duck, mix])
    }
}
#endif
