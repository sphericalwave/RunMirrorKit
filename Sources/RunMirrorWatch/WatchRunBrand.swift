//
//  WatchRunBrand.swift
//  RunMirrorKit
//
//  What makes the wrist's run one app's and not another's: the name its
//  workouts carry in Health, what kind of workout they record as, and the
//  words on the screens with no run to show.
//

#if os(watchOS)
import HealthKit
import SwiftUI

public struct WatchRunBrand {
    /// Tags each workout saved (brand name, `SWSourceApp`, sync identifier),
    /// so another app reading Health can tell it's this one's.
    public var name: String
    public var activityType: HKWorkoutActivityType
    public var wording: Wording

    public init(name: String, activityType: HKWorkoutActivityType, wording: Wording) {
        self.name = name
        self.activityType = activityType
        self.wording = wording
    }

    public struct Wording {
        /// Nothing running: "No workout running".
        public var idleTitle: String
        public var idleDetail: String
        public var idleSymbol: String
        /// Ended on the phone: "Workout done".
        public var doneTitle: String
        public var doneDetail: String
        /// Put away with Later: "Saved for later".
        public var leftTitle: String
        public var leftDetail: String
        /// End's confirmation: "End workout?" and what it does.
        public var endTitle: String
        public var endMessage: String

        public init(idleTitle: String, idleDetail: String, idleSymbol: String,
                    doneTitle: String, doneDetail: String,
                    leftTitle: String, leftDetail: String,
                    endTitle: String, endMessage: String) {
            self.idleTitle = idleTitle
            self.idleDetail = idleDetail
            self.idleSymbol = idleSymbol
            self.doneTitle = doneTitle
            self.doneDetail = doneDetail
            self.leftTitle = leftTitle
            self.leftDetail = leftDetail
            self.endTitle = endTitle
            self.endMessage = endMessage
        }
    }
}
#endif
