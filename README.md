# RunMirrorKit

A guided run (timed holds, rounds) on the iPhone, mirrored on the Apple Watch, with the phone in a pocket. Extracted from bioMechanic (torque) so meditate can run its routines the same way.

## Products

- **RunMirrorKit**: every platform. Contains:
  - `WatchRunState`, `WatchRunCommand` and `WatchRunMessage`: what the phone and watch say to each other.
  - `WatchWorkoutSaveRule`: when the watch keeps its workout in Health.
  - `RunInterruptions`: a call pauses a run and resumes it after.
- **RunMirrorPhone**: iOS, plus a do-nothing macOS stand-in for the watch link. Contains:
  - `RunCues`: spoken holds and ticks, plus a silent keepalive that runs the timer with the screen locked. It ducks music, or doesn't mix when pocket controls are on. It restarts after interruptions and route changes.
  - `RunRemote`: Now Playing and lock-screen/AirPods ⏮⏯⏭.
  - `WatchRunLink`: the phone's end of the watch link. It sends application context plus live messages, and launches the watch app into its workout.
- **RunMirrorWatch**: watchOS. Contains:
  - `RunMirror`: the countdown from `endsAt`, plus haptics. The haptics are start, stop, a click for each of the last 3 s, and success at the end.
  - `PhoneLink`.
  - `WatchWorkout`: an HKWorkoutSession, saved per `WatchWorkoutSaveRule`.
  - The `RunRootView`, `RunView` and `EndPage` screens.
  - `WatchRunBrand`: the app's Health name, its activity type, and its wording.

## Using it

The phone app must:
- declare `UIBackgroundModes: audio`;
- call `WatchRunLink.shared.activate(activityType:)` at launch;
- `publish` a `WatchRunState` whenever the run changes;
- handle `onCommand`.

The watch app needs:
- the HealthKit capability;
- `WKBackgroundModes: workout-processing`;
- `RunMirror(brand:)`, activated at launch.

The session has one delegate:
- On the phone, `WatchRunLink.claim()` takes it for a run, and passes anything that isn't the run's to whoever had it before.
- On the watch, `PhoneLink.onOther` receives everything that isn't the run's.
