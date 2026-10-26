//
//  RunAudioSessionTests.swift
//  RunMirrorPhoneTests
//
//  Off, a run mixes with music, ducking it only for cues; on, it takes the
//  audio so the AirPods and lock screen drive it. Either way it can run
//  locked.
//

#if os(iOS)
import AVFoundation
import XCTest
@testable import RunMirrorPhone

final class RunAudioSessionTests: XCTestCase {
    func testOffMixesWithMusicAtFullVolume() {
        let configuration = RunAudioSession.configuration(remoteControls: false)
        XCTAssertEqual(configuration.options, [.mixWithOthers])
    }

    func testOffDucksTheMusicForACue() {
        let configuration = RunAudioSession.cueConfiguration(remoteControls: false)
        XCTAssertEqual(configuration.options, [.mixWithOthers, .duckOthers])
    }

    func testOnTakesTheAudioSoTheRemoteCommandsComeHere() {
        for configuration in [RunAudioSession.configuration(remoteControls: true),
                              RunAudioSession.cueConfiguration(remoteControls: true)] {
            XCTAssertFalse(configuration.options.contains(.mixWithOthers))
            XCTAssertFalse(configuration.options.contains(.duckOthers))
        }
    }

    /// `.playback` is what the audio background mode keeps going locked.
    func testBothArePlaybackSoTheRunKeepsGoingLocked() {
        for on in [false, true] {
            for configuration in [RunAudioSession.configuration(remoteControls: on),
                                  RunAudioSession.cueConfiguration(remoteControls: on)] {
                XCTAssertEqual(configuration.category, .playback)
                XCTAssertEqual(configuration.mode, .spokenAudio)
            }
        }
    }

    func testActivatingAppliesTheConfiguration() {
        let session = AVAudioSession.sharedInstance()
        for on in [false, true] {
            RunAudioSession.activate(remoteControls: on)
            let configuration = RunAudioSession.configuration(remoteControls: on)
            XCTAssertEqual(session.category, configuration.category)
            XCTAssertEqual(session.mode, configuration.mode)
            XCTAssertEqual(session.categoryOptions, configuration.options)
        }
        try? session.setActive(false)
    }

    func testTheSettingDecidesByDefault() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: RunRemote.enabledKey)
        defer { defaults.set(saved, forKey: RunRemote.enabledKey) }

        defaults.removeObject(forKey: RunRemote.enabledKey)
        XCTAssertFalse(RunRemote.isEnabled, "Off unless turned on")
        defaults.set(true, forKey: RunRemote.enabledKey)
        XCTAssertTrue(RunRemote.isEnabled)
    }
}
#endif
