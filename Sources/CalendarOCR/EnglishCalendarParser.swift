import Foundation

public struct EnglishCalendarParser: RoadmapCalendarParsing {
    private let inferredBaseYear: Int?

    let normalizationLocaleIdentifier = "en_US"

    private static let monthNames: [String: Int] = [
        "january": 1,
        "jan": 1,
        "february": 2,
        "feb": 2,
        "march": 3,
        "mar": 3,
        "april": 4,
        "apr": 4,
        "may": 5,
        "june": 6,
        "jun": 6,
        "july": 7,
        "jul": 7,
        "august": 8,
        "aug": 8,
        "september": 9,
        "sep": 9,
        "sept": 9,
        "october": 10,
        "oct": 10,
        "november": 11,
        "nov": 11,
        "noy": 11,
        "december": 12,
        "dec": 12,
        "january.": 1,
        "february.": 2,
        "march.": 3,
        "april.": 4,
        "may.": 5,
        "june.": 6,
        "july.": 7,
        "august.": 8,
        "september.": 9,
        "october.": 10,
        "november.": 11,
        "december.": 12,
    ]

    public init(inferredBaseYear: Int? = nil) {
        self.inferredBaseYear = inferredBaseYear
    }

    public func parse(lines: [String]) -> [CalendarEvent] {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var events: [CalendarEvent] = []
        var currentSection: String?
        var pendingDate: ParsedDateLine?
        var pendingTitleLines: [String] = []

        func flushPending() {
            guard let currentPending = pendingDate else { return }
            let title = buildTitle(from: pendingTitleLines)
            if !title.isEmpty {
                events.append(
                    CalendarEvent(
                        title: title,
                        date: currentPending.range,
                        section: currentSection,
                        sourceLines: currentPending.sourceLines + pendingTitleLines
                    )
                )
            }
            pendingTitleLines.removeAll()
            pendingDate = nil
        }

        for line in cleaned {
            if let section = sectionHeading(from: line) {
                flushPending()
                currentSection = section
                continue
            }

            if let dateLine = parsedDateLine(from: line, currentSection: currentSection) {
                flushPending()
                pendingDate = dateLine
                continue
            }

            if pendingDate != nil {
                pendingTitleLines.append(line)
            }
        }

        flushPending()
        return events
    }

    func sectionHeading(from line: String) -> String? {
        let normalized = normalizeToken(line)
        guard Self.monthNames[normalized] != nil else {
            return nil
        }
        return canonicalMonthName(for: normalized)
    }

    func dateRange(from line: String, currentSection: String?) -> EventDateRange? {
        parsedDateLine(from: line, currentSection: currentSection)?.range
    }

    func cleanedTitle(from lines: [String]) -> String {
        buildTitle(from: lines)
    }

