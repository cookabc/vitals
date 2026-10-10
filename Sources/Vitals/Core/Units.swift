import Foundation

enum Units {
    static func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .decimal).locale(AppLanguage.current.locale))
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0.5 else { return "0 B/s" }
        return bytes(Int64(bytesPerSecond)) + "/s"
    }

    static func gigabytes(_ value: Int64) -> String {
        String(format: "%.1f GB", locale: AppLanguage.current.locale, Double(value) / 1_000_000_000)
    }
}
