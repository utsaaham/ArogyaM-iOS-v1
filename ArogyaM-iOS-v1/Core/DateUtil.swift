import Foundation

enum DateUtil {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Today as the `yyyy-MM-dd` local-calendar key the API expects.
    static var todayKey: String { dayFormatter.string(from: Date()) }

    static func key(for date: Date) -> String { dayFormatter.string(from: date) }

    static func date(fromKey key: String) -> Date? { dayFormatter.date(from: key) }

    /// Short label like "Mon, Jun 22" from a `yyyy-MM-dd` key.
    static func shortLabel(fromKey key: String) -> String {
        guard let date = dayFormatter.date(from: key) else { return key }
        let out = DateFormatter()
        out.dateFormat = "EEE, MMM d"
        return out.string(from: date)
    }
}
