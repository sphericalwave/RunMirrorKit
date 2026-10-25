//
//  RunRemote.swift
//  RunMirrorKit
//
//  A workout run with the phone in a pocket: published as Now Playing, so
//  the hold in progress and its countdown show on the lock screen and the
//  Apple Watch's Now Playing app, and play/pause/next/previous there — or a
//  squeeze of the AirPods — pause, resume, and go forward or back a hold.
//
//  iOS only hands those controls to an app whose audio doesn't mix with
//  others, so with this on a run pauses your music; off, music plays on
//  under the cues and the controls stay with the music app.
//
//  A phone call pauses the run, and it picks up again after if iOS says it
//  should (`RunInterruptions`).
//

import AVFoundation
import Foundation
import MediaPlayer
import RunMirrorKit

public final class RunRemote {
    public static let shared = RunRemote()

    public static let enabledKey = "runPocketControls"
    /// Off unless turned on, so music keeps playing by default.
    public static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    private var onPlay: (() -> Void)?
    private var onPause: (() -> Void)?
    private var onNext: (() -> Void)?
    private var onPrevious: (() -> Void)?
    private var isActive = false
    private var targets: [(MPRemoteCommand, Any)] = []
    private var interruptions = RunInterruptions()
    private var isPaused: Bool { interruptions.isPaused }
    private var interruptionObserver: NSObjectProtocol?

    private init() {}

    public func activate(play: @escaping () -> Void, pause: @escaping () -> Void,
                  next: @escaping () -> Void, previous: @escaping () -> Void) {
        onPlay = play
        onPause = pause
        onNext = next
        onPrevious = previous
        guard !isActive else { return }
        isActive = true
        #if os(iOS)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in MainActor.assumeIsolated { self?.interrupted(note) } }
        #endif
        guard Self.isEnabled else { return }
        let center = MPRemoteCommandCenter.shared()
        add(center.playCommand) { $0.onPlay?() }
        add(center.pauseCommand) { $0.onPause?() }
        add(center.togglePlayPauseCommand) { $0.isPaused ? $0.onPlay?() : $0.onPause?() }
        add(center.nextTrackCommand) { $0.onNext?() }
        add(center.previousTrackCommand) { $0.onPrevious?() }
        center.changePlaybackPositionCommand.isEnabled = false
    }

    private func add(_ command: MPRemoteCommand, _ action: @escaping (RunRemote) -> Void) {
        command.isEnabled = true
        // Remote commands arrive on the main thread.
        let token = command.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return .commandFailed }
                action(self)
                return .success
            }
        }
        targets.append((command, token))
    }

    /// The hold or rest in progress. iOS counts the elapsed time on from
    /// here by itself, so this is only needed when something changes.
    public func update(title: String, artist: String, album: String,
                duration: Int, elapsed: Int, paused: Bool) {
        guard isActive else { return }
        interruptions.runChanged(paused: paused)
        guard !targets.isEmpty else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPMediaItemPropertyPlaybackDuration: Double(duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(max(0, elapsed)),
            MPNowPlayingInfoPropertyPlaybackRate: paused ? 0.0 : 1.0,
        ]
    }

    public func deactivate() {
        guard isActive else { return }
        isActive = false
        for (command, token) in targets { command.removeTarget(token) }
        targets = []
        onPlay = nil
        onPause = nil
        onNext = nil
        onPrevious = nil
        interruptions.reset()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    #if os(iOS)
    private func interrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        let action: RunInterruptions.Action?
        switch type {
        case .began:
            action = interruptions.began()
        case .ended:
            let raw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            action = interruptions.ended(
                shouldResume: AVAudioSession.InterruptionOptions(rawValue: raw).contains(.shouldResume))
        @unknown default:
            action = nil
        }
        switch action {
        case .pause: onPause?()
        case .resume: onPlay?()
        case nil: break
        }
    }
    #endif
}
