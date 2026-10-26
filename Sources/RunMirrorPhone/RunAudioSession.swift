//
//  RunAudioSession.swift
//  RunMirrorKit
//
//  How a run's audio sits with whatever else is playing.
//
//  By default it mixes: music plays on at full volume, dipping only while a
//  cue is being spoken (`CueDucker`), and the run is driven from the screen
//  or the Apple Watch app. The watch's buttons come over WatchConnectivity
//  (`WatchRunLink`), so they never need anything from the audio session.
//
//  With the AirPods & lock-screen controls on (`RunRemote`) it doesn't mix,
//  since iOS only hands play/pause/next/previous to an app whose audio
//  doesn't — so the music pauses for the run.
//
//  Both are `.playback`, which is what lets `RunCues`' silent loop keep the
//  timer, the cues and the watch updates going with the screen locked (the
//  app declares the audio background mode). A mixable session is kept alive
//  in the background the same way as one that isn't.
//

#if os(iOS)
import AVFoundation

public enum RunAudioSession {
    public struct Configuration: Equatable {
        public var category: AVAudioSession.Category
        public var mode: AVAudioSession.Mode
        public var options: AVAudioSession.CategoryOptions
    }

    /// For the whole run. Mixing without ducking, so the silent loop leaves
    /// the music at full volume.
    public static func configuration(remoteControls: Bool) -> Configuration {
        Configuration(category: .playback, mode: .spokenAudio,
                      options: remoteControls ? [] : [.mixWithOthers])
    }

    /// While a cue is being spoken: the music dips under it.
    public static func cueConfiguration(remoteControls: Bool) -> Configuration {
        Configuration(category: .playback, mode: .spokenAudio,
                      options: remoteControls ? [] : [.mixWithOthers, .duckOthers])
    }

    /// Configures and activates the shared session for a run.
    public static func activate(remoteControls: Bool = RunRemote.isEnabled) {
        apply(configuration(remoteControls: remoteControls))
    }

    nonisolated static func apply(_ configuration: Configuration) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(configuration.category, mode: configuration.mode,
                                 options: configuration.options)
        try? session.setActive(true)
    }
}

/// Dips the music for a cue and brings it back after.
///
/// The way back is reconfiguring to mix-only while staying active, not
/// deactivating: deactivating would stop the silent loop, and with it the
/// timer once the screen is locked. Cues close together — a hold's name
/// straight after a round's tone — share one dip instead of pumping the
/// music between them.
final class CueDucker {
    /// How long the music stays down after a cue, in case another follows.
    static let hold: TimeInterval = 0.6

    private let apply: (RunAudioSession.Configuration) -> Void
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private var remoteControls = false
    private var ducked = false
    /// Bumped to call off a scheduled release.
    private var generation = 0

    init(apply: @escaping (RunAudioSession.Configuration) -> Void = RunAudioSession.apply,
         schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated(work) }
         }) {
        self.apply = apply
        self.schedule = schedule
    }

    /// Sets the session up for a run.
    func begin(remoteControls: Bool) {
        generation += 1
        self.remoteControls = remoteControls
        ducked = false
        apply(RunAudioSession.configuration(remoteControls: remoteControls))
    }

    func cueStarted() {
        generation += 1
        // Not mixing, the music is already paused: nothing to dip.
        guard !remoteControls, !ducked else { return }
        ducked = true
        apply(RunAudioSession.cueConfiguration(remoteControls: false))
    }

    func cueEnded() {
        guard ducked else { return }
        generation += 1
        let scheduled = generation
        schedule(Self.hold) { [weak self] in
            guard let self, ducked, generation == scheduled else { return }
            ducked = false
            apply(RunAudioSession.configuration(remoteControls: false))
        }
    }

    /// The run's over; the caller releases the session.
    func end() {
        generation += 1
        ducked = false
    }
}
#endif