    private func parsedDateLine(from line: String, currentSection: String?) -> ParsedDateLine? {
        let compact = line
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let dayFirstPattern = #"(?i)^\s*([0-9SOIl]{1,2})(?:ST|ND|RD|TH)?\s*([A-Za-z]+)?\s*(?:-\s*([0-9SOIl]{1,2})(?:ST|ND|RD|TH)?\s*([A-Za-z]+)?)?\s*$"#
        let monthFirstPattern = #"(?i)^\s*([A-Za-z]+)\s*([0-9SOIl]{1,2})(?:ST|ND|RD|TH)?\s*(?:-\s*([A-Za-z]+)?\s*([0-9SOIl]{1,2})(?:ST|ND|RD|TH)?)?\s*$"#

        let firstDay: Int?
        let firstMonthToken: String?
        let secondDay: Int?
        let secondMonthToken: String?

        if let regex = try? NSRegularExpression(pattern: monthFirstPattern),
           let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)) {
            firstMonthToken = stringGroup(1, in: compact, match: match)
            firstDay = dayGroup(2, in: compact, match: match)
            secondMonthToken = stringGroup(3, in: compact, match: match)
            secondDay = dayGroup(4, in: compact, match: match)
        } else if let regex = try? NSRegularExpression(pattern: dayFirstPattern),
                  let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)) {
            firstDay = dayGroup(1, in: compact, match: match)
            firstMonthToken = stringGroup(2, in: compact, match: match)
            secondDay = dayGroup(3, in: compact, match: match)
            secondMonthToken = stringGroup(4, in: compact, match: match)
        } else {
            return nil
        }

        guard let firstDay, (1...31).contains(firstDay) else {
            return nil
        }
        if let secondDay, !(1...31).contains(secondDay) {
            return nil
        }

        let fallbackMonthToken = currentSection.map(normalizeToken)
        let firstMonth = monthNumber(from: firstMonthToken) ?? fallbackMonthToken.flatMap(monthNumber(from:))

        guard let resolvedFirstMonth = firstMonth else {
            return nil
        }

        let sectionMonth = fallbackMonthToken.flatMap(monthNumber(from:))
        let endMonth = inferEndMonth(
            explicitEndMonth: monthNumber(from: secondMonthToken),
            secondDay: secondDay,
            firstDay: firstDay,
            startMonth: resolvedFirstMonth,
            sectionMonth: sectionMonth
        )

        let startYear = inferYear(forMonth: resolvedFirstMonth)
        let endYear = endMonth.flatMap(inferYear(forMonth:))

        let start = DayMonth(day: firstDay, month: resolvedFirstMonth, year: startYear)
        let end = endMonth.map { DayMonth(day: secondDay, month: $0, year: endYear) }
        let raw = canonicalRaw(start: start, end: end)

        return ParsedDateLine(
            range: EventDateRange(raw: raw, start: start, end: end),
            sourceLines: [line]
        )
    }

    private func normalizeTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildTitle(from lines: [String]) -> String {
        let uniqueLines = deduplicatedNormalizedLines(lines)
            .filter { !isIgnorableTitleLine($0) }

        return normalizeTitle(uniqueLines.joined(separator: " "))
    }

    private func deduplicatedNormalizedLines(_ lines: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for line in lines {
            let normalized = normalizeTitle(line)
            guard !normalized.isEmpty else { continue }
            let key = normalizeToken(normalized)
            if seen.insert(key).inserted {
                result.append(normalized)
            }
        }

        return result
    }

    private func isIgnorableTitleLine(_ line: String) -> Bool {
        let normalized = normalizeToken(line)
        if Self.monthNames[normalized] != nil {
            return true
        }

        if normalized.contains("season ") {
            return true
        }

        let ignoredPrefixes = [
            "c.a.m.p. theme",
            "community calendar",
            "bethesda",
            "fallout day",
        ]

        return ignoredPrefixes.contains(where: { normalized.hasPrefix($0) })
    }

    private func normalizeToken(_ token: String) -> String {
        token
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,:;"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func monthNumber(from token: String?) -> Int? {
        guard let token else { return nil }
        return Self.monthNames[normalizeToken(token)]
    }

    private func inferEndMonth(
        explicitEndMonth: Int?,
        secondDay: Int?,
        firstDay: Int,
        startMonth: Int,
        sectionMonth: Int?
    ) -> Int? {
        if let explicitEndMonth {
            return explicitEndMonth
        }
        guard secondDay != nil else {
            return nil
        }
        if let secondDay, secondDay < firstDay {
            if let sectionMonth, sectionMonth != startMonth {
                return sectionMonth
            }
            return startMonth == 12 ? 1 : startMonth + 1
        }
        return startMonth
    }

    private func canonicalRaw(start: DayMonth, end: DayMonth?) -> String {
        let startString = canonicalDateString(for: start)
        guard let end else {
            return startString
        }
        return "\(startString) - \(canonicalDateString(for: end))"
    }

    private func canonicalDateString(for date: DayMonth) -> String {
        let dayPart = date.day.map(String.init) ?? ""
        let monthPart = canonicalMonthName(for: date.month)
        if dayPart.isEmpty {
            return monthPart
        }
        return "\(dayPart) \(monthPart)"
    }

    private func canonicalMonthName(for normalizedToken: String) -> String {
        let month = Self.monthNames[normalizedToken] ?? 1
        return canonicalMonthName(for: month)
    }

    private func canonicalMonthName(for month: Int) -> String {
        let names = [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
        ]
        return names[max(0, min(names.count - 1, month - 1))]
    }

    private func inferYear(forMonth month: Int) -> Int? {
        guard let inferredBaseYear else { return nil }
        return month >= 9 ? inferredBaseYear : inferredBaseYear + 1
    }

    private func intGroup(_ index: Int, in line: String, match: NSTextCheckingResult) -> Int? {
        guard let value = stringGroup(index, in: line, match: match) else { return nil }
        return Int(value)
    }

    private func dayGroup(_ index: Int, in line: String, match: NSTextCheckingResult) -> Int? {
        guard let value = stringGroup(index, in: line, match: match) else { return nil }

        let repaired = value
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "o", with: "0")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "l", with: "1")
            .replacingOccurrences(of: "S", with: "5")
            .replacingOccurrences(of: "s", with: "5")

        return Int(repaired)
    }

    private func stringGroup(_ index: Int, in line: String, match: NSTextCheckingResult) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: line) else {
            return nil
        }
        return String(line[swiftRange])
    }
}

private struct ParsedDateLine {
    let range: EventDateRange
    let sourceLines: [String]
}
