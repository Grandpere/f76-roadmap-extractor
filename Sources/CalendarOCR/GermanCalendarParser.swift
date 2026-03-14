import Foundation

public struct GermanCalendarParser: RoadmapCalendarParsing {
    private let inferredBaseYear: Int?

    let normalizationLocaleIdentifier = "de_DE"

    private static let monthNames: [String: Int] = [
        "januar": 1,
        "februar": 2,
        "marz": 3,
        "märz": 3,
        "april": 4,
        "mai": 5,
        "juni": 6,
        "juli": 7,
        "august": 8,
        "september": 9,
        "oktober": 10,
        "november": 11,
        "dezember": 12,
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

        let rangeWithMonthAfterStart = #"(?i)^\s*([0-9SOIl]{1,2})\.?\s*([A-Za-zÄÖÜäöüß]+)\s*(?:bis|-)\s*([0-9SOIl]{1,2})\.?\s*([A-Za-zÄÖÜäöüß]+)?\s*$"#
        let rangeWithoutMonthAfterStart = #"(?i)^\s*([0-9SOIl]{1,2})\.?\s*(?:bis|-)\s*([0-9SOIl]{1,2})\.?\s*([A-Za-zÄÖÜäöüß]+)\s*$"#
        let singlePattern = #"(?i)^\s*([0-9SOIl]{1,2})\.?\s*([A-Za-zÄÖÜäöüß]+)?\s*$"#

        let firstDay: Int?
        let firstMonthToken: String?
        let secondDay: Int?
        let secondMonthToken: String?

        if let regex = try? NSRegularExpression(pattern: rangeWithMonthAfterStart),
           let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)) {
            firstDay = dayGroup(1, in: compact, match: match)
            firstMonthToken = stringGroup(2, in: compact, match: match)
            secondDay = dayGroup(3, in: compact, match: match)
            secondMonthToken = stringGroup(4, in: compact, match: match)
        } else if let regex = try? NSRegularExpression(pattern: rangeWithoutMonthAfterStart),
                  let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)) {
            firstDay = dayGroup(1, in: compact, match: match)
            firstMonthToken = nil
            secondDay = dayGroup(2, in: compact, match: match)
            secondMonthToken = stringGroup(3, in: compact, match: match)
        } else if let regex = try? NSRegularExpression(pattern: singlePattern),
                  let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)) {
            firstDay = dayGroup(1, in: compact, match: match)
            firstMonthToken = stringGroup(2, in: compact, match: match)
            secondDay = nil
            secondMonthToken = nil
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

        let ignoredPrefixes = [
            "community calendar",
            "bethesda",
            "c.a.m.p. showcase",
            "rip daring",
            "and the",
            "cryptids from beyond the cosmos",
        ]

        return ignoredPrefixes.contains(where: { normalized.hasPrefix($0) })
    }

    private func normalizeToken(_ token: String) -> String {
        token
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
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
        guard let end else { return startString }
        return "\(startString) - \(canonicalDateString(for: end))"
    }

    private func canonicalDateString(for date: DayMonth) -> String {
        let dayPart = date.day.map(String.init) ?? ""
        let monthPart = canonicalMonthName(for: date.month)
        return dayPart.isEmpty ? monthPart : "\(dayPart) \(monthPart)"
    }

    private func canonicalMonthName(for normalizedToken: String) -> String {
        let month = Self.monthNames[normalizedToken] ?? 1
        return canonicalMonthName(for: month)
    }

    private func canonicalMonthName(for month: Int) -> String {
        let names = [
            "Januar", "Februar", "März", "April", "Mai", "Juni",
            "Juli", "August", "September", "Oktober", "November", "Dezember"
        ]
        return names[max(0, min(names.count - 1, month - 1))]
    }

    private func inferYear(forMonth month: Int) -> Int? {
        guard let inferredBaseYear else { return nil }
        return month >= 9 ? inferredBaseYear : inferredBaseYear + 1
    }

    private func stringGroup(_ index: Int, in line: String, match: NSTextCheckingResult) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: line) else {
            return nil
        }
        let value = String(line[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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
}

private struct ParsedDateLine {
    let range: EventDateRange
    let sourceLines: [String]
}
