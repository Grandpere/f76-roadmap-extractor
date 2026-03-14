import Foundation

public struct WebCalendarExport: Codable, Equatable {
    public let season: Int?
    public let name: String
    public let events: [WebCalendarEvent]

    public init(season: Int?, name: String, events: [WebCalendarEvent]) {
        self.season = season
        self.name = name
        self.events = events
    }
}

public struct WebCalendarEvent: Codable, Equatable {
    public let dateStart: String
    public let dateEnd: String
    public let title: String

    public init(dateStart: String, dateEnd: String, title: String) {
        self.dateStart = dateStart
        self.dateEnd = dateEnd
        self.title = title
    }

    enum CodingKeys: String, CodingKey {
        case dateStart = "date_start"
        case dateEnd = "date_end"
        case title
    }
}

public struct WebCalendarExporter {
    public init() {}

    public func export(result: ExtractionResult, fallbackBaseYear: Int? = nil) -> WebCalendarExport {
        let resolvedBaseYear = fallbackBaseYear ?? inferBaseYear(from: result.rawLines)
        let anchorMonth = result.events.map { $0.date.start.month }.min()
        let season = inferSeason(from: result.rawLines)
        let locale = result.locale.lowercased()
        let name = inferSeasonName(from: result.rawLines, locale: locale) ?? "Unknown"
        let normalizedEvents = normalizeEvents(result.events)
        let events = pruneWeakEvents(normalizedEvents
            .compactMap { makeEvent(from: $0, baseYear: resolvedBaseYear, anchorMonth: anchorMonth, locale: locale) }
            .sorted {
                if $0.dateStart != $1.dateStart {
                    return $0.dateStart < $1.dateStart
                }
                if $0.dateEnd != $1.dateEnd {
                    return $0.dateEnd < $1.dateEnd
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            })

        return WebCalendarExport(season: season, name: name, events: events)
    }

    private func normalizeEvents(_ events: [CalendarEvent]) -> [CalendarEvent] {
        var normalized = events
        var consumed = Set<Int>()

        for index in normalized.indices {
            guard !consumed.contains(index) else { continue }

            let current = normalized[index]
            guard current.date.end != nil,
                  isWeakCalendarEventTitle(current.title) else {
                continue
            }

            guard let replacementIndex = normalized.indices.first(where: { candidateIndex in
                guard candidateIndex != index, !consumed.contains(candidateIndex) else { return false }
                let candidate = normalized[candidateIndex]
                return candidate.section == current.section &&
                    candidate.date.start.day == current.date.start.day &&
                    candidate.date.start.month == current.date.start.month &&
                    candidate.date.end == nil &&
                    !isWeakCalendarEventTitle(candidate.title)
            }) else {
                continue
            }

            let replacement = normalized[replacementIndex]
            normalized[replacementIndex] = CalendarEvent(
                title: replacement.title,
                date: current.date,
                section: replacement.section,
                sourceLines: replacement.sourceLines + current.sourceLines
            )
            consumed.insert(index)
        }

        for index in normalized.indices where !consumed.contains(index) {
            let current = normalized[index]
            let currentHasRange = current.date.end != nil

            guard let counterpartIndex = normalized.indices.first(where: { candidateIndex in
                guard candidateIndex != index, !consumed.contains(candidateIndex) else { return false }
                let candidate = normalized[candidateIndex]
                return candidate.section == current.section &&
                    candidate.date.start.day == current.date.start.day &&
                    candidate.date.start.month == current.date.start.month &&
                    (candidate.date.end != nil) != currentHasRange
            }) else {
                continue
            }

            let rangedIndex = currentHasRange ? index : counterpartIndex
            let singleIndex = currentHasRange ? counterpartIndex : index
            let ranged = normalized[rangedIndex]
            let single = normalized[singleIndex]

            guard let mergedTitle = mergedComplementaryTitle(primary: ranged.title, secondary: single.title) else {
                continue
            }

            normalized[rangedIndex] = CalendarEvent(
                title: mergedTitle,
                date: ranged.date,
                section: ranged.section,
                sourceLines: deduplicatedSourceLines(ranged.sourceLines + single.sourceLines)
            )
            consumed.insert(singleIndex)
        }

        return normalized.enumerated().compactMap { consumed.contains($0.offset) ? nil : $0.element }
    }

    private func mergedComplementaryTitle(primary: String, secondary: String) -> String? {
        let primaryNormalized = normalize(primary)
        let secondaryNormalized = normalize(secondary)

        if primaryNormalized == secondaryNormalized {
            return primary
        }

        let pairs = [
            (primary, secondary),
            (secondary, primary),
        ]

        for (prefix, suffix) in pairs {
            let prefixNormalized = normalize(prefix)
            let suffixNormalized = normalize(suffix)

            if prefixNormalized.hasSuffix(" double") && suffixNormalized.hasPrefix("mutations") {
                return "\(prefix) \(suffix)"
            }

            if prefixNormalized.hasSuffix(" and") && !suffixNormalized.hasPrefix("and ") {
                return "\(prefix) \(suffix)"
            }
        }

        return nil
    }

    private func deduplicatedSourceLines(_ lines: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for line in lines {
            let normalized = normalize(line)
            guard seen.insert(normalized).inserted else { continue }
            result.append(line)
        }

        return result
    }

    func inferBaseYear(from rawLines: [String]) -> Int? {
        let yearRegex = try? NSRegularExpression(pattern: #"(19|20)\d{2}"#)

        for line in rawLines.reversed() {
            let normalized = normalize(line)
            guard normalized.contains("bethesda") || normalized.contains("zenimax") || normalized.contains("202") else {
                continue
            }
            guard let yearRegex,
                  let match = yearRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range, in: line) else {
                continue
            }
            return Int(line[range])
        }

        return nil
    }

    func inferSeason(from rawLines: [String]) -> Int? {
        let patterns = [
            #"(?i)\bsaison\s+(\d{1,2})\b"#,
            #"(?i)\bseason\s+(\d{1,2})\b"#,
        ]

        for line in rawLines {
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let range = Range(match.range(at: 1), in: line),
                      let season = Int(line[range]) else {
                    continue
                }
                return season
            }
        }

        return nil
    }

