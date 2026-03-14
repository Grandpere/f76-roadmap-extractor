import Foundation

public struct CalendarExtractor {
    private let textExtractor: ImageTextExtractor
    private let frenchParser: FrenchCalendarParser
    private let englishParser: EnglishCalendarParser
    private let germanParser: GermanCalendarParser

    public init(baseYear: Int? = nil) {
        self.textExtractor = ImageTextExtractor()
        self.frenchParser = FrenchCalendarParser(inferredBaseYear: baseYear)
        self.englishParser = EnglishCalendarParser(inferredBaseYear: baseYear)
        self.germanParser = GermanCalendarParser(inferredBaseYear: baseYear)
    }

    public func extract(from imageURL: URL, localeIdentifier: String = "fr-FR") throws -> ExtractionResult {
        let extractedLines = try textExtractor.extractLines(from: imageURL, localeIdentifier: localeIdentifier)
        let rawLines = extractedLines.map(\.text)
        let events = extractEvents(from: extractedLines, localeIdentifier: localeIdentifier, fallbackRawLines: rawLines)

        return ExtractionResult(
            locale: String(localeIdentifier.prefix(2)).lowercased(),
            source: imageURL.lastPathComponent,
            events: events,
            rawLines: rawLines
        )
    }

    public func extractWithDebug(from imageURL: URL, localeIdentifier: String = "fr-FR") throws -> ExtractionDebugDump {
        let debug = try textExtractor.extractDebugDump(from: imageURL, localeIdentifier: localeIdentifier)
        let rawLines = debug.merged.map(\.text)
        let events = extractEvents(from: debug.merged, localeIdentifier: localeIdentifier, fallbackRawLines: rawLines)

        let result = ExtractionResult(
            locale: String(localeIdentifier.prefix(2)).lowercased(),
            source: imageURL.lastPathComponent,
            events: events,
            rawLines: rawLines
        )

        return ExtractionDebugDump(
            source: imageURL.lastPathComponent,
            locale: localeIdentifier,
            profiles: debug.perProfile,
            mergedLines: debug.merged.map {
                OCRDebugLine(
                    text: $0.text,
                    minX: Double($0.minX),
                    minY: Double($0.minY),
                    profile: $0.profile.rawValue
                )
            },
            result: result
        )
    }

    private func extractEvents(from lines: [OCRTextLine], localeIdentifier: String, fallbackRawLines: [String]) -> [CalendarEvent] {
        switch localeIdentifier.prefix(2).lowercased() {
        case "fr":
            let spatialEvents = SpatialRoadmapCalendarParser(parser: frenchParser).parse(lines: lines)
            return spatialEvents.isEmpty ? frenchParser.parse(lines: fallbackRawLines) : spatialEvents
        case "en":
            let spatialEvents = SpatialRoadmapCalendarParser(parser: englishParser).parse(lines: lines)
            return spatialEvents.isEmpty ? englishParser.parse(lines: fallbackRawLines) : spatialEvents
        case "de":
            let spatialEvents = SpatialRoadmapCalendarParser(parser: germanParser).parse(lines: lines)
            return spatialEvents.isEmpty ? germanParser.parse(lines: fallbackRawLines) : spatialEvents
        default:
            return frenchParser.parse(lines: fallbackRawLines)
        }
    }
}

private struct SpatialRoadmapCalendarParser {
    let parser: any RoadmapCalendarParsing

    func parse(lines: [OCRTextLine]) -> [CalendarEvent] {
        let sections = monthSections(in: lines)
        var events: [CalendarEvent] = []

        for section in sections {
            let sectionEvents = parseEvents(in: section)
            events.append(contentsOf: sectionEvents)
        }

        return consolidated(events: events)
    }

    private func monthSections(in lines: [OCRTextLine]) -> [MonthSection] {
        let headings = lines.compactMap { line -> MonthHeading? in
            guard let month = parser.sectionHeading(from: line.text),
                  line.minX >= 0.43,
                  line.minX <= 0.56,
                  containsLowercaseLetter(line.text) else {
                return nil
            }
            return MonthHeading(title: month, y: line.minY)
        }
        .sorted { $0.y > $1.y }

        var uniqueHeadings: [MonthHeading] = []
        for heading in headings {
            if let last = uniqueHeadings.last, last.title == heading.title, abs(last.y - heading.y) < 0.03 {
                continue
            }
            uniqueHeadings.append(heading)
        }

        return uniqueHeadings.enumerated().map { index, heading in
            let nextY = index + 1 < uniqueHeadings.count ? uniqueHeadings[index + 1].y : 0
            let sectionLines = lines.filter { line in
                line.minY <= heading.y + 0.015 && line.minY > nextY + 0.01 && line.minX >= 0.43
            }
            return MonthSection(title: heading.title, topY: heading.y, bottomY: nextY, lines: sectionLines)
        }
    }

