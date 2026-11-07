//
//  PhoneLink.swift
//  RunMirrorKit
//
//  The watch's end of the run: the phone's latest state in, the buttons,
//  heart rate and any "workout not saved" note out. The phone runs the workout; nothing here decides
//  anything about it.
//
//  A command goes as a message with a reply, which brings the run back as
//  the phone has it after acting on it — no waiting for the phone's next
//  update. A message that fails is tried again a couple of times, then left
//  as application context; the phone ignores that if it's more than a few
//  seconds old by the time it lands, since a ⏭ delivered a minute later
//  would skip a hold nobody meant to skip. Every try of one press carries
//  the same id, so the phone acts on it once.
//
//  WCSession has one delegate, and this is it. Anything the phone sends that
//  isn't the run's goes to `onOther`, for the app's other features.
//

#if os(watchOS)
import Foundation
import Observation
import RunMirrorKit
import WatchConnectivity

@Observable
public final class PhoneLink: NSObject {
    public private(set) var isReachable = false
    /// Set when a command didn't get through, cleared by the next that does.
    public private(set) var sendFailed = false

    @ObservationIgnored public var onState: ((WatchRunState) -> Void)?
    /// A context or message that isn't the run's — on activation too, with
    /// whatever context was waiting.
    @ObservationIgnored public var onOther: (([String: Any]) -> Void)?

    public func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    /// Called when a command's messages all failed and it was left as
    /// application context — the run on the wrist may not be the phone's.
    @ObservationIgnored public var onCommandUndelivered: (() -> Void)?

    /// How many times a command's message is tried, and the wait before each retry.
    static let commandTries = 3
    static let retryAfter: Duration = .milliseconds(300)

    public func send(_ command: WatchRunCommand) {
        let message = WatchRunMessage.encode(command, id: UUID().uuidString, sentAt: Date())
        send(command: message, try: 1)
    }

    private func send(command message: [String: Any], try attempt: Int) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            sendFailed = true
            return
        }
        guard session.isReachable else {
            leave(command: message)
            return
        }
        session.sendMessage(message, replyHandler: { reply in
            let state = WatchRunMessage.state(in: reply)
            Task { @MainActor in
                self.sendFailed = false
                if let state { self.onState?(state) }
            }
        }, errorHandler: { _ in
            Task { @MainActor in
                guard attempt < Self.commandTries else {
                    self.leave(command: message)
                    return
                }
                try? await Task.sleep(for: Self.retryAfter * attempt)
                self.send(command: message, try: attempt + 1)
            }
        })
    }

    /// The last resort: delivered whenever the system gets to it, and acted
    /// on only if that's soon.
    private func leave(command message: [String: Any]) {
        sendFailed = true
        try? WCSession.default.updateApplicationContext(message)
        onCommandUndelivered?()
    }

    /// Live only: a reading that can't go now is stale by the time it could.
    public func send(heartRate bpm: Int) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(WatchRunMessage.encode(heartRate: bpm), replyHandler: nil, errorHandler: nil)
    }

    /// For the run's review. Queued when the phone's out of reach, since the
    /// review may well still be up when it's back.
    public func send(_ note: WatchWorkoutNote) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let message = WatchRunMessage.encode(note)
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(WatchRunMessage.encode(note))
            }
        } else {
            session.transferUserInfo(message)
        }
    }

    /// Asks the phone for the run as it stands; the answer comes back as
    /// `onState`. For when a state the phone sent didn't arrive — application
    /// context can wait on the system, and a message can be dropped — so the
    /// watch would otherwise sit on a run that's moved on. A phone with no run,
    /// or one too old to answer, replies with nothing.
    public func requestState() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(WatchRunMessage.encodeStateRequest(), replyHandler: { reply in
            guard let state = WatchRunMessage.state(in: reply) else { return }
            Task { @MainActor in self.onState?(state) }
        }, errorHandler: nil)
    }

    private func reachabilityChanged(_ reachable: Bool) {
        let regained = reachable && !isReachable
        isReachable = reachable
        if reachable { sendFailed = false }
        // Whatever was sent while out of reach may still be on its way.
        if regained { requestState() }
    }
}

extension PhoneLink: WCSessionDelegate {
    public nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        // Whatever the phone last said, waiting from before the app opened.
        let context = session.receivedApplicationContext
        let waiting = WatchRunMessage.state(in: context)
        let reachable = session.isReachable
        Task { @MainActor in
            self.reachabilityChanged(reachable)
            if let waiting { self.onState?(waiting) } else if !context.isEmpty { self.onOther?(context) }
        }
    }

    public nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.reachabilityChanged(reachable) }
    }

    public nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let state = WatchRunMessage.state(in: context) else {
            Task { @MainActor in self.onOther?(context) }
            return
        }
        Task { @MainActor in self.onState?(state) }
    }

    public nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let state = WatchRunMessage.state(in: message) else {
            Task { @MainActor in self.onOther?(message) }
            return
        }
        Task { @MainActor in self.onState?(state) }
    }
}
#endif