    func inferSeasonName(from rawLines: [String], locale: String = "fr") -> String? {
        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let extracted = seasonName(from: trimmed, locale: locale) {
                return extracted
            }
        }

        return nil
    }

    private func seasonName(from line: String, locale: String) -> String? {
        let patterns = [
            #"(?i)\b(?:borne\s+z[eé]ro\s+et\s+)?saison\s+\d{1,2}\s*[:\-]\s*(.+)$"#,
            #"(?i)\bseason\s+\d{1,2}\s*[:\-]\s*(.+)$"#,
            #"(?i)^(?:mise\s+[aà]\s+jour\s+)?(.+?)\s+et\s+saison\s+\d{1,2}$"#,
            #"(?i)^(?:update\s+)?(.+?)\s+and\s+season\s+\d{1,2}$"#,
            #"(?i)^(.+?)\s+und\s+saison\s+\d{1,2}$"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range(at: 1), in: line) else {
                continue
            }

            let candidate = line[range]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

            guard !candidate.isEmpty else { continue }
            return nameCase(cleanSeasonName(candidate), locale: locale)
        }

        return nil
    }

    private func cleanSeasonName(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"(?i)^mise\s+[aà]\s+jour\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^update\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^das\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s+et\s+saison\s+\d{1,2}$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s+and\s+season\s+\d{1,2}$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s+und\s+saison\s+\d{1,2}$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeEvent(from event: CalendarEvent, baseYear: Int?, anchorMonth: Int?, locale: String) -> WebCalendarEvent? {
        guard let start = resolvedDateParts(for: event.date.start, baseYear: baseYear, anchorMonth: anchorMonth) else {
            return nil
        }
        let endDate = event.date.end ?? event.date.start
        guard var end = resolvedDateParts(for: endDate, baseYear: baseYear, anchorMonth: anchorMonth) else {
            return nil
        }

        if (end.year, end.month, end.day) < (start.year, start.month, start.day) {
            if end.month < start.month || (end.month == start.month && end.day < start.day) {
                end.year = start.year + 1
            } else {
                end.year = start.year
            }
        }

        let cleanedTitle = editorialTitle(event.title, locale: locale)
        guard !shouldIgnoreEventTitle(cleanedTitle) else {
            return nil
        }

        return WebCalendarEvent(
            dateStart: start.iso8601,
            dateEnd: end.iso8601,
            title: cleanedTitle
        )
    }

    private func resolvedDateParts(for value: DayMonth, baseYear: Int?, anchorMonth: Int?) -> ResolvedDateParts? {
        guard let day = value.day else { return nil }
        let year = resolvedYear(for: value, baseYear: baseYear, anchorMonth: anchorMonth)
        guard let year else { return nil }
        return ResolvedDateParts(year: year, month: value.month, day: day)
    }

    private func resolvedYear(for value: DayMonth, baseYear: Int?, anchorMonth: Int?) -> Int? {
        if let baseYear, let anchorMonth {
            return value.month < anchorMonth ? baseYear + 1 : baseYear
        }
        return value.year
    }

    private func nameCase(_ value: String, locale: String) -> String {
        let localeIdentifier = locale == "en" ? "en_US" : "fr_FR"
        var result = value.localizedLowercase.capitalized(with: Locale(identifier: localeIdentifier))
            .replacingOccurrences(of: "Foret", with: "Forêt")
            .replacingOccurrences(of: "S.c.o.r.e.", with: "S.C.O.R.E.")
            .replacingOccurrences(of: "C.a.m.p.", with: "C.A.M.P.")
            .replacingOccurrences(of: "Xp", with: "XP")
        if locale == "en" {
            result = result.replacingOccurrences(of: " Update", with: "")
        }
        if locale == "de" {
            result = result
                .replacingOccurrences(of: "-Update", with: "")
                .replacingOccurrences(of: " Update", with: "")
                .replacingOccurrences(of: "Leichte-Wasser", with: "Leichte Wasser")
        }
        return result
    }

    private func editorialTitle(_ value: String, locale: String) -> String {
        if locale == "en" {
            return editorialEnglishTitle(value)
        }
        if locale == "de" {
            return editorialGermanTitle(value)
        }
        return editorialFrenchTitle(value)
    }

    private func editorialGermanTitle(_ value: String) -> String {
        var title = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let replacements = [
            ("MARZ", "März"),
            ("MARz", "März"),
            ("MURMRGHS", "MURMRGHS"),
            ("DOPPELIER", "DOPPELTER"),
            ("EVENTSR", "EVENTS"),
            ("HIND REICHLICH KRONKORKEN", "UND REICHLICH KRONKORKEN"),
            ("GRUSELIGE-VERBRANNTE-", "GRUSELIGE-VERBRANNTE"),
            ("MUTIERTE ÖFFENTLICHE EVENTS EVENTS", "MUTIERTE ÖFFENTLICHE EVENTS"),
            ("EVENT: DAS GROßE BLÜHEN EVENT- DAS GROßE BLÜHEN", "EVENT: DAS GROßE BLÜHEN"),
            ("DOPPELTER S.C.O.R.E., DOPPELMUTATIONEN DOPPELTER S.C.O.R.E., DOPPELMUTATIONEN UND REICHLICH KRONKORKEN", "DOPPELTER S.C.O.R.E., DOPPELMUTATIONEN UND REICHLICH KRONKORKEN"),
            ("LEGENDARE", "LEGENDÄRE"),
            ("ANGEL-C.A.M.P.-WETT ANGEL-C.A.M.P.-WETT SCHEINE-SEGEN UND BEWERB", "ANGEL-C.A.M.P.-WETTBEWERB"),
        ]

        for (search, replacement) in replacements {
            title = title.replacingOccurrences(of: search, with: replacement)
        }

        title = title
            .replacingOccurrences(of: "EVENT: DAS GROßE BLÜHEN EVENT- DAS GROßE BLÜHEN", with: "EVENT: DAS GROßE BLÜHEN")
            .replacingOccurrences(of: "GRUSELIGE-VERBRANNTE EVENT", with: "GRUSELIGE-VERBRANNTE-EVENT")
            .replacingOccurrences(of: "DOPPELTER S.C.O.R.E., DOPPELMUTATIONEN SCHATZSUCHER UND LEGENDÄRE ANGEBOTE", with: "DOPPELTER S.C.O.R.E., DOPPELMUTATIONEN UND SCHATZSUCHER UND LEGENDÄRE ANGEBOTE")

        return deduplicateRepeatedPhrase(deduplicateTitleSegments(title))
    }

    private func editorialFrenchTitle(_ value: String) -> String {
        var title = value
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .localizedLowercase
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let replacements = [
            ("a jour", "à jour"),
            ("zero", "zéro"),
            ("foret", "forêt"),
            ("special", "spécial"),
            ("selection", "sélection"),
            ("legendaire", "légendaire"),
            ("fievre", "fièvre"),
            ("fetes", "fêtes"),
            ("tresor", "trésor"),
            ("tresors", "trésors"),
            ("defis", "défis"),
            ("d'ete", "d'été"),
            ("brulant", "brûlant"),
            ("calcines", "calcinés"),
            ("evenement", "événement"),
            ("evenements", "événements"),
            ("au-dela", "au-delà"),
            ("capsules a gogo", "capsules à gogo"),
            ("ei", "et"),
            ("mutatons", "mutations"),
            ("mitations", "mutations"),
            ("capciles a gogo", "capsules à gogo"),
            ("capches a gogo", "capsules à gogo"),
            ("capches", "capsules"),
            ("capciles", "capsules"),
            ("murrmrgh", "Murrmrgh"),
            ("murmrgh", "Murrmrgh"),
            ("minerva", "Minerva"),
            ("rip daring", "Rip Daring"),
            ("explosive", "eXPlosive"),
            ("des marchands des marchands.", "des marchands"),
            ("des marchands des marchands", "des marchands"),
            ("et des bonbons ou un-sort bonbons ou un sort", "et bonbons ou un sort"),
            ("bonbons ou un-sort", "bonbons ou un sort"),
            ("doubles mutations et promotion légendaire des marchands des marchands", "doubles mutations et promotion légendaire des marchands"),
            ("double xp, doubles mutations et mutations et", "double xp, doubles mutations et"),
            ("week-end double s.c.o.r.e. week-end double s.c.o.r.e.", "Week-end double S.C.O.R.E."),
            ("double score", "Double S.C.O.R.E."),
            ("dquble s.c.o.r.e.", "Double S.C.O.R.E."),
            ("meilleurs s.c.o.r.e.", "Meilleurs S.C.O.R.E."),
            ("event de fastnacht", "Événement de Fastnacht"),
            ("evenement de fastnacht", "Événement de Fastnacht"),
            ("equinoxe de l'homme-phalene", "Équinoxe de l'homme-phalène"),
            ("amour brolant amour brulant", "amour brûlant"),
            ("double s.c.o.r.e., doubles mutations double s.c.q.r.e., doubles mutations et choix spécial de Murrmrgh", "Double S.C.O.R.E., doubles mutations et choix spécial de Murrmrgh"),
            ("double s.c.o.r.e., doubles mutations, capsules à gogo mutations et capsules à gogo", "Double S.C.O.R.E., doubles mutations et capsules à gogo"),
            ("double s.c.o.r.e., doubles mutations et capsules à gogo mutations et capsules à gogo", "Double S.C.O.R.E., doubles mutations et capsules à gogo"),
        ]

        for (search, replacement) in replacements {
            title = title.replacingOccurrences(of: search, with: replacement)
        }

        title = title
            .replacingOccurrences(of: "s.c.o.r.e.", with: "S.C.O.R.E.")
            .replacingOccurrences(of: "xp", with: "XP")
            .replacingOccurrences(of: "fallout day", with: "Fallout Day")
            .replacingOccurrences(of: "fallout 76", with: "Fallout 76")
            .replacingOccurrences(of: "c.a.m.p.", with: "C.A.M.P.")
            .replacingOccurrences(of: "événement calcinés", with: "Événement Calcinés")
            .replacingOccurrences(of: "événement les envahisseurs", with: "Événement Les Envahisseurs")

        if let first = title.first {
            title = first.uppercased() + title.dropFirst()
        }

        return deduplicateTitleSegments(title)
    }

    private func editorialEnglishTitle(_ value: String) -> String {
        var title = value
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .localizedLowercase
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let replacements = [
            ("double score", "double S.C.O.R.E."),
            ("s.c.o.r.e.", "S.C.O.R.E."),
            ("xp", "XP"),
            ("double xp", "Double XP"),
            ("murrmrgh", "Murrmrgh"),
            ("murmrgh", "Murrmrgh"),
            ("minerva", "Minerva"),
            ("rip daring", "Rip Daring"),
            ("fallout day", "Fallout Day"),
            ("public events", "Public Events"),
            ("double mutations", "Double Mutations"),
            ("treasure hunter", "Treasure Hunter"),
            ("caps•a-plenty", "Caps-A-Plenty"),
            ("caps-a-plenty and double caps-a-plenty and double mutations weekend", "Caps-A-Plenty And Double Mutations Weekend"),
            ("invaders from invaders from caps-a-plenty beyond event", "Invaders From Beyond Event"),
            ("double s.c.o.r.e., double mutations, double s.c.o.r.e. double mutations.", "Double S.C.O.R.E., Double Mutations,"),
            ("double s.c.o.r.e., double mutations, double s.c.o.r.e. double mutations. treasure hunter, and legendary sale", "Double S.C.O.R.E., Double Mutations, Treasure Hunter, And Legendary Sale"),
        ]

        for (search, replacement) in replacements {
            title = title.replacingOccurrences(of: search, with: replacement)
        }

        title = title
            .split(separator: " ")
            .map { word -> String in
                if word == "S.C.O.R.E." || word == "XP" || word == "C.A.M.P." || word == "Fallout" || word == "Day" || word == "Murrmrgh" || word == "Minerva" || word == "Rip" || word == "Daring" {
                    return String(word)
                }
                return String(word).capitalized(with: Locale(identifier: "en_US"))
            }
            .joined(separator: " ")

        title = title
            .replacingOccurrences(of: "S.c.o.r.e.", with: "S.C.O.R.E.")
            .replacingOccurrences(of: "S.c.o.r.e.,", with: "S.C.O.R.E.,")
            .replacingOccurrences(of: "Double Xp", with: "Double XP")
            .replacingOccurrences(of: "Caps-A-Plenty And Double Caps-A-Plenty And Double Mutations Weekend", with: "Caps-A-Plenty And Double Mutations Weekend")
            .replacingOccurrences(of: "Mutated Public", with: "Mutated Public Events")
            .replacingOccurrences(of: "Mutated Public Events Events", with: "Mutated Public Events")
            .replacingOccurrences(of: "Gone Fission Update", with: "Gone Fission")
            .replacingOccurrences(of: "Double S.C.O.R.E., Double Mutations, Double S.C.O.R.E. Double Mutations. Treasure Hunter, And Legendary Sale", with: "Double S.C.O.R.E., Double Mutations, Treasure Hunter, And Legendary Sale")

        return deduplicateRepeatedPhrase(deduplicateTitleSegments(title))
    }

    private func deduplicateTitleSegments(_ value: String) -> String {
        let normalizedValue = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        if normalizedValue.contains(",") {
            let segments = normalizedValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            var kept: [String] = []
            var seen: Set<String> = []

            for segment in segments {
                let key = normalize(segment)
                if seen.insert(key).inserted {
                    kept.append(segment)
                }
            }

            return kept.joined(separator: ", ")
        }

        return normalizedValue
    }

    private func deduplicateRepeatedPhrase(_ value: String) -> String {
        let normalizedValue = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let midpoint = normalizedValue.count / 2
        guard midpoint > 0 else { return normalizedValue }

        let index = normalizedValue.index(normalizedValue.startIndex, offsetBy: midpoint)
        let first = normalizedValue[..<index].trimmingCharacters(in: .whitespacesAndNewlines)
        let second = normalizedValue[index...].trimmingCharacters(in: .whitespacesAndNewlines)

        if !first.isEmpty && normalize(String(first)) == normalize(String(second)) {
            return String(first)
        }

        return normalizedValue
    }

    private func shouldIgnoreEventTitle(_ value: String) -> Bool {
        let normalized = normalize(value)
        let ignoredFragments = [
            "bethesda",
            "community calendar",
            "calendrier de la communaute",
            "calendrier de la communauté",
            "copyright",
        ]

        if ignoredFragments.contains(where: { normalized.contains($0) }) {
            return true
        }

        if normalized == "weekend" {
            return true
        }

        if normalized == "mini-saison:" || normalized == "mini season:" {
            return true
        }

        if normalized.hasPrefix("et ") || normalized.hasPrefix("de ") || normalized.hasPrefix("and ") {
            return true
        }

        if normalized.hasSuffix(" and") {
            return true
        }

        if normalized.hasSuffix(":") && normalized.count < 24 {
            return true
        }

        return normalized.count < 4
    }

    private func isWeakCalendarEventTitle(_ value: String) -> Bool {
        let normalized = normalize(value)
        return normalized.hasPrefix("et ")
            || normalized.hasPrefix("de ")
            || normalized.hasPrefix("and ")
            || normalized.hasSuffix(" and")
            || normalized.hasSuffix(":")
            || normalized.hasSuffix(" double")
            || normalized.count < 24
    }

    private func pruneWeakEvents(_ events: [WebCalendarEvent]) -> [WebCalendarEvent] {
        var kept: [WebCalendarEvent] = []

        outer: for event in events {
            let normalized = normalize(event.title)

            for existing in kept {
                let existingNormalized = normalize(existing.title)
                let sameStart = existing.dateStart == event.dateStart
                let sameWindow = existing.dateStart == event.dateStart && existing.dateEnd == event.dateEnd

                if sameWindow && existingNormalized.contains(normalized) && existingNormalized.count > normalized.count {
                    continue outer
                }

                if sameStart && existingNormalized.contains(normalized) && normalized.count < 24 {
                    continue outer
                }
            }

            kept.append(event)
        }

        return kept
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ResolvedDateParts {
    var year: Int
    let month: Int
    let day: Int

    var iso8601: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}