    private func parseEvents(in section: MonthSection) -> [CalendarEvent] {
        let candidateDates = deduplicatedDateCandidates(in: section)
        guard !candidateDates.isEmpty else { return [] }
        trace(section: section, candidates: candidateDates)

        let boundaries = columnBoundaries(for: candidateDates)
        let consumedDateLineKeys = Set(candidateDates.flatMap(\.consumedLineKeys))
        var events: [CalendarEvent] = []

        for (index, candidate) in candidateDates.enumerated() {
            let titleBlock = titleLines(
                for: candidate,
                index: index,
                candidates: candidateDates,
                boundaries: boundaries,
                section: section,
                consumedDateLineKeys: consumedDateLineKeys
            )
            let title = parser.cleanedTitle(from: titleBlock.map(\.text))
            guard !title.isEmpty else { continue }

            let sourceLines = [candidate.line.text] + titleBlock.map(\.text)
            let event = CalendarEvent(
                title: title,
                date: candidate.range,
                section: section.title,
                sourceLines: sourceLines
            )
            if !shouldDrop(candidate: event, becauseOfAnyOf: events) {
                events.append(event)
            }
        }

        return events
    }

    private func deduplicatedDateCandidates(in section: MonthSection) -> [DateCandidate] {
        let sortedLines = section.lines.sorted {
            if abs($0.minX - $1.minX) > 0.01 {
                return $0.minX < $1.minX
            }
            return $0.minY > $1.minY
        }

        var linesConsumedAsDateSupport: Set<String> = []
        let rawCandidates = sortedLines.compactMap { line -> DateCandidate? in
            if linesConsumedAsDateSupport.contains(lineKey(for: line)) {
                return nil
            }

            if let repaired = repairedDateCandidate(for: line, in: sortedLines, sectionTitle: section.title) {
                linesConsumedAsDateSupport.formUnion(repaired.consumedLineKeys)
                return repaired
            }

            guard let range = parser.dateRange(from: line.text, currentSection: section.title) else {
                return nil
            }
            return DateCandidate(line: line, range: range, consumedLineKeys: [lineKey(for: line)])
        }
        .sorted {
            if abs($0.line.minX - $1.line.minX) > 0.01 {
                return $0.line.minX < $1.line.minX
            }
            return $0.line.minY > $1.line.minY
        }

        var unique: [DateCandidate] = []
        for candidate in rawCandidates {
            if let last = unique.last,
               abs(last.line.minX - candidate.line.minX) < 0.025,
               abs(last.line.minY - candidate.line.minY) < 0.02,
               normalizedDateText(last.line.text) == normalizedDateText(candidate.line.text) {
                if candidate.line.text.count > last.line.text.count {
                    unique.removeLast()
                    unique.append(candidate)
                }
                continue
            }
            unique.append(candidate)
        }

        return unique
    }

    private func columnBoundaries(for candidates: [DateCandidate]) -> [ClosedRange<Double>] {
        let xs = candidates.map { Double($0.line.minX) }
        var boundaries: [ClosedRange<Double>] = []

        for index in xs.indices {
            let left = index == 0 ? 0.43 : (xs[index - 1] + xs[index]) / 2
            let right = index == xs.count - 1 ? 0.98 : (xs[index] + xs[index + 1]) / 2
            let lower = min(left, right)
            let upper = max(left, right)
            boundaries.append(lower...upper)
        }

        return boundaries
    }

