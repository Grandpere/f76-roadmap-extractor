import Foundation

public struct DayMonth: Codable, Equatable {
    public let day: Int?
    public let month: Int
    public let year: Int?

    public init(day: Int?, month: Int, year: Int? = nil) {
        self.day = day
        self.month = month
        self.year = year
    }

    public var isoLikeString: String {
        let resolvedYear = year.map { String(format: "%04d", $0) } ?? "XXXX"
        let resolvedDay = day.map { String(format: "%02d", $0) } ?? "XX"
        return "\(resolvedYear)-\(String(format: "%02d", month))-\(resolvedDay)"
    }
}

public struct EventDateRange: Codable, Equatable {
    public let raw: String
    public let start: DayMonth
    public let end: DayMonth?

    public init(raw: String, start: DayMonth, end: DayMonth?) {
        self.raw = raw
        self.start = start
        self.end = end
    }
}

public struct CalendarEvent: Codable, Equatable {
    public let title: String
    public let date: EventDateRange
    public let section: String?
    public let sourceLines: [String]

    public init(title: String, date: EventDateRange, section: String?, sourceLines: [String]) {
        self.title = title
        self.date = date
        self.section = section
        self.sourceLines = sourceLines
    }
}

public struct ExtractionResult: Codable, Equatable {
    public let locale: String
    public let source: String
    public let events: [CalendarEvent]
    public let rawLines: [String]

    public init(locale: String, source: String, events: [CalendarEvent], rawLines: [String]) {
        self.locale = locale
        self.source = source
        self.events = events
        self.rawLines = rawLines
    }
}

public struct OCRDebugLine: Codable, Equatable {
    public let text: String
    public let minX: Double
    public let minY: Double
    public let profile: String

    public init(text: String, minX: Double, minY: Double, profile: String) {
        self.text = text
        self.minX = minX
        self.minY = minY
        self.profile = profile
    }
}

public struct OCRDebugProfileDump: Codable, Equatable {
    public let profile: String
    public let lines: [OCRDebugLine]

    public init(profile: String, lines: [OCRDebugLine]) {
        self.profile = profile
        self.lines = lines
    }
}

public struct ExtractionDebugDump: Codable, Equatable {
    public let source: String
    public let locale: String
    public let profiles: [OCRDebugProfileDump]
    public let mergedLines: [OCRDebugLine]
    public let result: ExtractionResult

    public init(source: String, locale: String, profiles: [OCRDebugProfileDump], mergedLines: [OCRDebugLine], result: ExtractionResult) {
        self.source = source
        self.locale = locale
        self.profiles = profiles
        self.mergedLines = mergedLines
        self.result = result
    }
}
