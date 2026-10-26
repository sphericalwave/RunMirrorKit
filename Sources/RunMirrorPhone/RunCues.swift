//
//  RunCues.swift
//  RunMirrorKit
//
//  What a workout run sounds like: each hold announced by name, a tick for
//  the last three seconds, a tone at the end of a round and of the workout.
//  A silent loop keeps the audio session — and so the timer — alive with the
//  screen locked; the app must declare the audio background mode.
//
//  The session is `RunAudioSession`'s: mixed with music, dipping it only
//  while something is said (`CueDucker`), unless the AirPods & lock-screen
//  controls (`RunRemote`) are on.
//

import AVFoundation
import AudioToolbox
import Foundation

public protocol RunCueing {
    func begin()
    func announce(_ text: String)
    func tick()
    func roundDone(_ text: String)
    func finish(_ text: String)
    func end()
}

public final class RunCues: NSObject, RunCueing, AVSpeechSynthesizerDelegate {
    public static let shared = RunCues()

    private let synth = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let silence = AVAudioPlayerNode()
    private var running = false
    private var endAfterSpeech = false
    #if os(iOS)
    private let ducker = CueDucker()
    #endif

    override private init() {
        super.init()
        synth.delegate = self
        // A call, or AirPods connecting, stops the engine; the silence has to
        // start again or the run stops with the screen locked.
        NotificationCenter.default.addObserver(self, selector: #selector(engineStopped),
                                               name: .AVAudioEngineConfigurationChange, object: engine)
        #if os(iOS)
        NotificationCenter.default.addObserver(self, selector: #selector(interruptionChanged(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
        #endif
    }

    public func begin() {
        // Another round can start while "Workout complete" is still being said.
        endAfterSpeech = false
        guard !running else { return }
        #if os(iOS)
        ducker.begin(remoteControls: RunRemote.isEnabled)
        #endif
        playSilence()
        running = true
    }

    private func playSilence() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let frames = AVAudioFrameCount(22_050)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        if !engine.attachedNodes.contains(silence) { engine.attach(silence) }
        engine.connect(silence, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            silence.scheduleBuffer(buffer, at: nil, options: .loops)
            silence.play()
        } catch {
            // Still works in the foreground; it just won't survive a lock.
        }
    }

    /// Posted off the main thread.
    @objc nonisolated private func engineStopped() {
        Task { @MainActor in restartSilence() }
    }

    private func restartSilence() {
        guard running, !engine.isRunning else { return }
        silence.stop()
        playSilence()
    }

    #if os(iOS)
    @objc nonisolated private func interruptionChanged(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
        Task { @MainActor in
            guard running else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            restartSilence()
        }
    }
    #endif

    public func announce(_ text: String) {
        #if os(iOS)
        if running { ducker.cueStarted() }
        #endif
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        synth.speak(utterance)
    }

    public func tick() { AudioServicesPlaySystemSound(1103) }

    public func roundDone(_ text: String) {
        AudioServicesPlaySystemSound(1057)
        announce(text)
    }

    /// The last words, then the session released once they've been said —
    /// tearing it down straight away cuts them off.
    public func finish(_ text: String) {
        AudioServicesPlaySystemSound(1025)
        endAfterSpeech = true
        announce(text)
    }

    public func end() {
        guard running else { return }
        running = false
        silence.stop()
        engine.stop()
        #if os(iOS)
        ducker.end()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard !synthesizer.isSpeaking else { return }
        guard endAfterSpeech else {
            #if os(iOS)
            ducker.cueEnded()
            #endif
            return
        }
        endAfterSpeech = false
        end()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        #if os(iOS)
        if !synthesizer.isSpeaking { ducker.cueEnded() }
        #endif
    }
}