    private func titleLines(
        for candidate: DateCandidate,
        index: Int,
        candidates: [DateCandidate],
        boundaries: [ClosedRange<Double>],
        section: MonthSection,
        consumedDateLineKeys: Set<String>
    ) -> [OCRTextLine] {
        let horizontalBand = boundaries[index]
        let centerX = Double(candidate.line.minX)
        let leftDistance = index > 0 ? centerX - Double(candidates[index - 1].line.minX) : centerX - horizontalBand.lowerBound
        let rightDistance = index + 1 < candidates.count ? Double(candidates[index + 1].line.minX) - centerX : horizontalBand.upperBound - centerX
        let maxHorizontalDistance = max(0.018, min(0.045, min(leftDistance, rightDistance) * 0.42))
        let minY = max(Double(candidate.line.minY) - 0.12, Double(section.bottomY))
        let maxY = Double(candidate.line.minY) - 0.008

        return section.lines.filter { line in
            let x = Double(line.minX)
            let y = Double(line.minY)
            guard horizontalBand.contains(x) else { return false }
            guard abs(x - centerX) <= maxHorizontalDistance else { return false }
            guard y >= minY && y <= maxY else { return false }
            guard !consumedDateLineKeys.contains(lineKey(for: line)) else { return false }
            guard parser.dateRange(from: line.text, currentSection: section.title) == nil else { return false }
            guard parser.sectionHeading(from: line.text) == nil else { return false }
            return !isDecoration(line.text)
        }
        .sorted {
            if abs($0.minY - $1.minY) > 0.01 {
                return $0.minY > $1.minY
            }
            return $0.minX < $1.minX
        }
        .contiguousVerticalCluster(maxGap: 0.03)
    }

