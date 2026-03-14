import AppKit
import CalendarOCR
import Foundation

@main
struct OCRSmokeTests {
    static func main() {
        var failures: [String] = []

        run("parser extracts ranged and cross-year events", failures: &failures) {
            let parser = FrenchCalendarParser(inferredBaseYear: 2025)
            let lines = [
                "Septembre",
                "3 SEPTEMBRE",
                "MISE A JOUR BORNE ZERO",
                "5 SEPTEMBRE - 9 SEPTEMBRE",
                "DOUBLES MUTATIONS ET",
                "PROMOTION LEGENDAIRE DES MARCHANDS",
                "Décembre",
                "17 DÉCEMBRE - 2 JANVIER",
                "ÉVÉNEMENT CALCINÉS DES FÊTES"
            ]

            let events = parser.parse(lines: lines)
            try expect(events.count == 3, "Expected 3 events, got \(events.count)")
            try expect(events[0].date.start.isoLikeString == "2025-09-03", "Unexpected first start date: \(events[0].date.start.isoLikeString)")
            try expect(events[1].date.end?.isoLikeString == "2025-09-09", "Unexpected second end date")
            try expect(events[2].date.end?.isoLikeString == "2026-01-02", "Unexpected cross-year end date")
        }

        run("parser infers next month when end day wraps without explicit month", failures: &failures) {
            let parser = FrenchCalendarParser(inferredBaseYear: 2025)
            let events = parser.parse(lines: [
                "Juin",
                "23 JUIN - 7",
                "ÉVÉNEMENT TEST"
            ])
            let range = events.first?.date

            try expect(range?.start.isoLikeString == "2026-06-23", "Unexpected wrapped start date")
            try expect(range?.end?.isoLikeString == "2026-07-07", "Unexpected wrapped end date")
        }

        run("parser ignores header noise", failures: &failures) {
            let parser = FrenchCalendarParser(inferredBaseYear: 2025)
            let events = parser.parse(lines: [
                "Country Road",
                "Calendrier de la communauté",
                "Novembre",
                "7 NOVEMBRE - 11 NOVEMBRE",
                "WEEK-END DOUBLE S.C.O.R.E. ET CHASSEUR DE TRESORS"
            ])

            try expect(events.count == 1, "Expected 1 event, got \(events.count)")
            try expect(events[0].section == "Novembre", "Unexpected section: \(String(describing: events[0].section))")
        }

        run("english parser extracts ranged events", failures: &failures) {
            let parser = EnglishCalendarParser(inferredBaseYear: 2025)
            let events = parser.parse(lines: [
                "September",
                "3 September",
                "MILEPOST ZERO UPDATE",
                "5 September - 9 September",
                "DOUBLE MUTATIONS AND LEGENDARY VENDOR SALE",
                "December",
                "17 December - 2 January",
                "HOLIDAY SCORCHED"
            ])

            try expect(events.count == 3, "Expected 3 English events, got \(events.count)")
            try expect(events[0].date.start.isoLikeString == "2025-09-03", "Unexpected English first start date")
            try expect(events[1].date.end?.isoLikeString == "2025-09-09", "Unexpected English second end date")
            try expect(events[2].date.end?.isoLikeString == "2026-01-02", "Unexpected English cross-year end date")
        }

        run("german parser extracts ranged events", failures: &failures) {
            let parser = GermanCalendarParser(inferredBaseYear: 2026)
            let events = parser.parse(lines: [
                "März",
                "3. März",
                "UPDATE: DAS HINTERLAND",
                "3. BIS 10. MÄRZ",
                "BIGFOOTS PARTY",
                "Juni",
                "23. JUNI BIS 7. JULI",
                "EVENT: FLEISCHWOCHE SAMT NACHSCHLAG"
            ])

            try expect(events.count == 3, "Expected 3 German events, got \(events.count)")
            try expect(events[0].date.start.isoLikeString == "2027-03-03", "Unexpected German first start date")
            try expect(events[1].date.end?.isoLikeString == "2027-03-10", "Unexpected German second end date")
            try expect(events[2].date.end?.isoLikeString == "2027-07-07", "Unexpected German cross-month end date")
        }

        run("OCR extracts events from synthetic image", failures: &failures) {
            let imageURL = try SyntheticImageFactory.makeImage(lines: [
                "Septembre",
                "3 SEPTEMBRE",
                "MISE A JOUR BORNE ZERO",
                "5 SEPTEMBRE - 9 SEPTEMBRE",
                "DOUBLES MUTATIONS"
            ])

            let extractor = CalendarExtractor(baseYear: 2025)
            let result = try extractor.extract(from: imageURL, localeIdentifier: "fr-FR")

            try expect(result.events.count >= 2, "Expected at least 2 events, got \(result.events.count)")
            try expect(result.events.contains(where: { $0.title.localizedCaseInsensitiveContains("BORNE") }), "Missing BORNE event")
            try expect(result.events.contains(where: { $0.title.localizedCaseInsensitiveContains("MUTATIONS") }), "Missing MUTATIONS event")
        }

        run("debug dump contains OCR profile details", failures: &failures) {
            let imageURL = try SyntheticImageFactory.makeImage(lines: [
                "Septembre",
                "3 SEPTEMBRE",
                "MISE A JOUR BORNE ZERO"
            ])

            let extractor = CalendarExtractor(baseYear: 2025)
            let debugDump = try extractor.extractWithDebug(from: imageURL, localeIdentifier: "fr-FR")

            try expect(!debugDump.profiles.isEmpty, "Expected at least one profile dump")
            try expect(!debugDump.mergedLines.isEmpty, "Expected merged OCR lines")
            try expect(debugDump.result.events.contains(where: { $0.title.localizedCaseInsensitiveContains("BORNE") }), "Expected parsed event in debug result")
        }

        run("web export infers season, name and year", failures: &failures) {
            let exporter = WebCalendarExporter()
            let result = ExtractionResult(
                locale: "fr",
                source: "fixture.jpg",
                events: [
                    CalendarEvent(
                        title: "MISE A JOUR BORNE ZERO",
                        date: EventDateRange(
                            raw: "3 SEPTEMBRE",
                            start: DayMonth(day: 3, month: 9, year: nil),
                            end: nil
                        ),
                        section: "Septembre",
                        sourceLines: []
                    ),
                    CalendarEvent(
                        title: "ÉVÉNEMENT CALCINÉS DES FÊTES",
                        date: EventDateRange(
                            raw: "17 DÉCEMBRE - 2 JANVIER",
                            start: DayMonth(day: 17, month: 12, year: nil),
                            end: DayMonth(day: 2, month: 1, year: nil)
                        ),
                        section: "Décembre",
                        sourceLines: []
                    )
                ],
                rawLines: [
                    "BORNE ZÉRO ET SAISON 18 : COUNTRY ROADS",
                    "*Bethesda",
                    "© 2024 ZeniMax"
                ]
            )

            let web = exporter.export(result: result, fallbackBaseYear: nil)

            try expect(web.season == 18, "Expected season 18, got \(String(describing: web.season))")
            try expect(web.name == "Country Roads", "Expected Country Roads, got \(web.name)")
            try expect(web.events.first?.dateStart == "2024-09-03", "Unexpected first web event start")
            try expect(web.events.last?.dateEnd == "2025-01-02", "Unexpected cross-year web event end")
            try expect(web.events.first?.title == "Mise à jour borne zéro", "Unexpected editorial title: \(String(describing: web.events.first?.title))")
        }

        run("web export lets explicit base year override OCR year", failures: &failures) {
            let exporter = WebCalendarExporter()
            let result = ExtractionResult(
                locale: "fr",
                source: "fixture.jpg",
                events: [
                    CalendarEvent(
                        title: "MISE A JOUR FORET SAUVAGE",
                        date: EventDateRange(
                            raw: "3 MARS",
                            start: DayMonth(day: 3, month: 3, year: nil),
                            end: nil
                        ),
                        section: "Mars",
                        sourceLines: []
                    )
                ],
                rawLines: [
                    "FORET SAUVAGE ET SAISON 24",
                    "© 2024 ZeniMax"
                ]
            )

            let web = exporter.export(result: result, fallbackBaseYear: 2026)
            try expect(web.events.first?.dateStart == "2026-03-03", "Expected explicit base year to override OCR year")
        }

        run("web export infers name from update-and-season phrasing", failures: &failures) {
            let exporter = WebCalendarExporter()
            let result = ExtractionResult(
                locale: "fr",
                source: "fixture.jpg",
                events: [],
                rawLines: [
                    "MISE À JOUR PARTI EN FISSION ET SAISON 21",
                    "© 2025 Bethesda"
                ]
            )

            let web = exporter.export(result: result, fallbackBaseYear: nil)
            try expect(web.season == 21, "Expected season 21")
            try expect(web.name == "Parti En Fission", "Expected Parti En Fission, got \(web.name)")
        }

        run("web export keeps end date after start date on same-year cross-month ranges", failures: &failures) {
            let exporter = WebCalendarExporter()
            let result = ExtractionResult(
                locale: "fr",
                source: "fixture.jpg",
                events: [
                    CalendarEvent(
                        title: "DEUX SERVICES DE SEMAINE DE LA VIANDE",
                        date: EventDateRange(
                            raw: "29 AOÛT - 12 SEPTEMBRE",
                            start: DayMonth(day: 29, month: 8, year: 2026),
                            end: DayMonth(day: 12, month: 9, year: 2025)
                        ),
                        section: "Août",
                        sourceLines: []
                    )
                ],
                rawLines: []
            )

            let web = exporter.export(result: result, fallbackBaseYear: nil)
            try expect(web.events.first?.dateStart == "2026-08-29", "Unexpected start date normalization")
            try expect(web.events.first?.dateEnd == "2026-09-12", "Unexpected end date normalization")
        }

        run("web export cleans noisy French OCR titles", failures: &failures) {
            let exporter = WebCalendarExporter()
            let result = ExtractionResult(
                locale: "fr",
                source: "fixture.jpg",
                events: [
                    CalendarEvent(
                        title: "WEEK-END SELECTION SPECIALE DE MURMRGH ET DOUBLES MUTATONS",
                        date: EventDateRange(
                            raw: "8 FEVRIER - 12 FEVRIER",
                            start: DayMonth(day: 8, month: 2, year: nil),
                            end: DayMonth(day: 12, month: 2, year: nil)
                        ),
                        section: "Février",
                        sourceLines: []
                    ),
                    CalendarEvent(
                        title: "EVENT DE FASTNACHT",
                        date: EventDateRange(
                            raw: "17 FEVRIER - 3 MARS",
                            start: DayMonth(day: 17, month: 2, year: nil),
                            end: DayMonth(day: 3, month: 3, year: nil)
                        ),
                        section: "Février",
                        sourceLines: []
                    )
                ],
                rawLines: ["© 2025 Bethesda"]
            )

            let web = exporter.export(result: result, fallbackBaseYear: nil)
            try expect(web.events.contains(where: { $0.title == "Week-end sélection spéciale de Murrmrgh et doubles mutations" }), "Expected cleaned Murrmrgh weekend title")
            try expect(web.events.contains(where: { $0.title == "Événement de Fastnacht" }), "Expected cleaned Fastnacht title")
        }

        run("web export title-cases english OCR titles", failures: &failures) {
            let exporter = WebCalendarExporter()
            let result = ExtractionResult(
                locale: "en",
                source: "fixture.jpg",
                events: [
                    CalendarEvent(
                        title: "DOUBLE SCORE, DOUBLE MUTATIONS AND MURMRGH'S PICK",
                        date: EventDateRange(
                            raw: "19 September - 23 September",
                            start: DayMonth(day: 19, month: 9, year: nil),
                            end: DayMonth(day: 23, month: 9, year: nil)
                        ),
                        section: "September",
                        sourceLines: []
                    )
                ],
                rawLines: [
                    "SEASON 18: COUNTRY ROADS",
                    "© 2024 Bethesda"
                ]
            )

            let web = exporter.export(result: result, fallbackBaseYear: nil)
            try expect(web.name == "Country Roads", "Expected English season name, got \(web.name)")
            try expect(web.events.first?.title == "Double S.C.O.R.E., Double Mutations And Murrmrgh's Pick", "Expected cleaned English title, got \(String(describing: web.events.first?.title))")
        }

        run("web export drops weak english fragments", failures: &failures) {
            let exporter = WebCalendarExporter()
            let result = ExtractionResult(
                locale: "en",
                source: "fixture.jpg",
                events: [
                    CalendarEvent(
                        title: "AND MURRMRGH'S SPECIAL PICK",
                        date: EventDateRange(
                            raw: "19 MARCH - 23 MARCH",
                            start: DayMonth(day: 19, month: 3, year: nil),
                            end: DayMonth(day: 23, month: 3, year: nil)
                        ),
                        section: "March",
                        sourceLines: []
                    ),
                    CalendarEvent(
                        title: "MUTATED PUBLIC",
                        date: EventDateRange(
                            raw: "7 APRIL - 14 APRIL",
                            start: DayMonth(day: 7, month: 4, year: nil),
                            end: DayMonth(day: 14, month: 4, year: nil)
                        ),
                        section: "April",
                        sourceLines: []
                    ),
                    CalendarEvent(
                        title: "HOLIDAY SCORCHED EVENT HOLIDAY SCORCHED EVENT",
                        date: EventDateRange(
                            raw: "19 DECEMBER - 2 JANUARY",
                            start: DayMonth(day: 19, month: 12, year: nil),
                            end: DayMonth(day: 2, month: 1, year: nil)
                        ),
                        section: "December",
                        sourceLines: []
                    ),
                    CalendarEvent(
                        title: "CAPS-A-PLENTY AND",
                        date: EventDateRange(
                            raw: "12 MARCH - 16 MARCH",
                            start: DayMonth(day: 12, month: 3, year: nil),
                            end: DayMonth(day: 16, month: 3, year: nil)
                        ),
                        section: "March",
                        sourceLines: []
                    ),
                    CalendarEvent(
                        title: "DOUBLE SCORE, DOUBLE MUTATIONS, DOUBLE SCORE DOUBLE MUTATIONS. TREASURE HUNTER, AND LEGENDARY SALE",
                        date: EventDateRange(
                            raw: "18 JUNE - 22 JUNE",
                            start: DayMonth(day: 18, month: 6, year: nil),
                            end: DayMonth(day: 22, month: 6, year: nil)
                        ),
                        section: "June",
                        sourceLines: []
                    )
                ],
                rawLines: ["GONE FISSION UPDATE AND SEASON 21", "© 2024 Bethesda"]
            )

            let web = exporter.export(result: result, fallbackBaseYear: nil)
            try expect(!web.events.contains(where: { $0.title == "And Murrmrgh's Special Pick" }), "Unexpected weak english fragment")
            try expect(!web.events.contains(where: { $0.title == "Caps-A-Plenty And" }), "Unexpected trailing conjunction fragment")
            try expect(web.events.contains(where: { $0.title == "Mutated Public Events" }), "Expected expanded Mutated Public Events title")
            try expect(web.events.contains(where: { $0.title == "Holiday Scorched Event" }), "Expected deduplicated Holiday Scorched title")
            try expect(web.events.contains(where: { $0.title == "Double S.C.O.R.E., Double Mutations, Treasure Hunter, And Legendary Sale" }), "Expected deduplicated legendary sale title")
            try expect(web.name == "Gone Fission", "Expected cleaned English season name, got \(web.name)")
        }

        run("web export cleans noisy German titles", failures: &failures) {
            let exporter = WebCalendarExporter()
            let result = ExtractionResult(
                locale: "de",
                source: "fixture.jpg",
                events: [
                    CalendarEvent(
                        title: "MUTIERTE ÖFFENTLICHE EVENTS EVENTS",
                        date: EventDateRange(
                            raw: "9. BIS 16. JUNI",
                            start: DayMonth(day: 9, month: 6, year: nil),
                            end: DayMonth(day: 16, month: 6, year: nil)
                        ),
                        section: "Juni",
                        sourceLines: []
                    ),
                    CalendarEvent(
                        title: "MINI-SAISON:",
                        date: EventDateRange(
                            raw: "21. APRIL BIS 5. MAI",
                            start: DayMonth(day: 21, month: 4, year: nil),
                            end: DayMonth(day: 5, month: 5, year: nil)
                        ),
                        section: "April",
                        sourceLines: []
                    ),
                    CalendarEvent(
                        title: "DOPPELTER S.C.O.R.E., LEGENDARE ANGEBOTE UND DOPPELMUTATIONEN",
                        date: EventDateRange(
                            raw: "19. BIS 23. JUNI",
                            start: DayMonth(day: 19, month: 6, year: nil),
                            end: DayMonth(day: 23, month: 6, year: nil)
                        ),
                        section: "Juni",
                        sourceLines: []
                    ),
                    CalendarEvent(
                        title: "ANGEL-C.A.M.P.-WETT ANGEL-C.A.M.P.-WETT SCHEINE-SEGEN UND BEWERB",
                        date: EventDateRange(
                            raw: "1. JULI BIS 22. JULI",
                            start: DayMonth(day: 1, month: 7, year: nil),
                            end: DayMonth(day: 22, month: 7, year: nil)
                        ),
                        section: "Juli",
                        sourceLines: []
                    ),
                    CalendarEvent(
                        title: "EVENT: DAS GROßE BLÜHEN EVENT- DAS GROßE BLÜHEN",
                        date: EventDateRange(
                            raw: "10. BIS 24. MÄRZ",
                            start: DayMonth(day: 10, month: 3, year: nil),
                            end: DayMonth(day: 24, month: 3, year: nil)
                        ),
                        section: "März",
                        sourceLines: []
                    ),
                    CalendarEvent(
                        title: "GRUSELIGE-VERBRANNTE EVENT",
                        date: EventDateRange(
                            raw: "28. APRIL BIS 12. MAI",
                            start: DayMonth(day: 28, month: 4, year: nil),
                            end: DayMonth(day: 12, month: 5, year: nil)
                        ),
                        section: "April",
                        sourceLines: []
                    ),
                    CalendarEvent(
                        title: "DOPPELTER S.C.O.R.E., DOPPELMUTATIONEN SCHATZSUCHER UND LEGENDÄRE ANGEBOTE",
                        date: EventDateRange(
                            raw: "18. BIS 22. JUNI",
                            start: DayMonth(day: 18, month: 6, year: nil),
                            end: DayMonth(day: 22, month: 6, year: nil)
                        ),
                        section: "Juni",
                        sourceLines: []
                    )
                ],
                rawLines: ["LEICHTE-WASSER-UPDATE UND SAISON 21", "© 2024 Bethesda"]
            )

            let web = exporter.export(result: result, fallbackBaseYear: 2026)
            try expect(web.name == "Leichte Wasser", "Expected cleaned German season name, got \(web.name)")
            try expect(web.events.contains(where: { $0.title == "MUTIERTE ÖFFENTLICHE EVENTS" }), "Expected deduplicated German events title")
            try expect(!web.events.contains(where: { $0.title == "MINI-SAISON:" }), "Unexpected weak German fragment")
            try expect(web.events.contains(where: { $0.title == "DOPPELTER S.C.O.R.E., LEGENDÄRE ANGEBOTE UND DOPPELMUTATIONEN" }), "Expected cleaned German legendary title")
            try expect(web.events.contains(where: { $0.title == "ANGEL-C.A.M.P.-WETTBEWERB" }), "Expected cleaned German camp contest title")
            try expect(web.events.contains(where: { $0.title == "EVENT: DAS GROßE BLÜHEN" }), "Expected cleaned German bloom event title")
            try expect(web.events.contains(where: { $0.title == "GRUSELIGE-VERBRANNTE-EVENT" }), "Expected cleaned German scorched title")
            try expect(web.events.contains(where: { $0.title == "DOPPELTER S.C.O.R.E., DOPPELMUTATIONEN UND SCHATZSUCHER UND LEGENDÄRE ANGEBOTE" }), "Expected cleaned German treasure hunter title")
        }

        run("real Fallout FR image keeps key events", failures: &failures) {
            let fixture = URL(fileURLWithPath: "/Users/lorenzomarozzo/PhpstormProjects/f76/data/roadmap_calendar_examples/fr/FO76_Season18_CommunityCalendar-FR-01.jpg")
            guard FileManager.default.fileExists(atPath: fixture.path) else {
                print("SKIP: real Fallout FR image keeps key events")
                return
            }

            let extractor = CalendarExtractor(baseYear: 2025)
            let result = try extractor.extract(from: fixture, localeIdentifier: "fr-FR")
            let web = WebCalendarExporter().export(result: result, fallbackBaseYear: nil)

            try expect(result.events.contains(where: { $0.title.localizedCaseInsensitiveContains("FALLOUT DAY") }), "Expected Fallout Day event")
            try expect(result.events.contains(where: { $0.date.raw.contains("5 SEPTEMBRE - 9 SEPTEMBRE") }), "Expected early September range")
            try expect(result.events.contains(where: { $0.date.raw.contains("5 NOVEMBRE - 12 NOVEMBRE") }), "Expected repaired early November range")
            try expect(result.events.contains(where: { $0.date.raw.contains("21 NOVEMBRE - 25 NOVEMBRE") }), "Expected repaired late-November range")
            try expect(result.events.contains(where: { $0.title.localizedCaseInsensitiveContains("JOYEUX ANNIVERSAIRE") }), "Expected Fallout birthday event")
            try expect(result.events.contains(where: { $0.date.raw.contains("17 DÉCEMBRE - 2 JANVIER") || $0.date.raw.contains("17 DECEMBRE - 2 JANVIER") }), "Expected cross-year December event")
            try expect(result.events.contains(where: { $0.title.localizedCaseInsensitiveContains("CHASSEUR DE TRESOR") }), "Expected December treasure hunter event")
            try expect(result.events.contains(where: { $0.date.raw.contains("28 NOVEMBRE - 2 DÉCEMBRE") || $0.date.raw.contains("28 NOVEMBRE - 2 DECEMBRE") }), "Expected repaired late-November date range")
            try expect(result.events.filter({ $0.date.raw.contains("31 OCTOBRE - 4 NOVEMBRE") }).count == 1, "Expected October/November duplicate collapse")
            try expect(!result.events.contains(where: { $0.section == "Novembre" && $0.date.raw == "5 DÉCEMBRE" }), "Unexpected stray December single-day event in November section")
            try expect(web.season == 18, "Expected web season 18")
            try expect(web.name == "Country Roads", "Expected web name Country Roads")
            try expect(web.events.contains(where: { $0.dateStart == "2024-11-05" && $0.dateEnd == "2024-11-12" }), "Expected repaired web November range")
            try expect(!web.events.contains(where: { $0.dateStart == "2025-09-03" }), "Expected copyright year inference for season 18")
            try expect(web.events.contains(where: { $0.title == "Choix spécial de Murrmrgh" }), "Expected cleaned Murrmrgh title")
            try expect(web.events.contains(where: { $0.title == "Joyeux anniversaire, Fallout 76 !" }), "Expected cleaned birthday title")
        }

        run("season 24 web export drops footer noise and weak fragments", failures: &failures) {
            let fixture = URL(fileURLWithPath: "/Users/lorenzomarozzo/PhpstormProjects/f76/data/roadmap_calendar_examples/fr/FO76_Season24_CommunityCalendar-FR-01.jpg")
            guard FileManager.default.fileExists(atPath: fixture.path) else {
                print("SKIP: season 24 web export drops footer noise and weak fragments")
                return
            }

            let extractor = CalendarExtractor(baseYear: 2026)
            let result = try extractor.extract(from: fixture, localeIdentifier: "fr-FR")
            let web = WebCalendarExporter().export(result: result, fallbackBaseYear: 2026)

            try expect(web.season == 24, "Expected web season 24")
            try expect(web.name == "Forêt Sauvage", "Expected cleaned season 24 name, got \(web.name)")
            try expect(web.events.contains(where: { $0.dateStart == "2026-03-03" }), "Expected season 24 spring anchor date")
            try expect(web.events.contains(where: { $0.dateStart == "2026-06-23" && $0.dateEnd == "2026-07-07" }), "Expected June/July range")
            try expect(web.events.contains(where: {
                $0.dateStart == "2026-06-18" &&
                $0.dateEnd == "2026-06-22" &&
                $0.title == "Double S.C.O.R.E., doubles mutations, chasseur de trésors et promotion légendaire"
            }), "Expected merged June promotion range")
            try expect(!web.events.contains(where: {
                $0.dateStart == "2026-06-18" &&
                $0.dateEnd == "2026-06-18" &&
                $0.title == "Double S.C.O.R.E., doubles mutations, chasseur de trésors et promotion légendaire"
            }), "Unexpected single-day June promotion event")
            try expect(!web.events.contains(where: { $0.title.localizedCaseInsensitiveContains("bethesda") }), "Unexpected footer/Bethesda event")
            try expect(!web.events.contains(where: { $0.title == "Et promotion légendaire" }), "Unexpected weak partial title")
        }

        run("real Fallout EN image exports key season 18 events", failures: &failures) {
            let fixture = URL(fileURLWithPath: "/Users/lorenzomarozzo/PhpstormProjects/f76/data/roadmap_calendar_examples/en/FO76_Season18_CommunityCalendar-EN-01.jpg")
            guard FileManager.default.fileExists(atPath: fixture.path) else {
                print("SKIP: real Fallout EN image exports key season 18 events")
                return
            }

            let extractor = CalendarExtractor(baseYear: 2024)
            let result = try extractor.extract(from: fixture, localeIdentifier: "en-US")
            let web = WebCalendarExporter().export(result: result, fallbackBaseYear: 2024)

            try expect(web.season == 18, "Expected EN web season 18")
            try expect(web.name == "Country Roads", "Expected EN web name Country Roads")
            try expect(web.events.contains(where: { $0.dateStart == "2024-09-05" && $0.dateEnd == "2024-09-09" && $0.title == "Double Mutations And Legendary Vendor Sale" }), "Expected EN September vendor event")
            try expect(web.events.contains(where: { $0.dateStart == "2024-11-12" && $0.dateEnd == "2024-11-26" && $0.title == "Invaders From Beyond Event" }), "Expected EN Invaders event")
            try expect(web.events.contains(where: { $0.dateStart == "2024-12-17" && $0.dateEnd == "2025-01-02" && $0.title == "Holiday Scorched Event" }), "Expected EN Holiday Scorched event")
            try expect(!web.events.contains(where: { $0.title == "Weekend" }), "Unexpected EN stray Weekend event")
        }

        run("real Fallout DE image exports key season 24 events", failures: &failures) {
            let fixture = URL(fileURLWithPath: "/Users/lorenzomarozzo/PhpstormProjects/f76/data/roadmap_calendar_examples/de/FO76_Season24_CommunityCalendar-DE-01.jpg")
            guard FileManager.default.fileExists(atPath: fixture.path) else {
                print("SKIP: real Fallout DE image exports key season 24 events")
                return
            }

            let extractor = CalendarExtractor(baseYear: 2026)
            let result = try extractor.extract(from: fixture, localeIdentifier: "de-DE")
            let web = WebCalendarExporter().export(result: result, fallbackBaseYear: 2026)

            try expect(web.season == 24, "Expected DE season 24")
            try expect(web.name == "Hinterland", "Expected DE season name Hinterland, got \(web.name)")
            try expect(web.events.contains(where: { $0.dateStart == "2026-03-03" && $0.dateEnd == "2026-03-03" && $0.title == "UPDATE: DAS HINTERLAND" }), "Expected DE update event")
            try expect(web.events.contains(where: { $0.dateStart == "2026-03-10" && $0.dateEnd == "2026-03-24" && $0.title == "EVENT: ANGREIFER AUS DEM ALL" }), "Expected DE invaders event")
            try expect(web.events.contains(where: { $0.dateStart == "2026-06-23" && $0.dateEnd == "2026-07-07" && $0.title == "EVENT: FLEISCHWOCHE SAMT NACHSCHLAG" }), "Expected DE meat week event")
        }

        if failures.isEmpty {
            print("All smoke tests passed.")
            Foundation.exit(0)
        }

        for failure in failures {
            FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8))
        }
        Foundation.exit(1)
    }

    private static func run(_ name: String, failures: inout [String], block: () throws -> Void) {
        do {
            try block()
            print("PASS: \(name)")
        } catch {
            failures.append("\(name) -> \(error)")
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) throws {
        if !condition() {
            throw ExpectationError(description: message())
        }
    }
}

private struct ExpectationError: Error, CustomStringConvertible {
    let description: String
}

private enum SyntheticImageFactory {
    static func makeImage(lines: [String]) throws -> URL {
        let width: CGFloat = 1800
        let height: CGFloat = 900
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width),
            pixelsHigh: Int(height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw SyntheticImageError.renderFailed
        }

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw SyntheticImageError.renderFailed
        }
        NSGraphicsContext.current = context
        defer {
            NSGraphicsContext.restoreGraphicsState()
        }

        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 54, weight: .bold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph,
        ]

        var y = height - 120
        for line in lines {
            let rect = NSRect(x: 80, y: y, width: width - 160, height: 80)
            NSString(string: line).draw(in: rect, withAttributes: attributes)
            y -= 110
        }

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SyntheticImageError.renderFailed
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try png.write(to: url)
        return url
    }
}

private enum SyntheticImageError: Error {
    case renderFailed
}
