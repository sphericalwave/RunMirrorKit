//
//  WatchCommandTests.swift
//  RunMirrorPhoneTests
//
//  The watch app's buttons reach the run with the AirPods & lock-screen
//  controls off: they come over WatchConnectivity, not the audio session.
//

#if os(iOS)
import AVFoundation
import RunMirrorKit
import WatchConnectivity
import XCTest
@testable import RunMirrorPhone

final class WatchCommandTests: XCTestCase {
    private var savedSetting: Any?

    override func setUp() {
        super.setUp()
        savedSetting = UserDefaults.standard.object(forKey: RunRemote.enabledKey)
        UserDefaults.standard.set(false, forKey: RunRemote.enabledKey)
    }

    override func tearDown() {
        RunRemote.shared.deactivate()
        WatchRunLink.shared.onCommand = nil
        UserDefaults.standard.set(savedSetting, forKey: RunRemote.enabledKey)
        super.tearDown()
    }

    /// A run with the controls off: the remote is up but takes no commands,
    /// and the session mixes.
    private func startRun(onCommand: @escaping (WatchRunCommand) -> Void) {
        RunAudioSession.activate()
        RunRemote.shared.activate(play: {}, pause: {}, next: {}, previous: {})
        WatchRunLink.shared.onCommand = onCommand
    }

    func testEveryButtonReachesTheRunWithTheControlsOff() async {
        XCTAssertFalse(RunRemote.isEnabled)
        var received: [WatchRunCommand] = []
        startRun { received.append($0) }
        XCTAssertTrue(AVAudioSession.sharedInstance().categoryOptions.contains(.mixWithOthers))

        let all: [WatchRunCommand] = [.back, .toggle, .forward, .end]
        for command in all {
            WatchRunLink.shared.session(WCSession.default, didReceiveMessage: WatchRunMessage.encode(command))
        }
        await settle()
        XCTAssertEqual(received, all)
    }

    /// The watch's sendMessage waits on a reply, which comes straight away.
    func testAButtonSentForAReplyIsAnsweredAndReachesTheRun() async {
        var received: [WatchRunCommand] = []
        startRun { received.append($0) }
        let replied = expectation(description: "replied")

        WatchRunLink.shared.session(WCSession.default, didReceiveMessage: WatchRunMessage.encode(.forward),
                                    replyHandler: { _ in replied.fulfill() })
        await fulfillment(of: [replied], timeout: 1)
        await settle()
        XCTAssertEqual(received, [.forward])
    }

    /// Commands are handed over on the main actor, after the delegate returns.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(50))
    }
}
#endif