    private func normalizedDateText(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: parser.normalizationLocaleIdentifier))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " - ", with: "-", options: .literal)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func trace(section: MonthSection, candidates: [DateCandidate]) {
        guard ProcessInfo.processInfo.environment["CALENDAR_TRACE"] == "1" else { return }
        let summary = candidates.map {
            "\($0.line.text)@x\(String(format: "%.3f", Double($0.line.minX)))@y\(String(format: "%.3f", Double($0.line.minY)))"
        }
        fputs("[trace] \(section.title): \(summary.joined(separator: " | "))\n", stderr)
    }

    private func consolidated(events: [CalendarEvent]) -> [CalendarEvent] {
        let sorted = events.sorted {
            if $0.date.start.month != $1.date.start.month {
                return $0.date.start.month < $1.date.start.month
            }
            let lhsDay = $0.date.start.day ?? 0
            let rhsDay = $1.date.start.day ?? 0
            if lhsDay != rhsDay {
                return lhsDay < rhsDay
            }
            return normalizedTitle($0.title).count > normalizedTitle($1.title).count
        }

        var kept: [CalendarEvent] = []

        outer: for event in sorted {
            for (index, existing) in kept.enumerated() {
                if shouldReplace(existing: existing, with: event) {
                    kept[index] = event
                    continue outer
                }
                if shouldDrop(candidate: event, becauseOf: existing) {
                    continue outer
                }
            }
            kept.append(event)
        }

        return kept
    }

    private func repairedDateCandidate(for line: OCRTextLine, in sortedLines: [OCRTextLine], sectionTitle: String) -> DateCandidate? {
        let normalized = normalizedDateText(line.text)
        guard normalized.contains("-") else { return nil }
        guard normalized.hasSuffix("-") else { return nil }

        let supports = sortedLines.filter { other in
            guard lineKey(for: other) != lineKey(for: line) else { return false }
            guard abs(Double(other.minX - line.minX)) <= 0.03 else { return false }
            let deltaY = Double(line.minY - other.minY)
            guard deltaY >= 0.0 && deltaY <= 0.03 else { return false }
            guard let supportRange = parser.dateRange(from: other.text, currentSection: sectionTitle) else { return false }
            guard supportRange.end == nil else { return false }
            return true
        }
        .sorted {
            let lhsDeltaY = abs(Double(line.minY - $0.minY))
            let rhsDeltaY = abs(Double(line.minY - $1.minY))
            if abs(lhsDeltaY - rhsDeltaY) > 0.002 {
                return lhsDeltaY < rhsDeltaY
            }
            return abs(Double(line.minX - $0.minX)) < abs(Double(line.minX - $1.minX))
        }

        guard let support = supports.first else { return nil }

        let mergedText = mergeDateFragments(primary: line.text, support: support.text)
        guard let mergedText,
              let range = parser.dateRange(from: mergedText, currentSection: sectionTitle) else {
            return nil
        }

        return DateCandidate(
            line: OCRTextLine(text: mergedText, minX: line.minX, minY: line.minY, profile: line.profile),
            range: range,
            consumedLineKeys: [lineKey(for: line), lineKey(for: support)]
        )
    }

    private func mergeDateFragments(primary: String, support: String) -> String? {
        let primaryNormalized = primary.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        let supportNormalized = support.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        guard primaryNormalized.hasSuffix("-") else { return nil }

        let supportTokens = supportNormalized.split(separator: " ").map(String.init)
        guard let firstToken = supportTokens.first, Int(firstToken) != nil else {
            return nil
        }

        return "\(primaryNormalized) \(supportNormalized)"
    }

    private func deduplicatedPreservingOrder(_ lines: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for line in lines {
            let normalized = normalizedTitle(line)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                result.append(line)
            }
        }

        return result
    }

    private func shouldReplace(existing: CalendarEvent, with candidate: CalendarEvent) -> Bool {
        guard sameDateSignature(existing, candidate) || partialSingleDayDuplicate(existing: existing, candidate: candidate) else { return false }
        return score(candidate) > score(existing)
    }

    private func shouldDrop(candidate: CalendarEvent, becauseOf existing: CalendarEvent) -> Bool {
        guard sameDateSignature(candidate, existing) || partialSingleDayDuplicate(existing: existing, candidate: candidate) else { return false }
        return score(existing) >= score(candidate)
    }

    private func shouldDrop(candidate: CalendarEvent, becauseOfAnyOf existingEvents: [CalendarEvent]) -> Bool {
        existingEvents.contains { shouldDrop(candidate: candidate, becauseOf: $0) }
    }

    private func sameDateSignature(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        lhs.date.start == rhs.date.start && lhs.date.end == rhs.date.end
    }

    private func partialSingleDayDuplicate(existing: CalendarEvent, candidate: CalendarEvent) -> Bool {
        let lhsRange = existing.date.end != nil
        let rhsRange = candidate.date.end != nil
        guard lhsRange != rhsRange else { return false }

        let ranged = lhsRange ? existing : candidate
        let single = lhsRange ? candidate : existing

        guard ranged.date.start == single.date.start else { return false }

        let rangedTitle = normalizedTitle(ranged.title)
        let singleTitle = normalizedTitle(single.title)
        if rangedTitle == singleTitle {
            return true
        }
        if !singleTitle.isEmpty && rangedTitle.contains(singleTitle) {
            return true
        }
        return false
    }

    private func score(_ event: CalendarEvent) -> Int {
        var total = normalizedTitle(event.title).count
        total += Set(event.sourceLines.map(normalizedTitle)).count * 8
        if let section = event.section,
           parser.sectionHeading(from: section) != nil,
           parser.dateRange(from: event.date.raw, currentSection: section)?.start.month == event.date.start.month {
            total += 20
        }
        if normalizedTitle(event.title).contains("fallout day") {
            total += 10
        }
        return total
    }

    private func normalizedTitle(_ title: String) -> String {
        title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: parser.normalizationLocaleIdentifier))
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func lineKey(for line: OCRTextLine) -> String {
        "\(round(line.minX * 1000))|\(round(line.minY * 1000))|\(normalizedTitle(line.text))"
    }

    private func isDecoration(_ text: String) -> Bool {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: parser.normalizationLocaleIdentifier))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let ignored = [
            "•",
            "o",
            "anna",
            "yield",
            "stop",
            "fallout",
            "76",
            "761",
            "milepost",
            "zero",
        ]
        return ignored.contains(normalized)
    }

    private func containsLowercaseLetter(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.lowercaseLetters.contains($0) }
    }
}

private extension Array where Element == OCRTextLine {
    func contiguousVerticalCluster(maxGap: Double) -> [OCRTextLine] {
        guard let first else { return [] }
        var cluster = [first]
        var previousY = Double(first.minY)

        for line in dropFirst() {
            let gap = previousY - Double(line.minY)
            if gap > maxGap {
                break
            }
            cluster.append(line)
            previousY = Double(line.minY)
        }

        return cluster
    }
}

private struct MonthHeading {
    let title: String
    let y: CGFloat
}

private struct MonthSection {
    let title: String
    let topY: CGFloat
    let bottomY: CGFloat
    let lines: [OCRTextLine]
}

private struct DateCandidate {
    let line: OCRTextLine
    let range: EventDateRange
    let consumedLineKeys: [String]
}
