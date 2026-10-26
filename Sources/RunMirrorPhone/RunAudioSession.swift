//
//  RunAudioSession.swift
//  RunMirrorKit
//
//  How a run's audio sits with whatever else is playing.
//
//  By default it mixes: music plays on, quieter while the run's audio is
//  up, and the run is driven from the screen or the Apple Watch app. The
//  watch's buttons come over WatchConnectivity (`WatchRunLink`), so they
//  never need anything from the audio session.
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

    public static func configuration(remoteControls: Bool) -> Configuration {
        Configuration(category: .playback, mode: .spokenAudio,
                      options: remoteControls ? [] : [.mixWithOthers, .duckOthers])
    }

    /// Configures and activates the shared session for a run.
    public static func activate(remoteControls: Bool = RunRemote.isEnabled) {
        let configuration = configuration(remoteControls: remoteControls)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(configuration.category, mode: configuration.mode,
                                 options: configuration.options)
        try? session.setActive(true)
    }
}
#endif
