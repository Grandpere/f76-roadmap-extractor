import Foundation

public struct FrenchCalendarParser: RoadmapCalendarParsing {
    private let inferredBaseYear: Int?
    let normalizationLocaleIdentifier = "fr_FR"

    private static let monthNames: [String: Int] = [
        "janvier": 1,
        "fevrier": 2,
        "février": 2,
        "mars": 3,
        "avril": 4,
        "mai": 5,
        "juin": 6,
        "juillet": 7,
        "aout": 8,
        "août": 8,
        "septembre": 9,
        "octobre": 10,
        "novembre": 11,
        "decembre": 12,
        "décembre": 12,
        "janvier.": 1,
        "fevrier.": 2,
        "février.": 2,
        "septembre.": 9,
        "octobre.": 10,
        "novembre.": 11,
        "decembre.": 12,
        "décembre.": 12,
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

        let pattern = #"(?i)^\s*(\d{1,2})\s*([A-Za-zÉÈÊËÀÂÄÎÏÔÖÙÛÜÇéèêëàâäîïôöùûüç]+)?\s*(?:-\s*(\d{1,2})\s*([A-Za-zÉÈÊËÀÂÄÎÏÔÖÙÛÜÇéèêëàâäîïôöùûüç]+)?)?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)) else {
            return nil
        }

        let firstDay = intGroup(1, in: compact, match: match)
        let firstMonthToken = stringGroup(2, in: compact, match: match)
        let secondDay = intGroup(3, in: compact, match: match)
        let secondMonthToken = stringGroup(4, in: compact, match: match)

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
            "theme de c.a.m.p",
            "thème de c.a.m.p",
            "calendrier de la communaute",
            "calendrier de la communauté",
            "bethesda",
            "country road",
            "saison 18",
            "season 18",
            "borne zero et saison 18",
            "borne zero et saison 18 : country roads",
            "nouvelle mise a jour et saison 19",
            "les envahisseurs sont de retour",
            "evenement de jeu fallout day",
            "événement de jeu fallout day",
        ]

        return ignoredPrefixes.contains(where: { normalized.hasPrefix($0) })
    }

    private func normalizeToken(_ token: String) -> String {
        token
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
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

    private func inferYear(forMonth month: Int) -> Int? {
        guard let inferredBaseYear else { return nil }
        return month >= 1 && month <= 8 ? inferredBaseYear + 1 : inferredBaseYear
    }

    private func canonicalMonthName(for month: Int) -> String {
        switch month {
        case 1: return "JANVIER"
        case 2: return "FÉVRIER"
        case 3: return "MARS"
        case 4: return "AVRIL"
        case 5: return "MAI"
        case 6: return "JUIN"
        case 7: return "JUILLET"
        case 8: return "AOÛT"
        case 9: return "SEPTEMBRE"
        case 10: return "OCTOBRE"
        case 11: return "NOVEMBRE"
        case 12: return "DÉCEMBRE"
        default: return String(month)
        }
    }

    private func canonicalMonthName(for token: String) -> String {
        switch Self.monthNames[token] {
        case 1: return "Janvier"
        case 2: return "Février"
        case 3: return "Mars"
        case 4: return "Avril"
        case 5: return "Mai"
        case 6: return "Juin"
        case 7: return "Juillet"
        case 8: return "Août"
        case 9: return "Septembre"
        case 10: return "Octobre"
        case 11: return "Novembre"
        case 12: return "Décembre"
        default: return token.capitalized
        }
    }

    private func stringGroup(_ index: Int, in line: String, match: NSTextCheckingResult) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: line) else {
            return nil
        }
        let value = String(line[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func intGroup(_ index: Int, in line: String, match: NSTextCheckingResult) -> Int? {
        guard let value = stringGroup(index, in: line, match: match) else {
            return nil
        }
        return Int(value)
    }
}

private struct ParsedDateLine {
    let range: EventDateRange
    let sourceLines: [String]
}
