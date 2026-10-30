import Foundation
import IOKit.ps

enum BatteryReader {
    static func read() -> BatteryInfo? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue()
                    as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let isAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            var minutes: Int?
            if !isAC, !isCharging {
                let estimate = IOPSGetTimeRemainingEstimate()
                if estimate != kIOPSTimeRemainingUnknown, estimate > 0 {
                    minutes = Int((estimate / 60).rounded())
                }
            }
            return BatteryInfo(
                level: description[kIOPSCurrentCapacityKey] as? Int ?? 0,
                isCharging: isCharging,
                isAC: isAC,
                timeRemainingMinutes: minutes
            )
        }
        return nil
    }
}
