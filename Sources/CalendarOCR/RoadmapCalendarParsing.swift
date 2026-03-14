import Foundation

protocol RoadmapCalendarParsing {
    var normalizationLocaleIdentifier: String { get }

    func parse(lines: [String]) -> [CalendarEvent]
    func sectionHeading(from line: String) -> String?
    func dateRange(from line: String, currentSection: String?) -> EventDateRange?
    func cleanedTitle(from lines: [String]) -> String
}
