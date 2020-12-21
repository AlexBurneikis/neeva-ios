import Foundation

let dateParser = ISO8601DateFormatter()

public enum DateTimeVisualSpec {
    case compact
    case news
    case currency
    case full
    public static let `default` = Self.full
}

extension TimeInterval {
    static func minutes(_ n: Double) -> Self { n * 60 }
    static func hours(_ n: Double) -> Self { .minutes(n * 60) }
    static func days(_ n: Double) -> Self { .hours(n * 24) }

    var seconds: Int { Int(self) }
    var minutes: Int { seconds / 60 }
    var hours: Int { minutes / 60 }
    var days: Int { hours / 24 }
}

func formatter(for format: String) -> (Date) -> String {
    let df = DateFormatter()
    df.dateFormat = format
    return df.string(from:)
}

struct DateFormatters {
    static let compactSameYear = formatter(for: "MMM d")
    static let compactDifferentYear = formatter(for: "d MMM y")

    static let newsTime = formatter(for: "h:mm a")

    static let fullTime = formatter(for: "h:mma")
    static let fullSameYear = formatter(for: "MMM do")
    static let fullDifferentYear = formatter(for: "MMM do y")

    // pretty similar to require('date-fns').formatDistance but not exactly the same
    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

let calendar = Calendar(identifier: .gregorian)
extension Date {
    var gregorianYear: Int { calendar.component(.year, from: self) }
    var dayOfGregorianYear: Int { calendar.ordinality(of: .day, in: .year, for: self)! }
}
func isSameDay(_ date1: Date, _ date2: Date) -> Bool {
    calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date1)
        == calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date2)
}

public func format(_ string: String?, as visualSpec: DateTimeVisualSpec = .default, from now: Date = Date()) -> String? {
    if let string = string,
       let date = dateParser.date(from: string) {
        return format(date, as: visualSpec, from: now)
    } else {
        return nil
    }
}

// Keep in sync with formatDateTime from the main codebase
public func format(_ time: Date, as visualSpec: DateTimeVisualSpec = .default, from now: Date = Date()) -> String {
    switch visualSpec {
    case .compact:
        if time < now {
            if time > (now - .minutes(1)) {
                return "\(time.distance(to: now).seconds)s"
            } else if time > (now - .hours(1)) {
                return "\(time.distance(to: now).minutes)m"
            } else if time > (now - .days(1)) {
                return "\(time.distance(to: now).hours)h"
            } else if time.gregorianYear == now.gregorianYear {
                    return DateFormatters.compactSameYear(time)
            } else {
                return DateFormatters.compactDifferentYear(time)
            }
        } else {
            if time < (now + .minutes(1)) {
                return "\(time.distance(to: now).seconds)s"
            } else if time < (now + .hours(1)) {
                return "\(time.distance(to: now).minutes)m"
            } else if time < (now + .days(1)) {
                return "\(time.distance(to: now).hours)h"
            } else if time.gregorianYear == now.gregorianYear {
                return DateFormatters.compactSameYear(time)
            } else {
                return DateFormatters.compactDifferentYear(time)
            }
        }
    case .news:
        if time >= now {
            // Future news means time travel, which we don't support :)
            return ""
        } else {
            if isSameDay(time, now) {
                return DateFormatters.newsTime(time).uppercased()
            } else if time.gregorianYear == now.gregorianYear {
                return DateFormatters.compactSameYear(time).uppercased()
            } else {
                return DateFormatters.compactDifferentYear(time).uppercased()
            }
        }
    case .currency:
        if time >= now {
            // Future fetch date means time travel, which we don't support :)
            return ""
        } else {
            let dayDiff = now.timeIntervalSince(time).days
            if dayDiff == 0 {
                return "Today"
            } else if dayDiff == 1 {
                return "Yesterday"
            } else if dayDiff < 7 {
                return "\(dayDiff) days ago"
            } else {
                return DateFormatters.fullSameYear(time)
            }
        }
    case .full:
        if time > now - .hours(1) && time < now {
            return DateFormatters.relative.localizedString(for: time, relativeTo: now)
        } else if isSameDay(time, now) {
            return DateFormatters.fullTime(time)
        } else if isSameDay(time, now - .days(1)) {
            return "Yesterday \(DateFormatters.fullTime(time))"
        } else if time.gregorianYear == now.gregorianYear {
            let dayDiff = now.dayOfGregorianYear - time.dayOfGregorianYear
            if 1 < dayDiff && dayDiff <= 7 {
                return "\(dayDiff) days ago"
            } else if dayDiff == 1 {
                return "yesterday"
            } else if dayDiff == -1 {
                return "tomorrow"
            } else {
                return DateFormatters.fullSameYear(time)
            }
        } else {
            return DateFormatters.fullDifferentYear(time)
        }
    }
}
