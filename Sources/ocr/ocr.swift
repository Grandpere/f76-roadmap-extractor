import CalendarOCR
import Foundation

@main
struct ocr {
    static func main() {
        do {
            let config = try CLIConfig(arguments: CommandLine.arguments)
            let extractor = CalendarExtractor(baseYear: config.baseYear)
            let webExporter = WebCalendarExporter()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let data: Data
            if let debugDirectoryURL = config.debugDirectoryURL {
                let debugDump = try extractor.extractWithDebug(from: config.imageURL, localeIdentifier: config.locale)
                let webExport = webExporter.export(result: debugDump.result, fallbackBaseYear: config.baseYear)
                try DebugWriter.write(debugDump: debugDump, webExport: webExport, to: debugDirectoryURL, encoder: encoder)
                data = try encoder.encode(debugDump.result)
            } else {
                let result = try extractor.extract(from: config.imageURL, localeIdentifier: config.locale)
                if let webJSONURL = config.webJSONURL {
                    let webExport = webExporter.export(result: result, fallbackBaseYear: config.baseYear)
                    try encoder.encode(webExport).write(to: webJSONURL)
                }
                data = try encoder.encode(result)
            }

            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            FileHandle.standardError.write(Data("Erreur: \(message)\n".utf8))
            Foundation.exit(1)
        }
    }
}

private struct CLIConfig {
    let imageURL: URL
    let locale: String
    let baseYear: Int?
    let debugDirectoryURL: URL?
    let webJSONURL: URL?

    init(arguments: [String]) throws {
        var imagePath: String?
        var locale = "fr-FR"
        var baseYear: Int?
        var debugDirectoryPath: String?
        var webJSONPath: String?

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--image":
                index += 1
                imagePath = try Self.value(at: index, in: arguments, for: argument)
            case "--locale":
                index += 1
                locale = try Self.value(at: index, in: arguments, for: argument)
            case "--base-year":
                index += 1
                let raw = try Self.value(at: index, in: arguments, for: argument)
                guard let year = Int(raw) else {
                    throw CLIError.invalidYear(raw)
                }
                baseYear = year
            case "--debug-dir":
                index += 1
                debugDirectoryPath = try Self.value(at: index, in: arguments, for: argument)
            case "--web-json":
                index += 1
                webJSONPath = try Self.value(at: index, in: arguments, for: argument)
            case "--help", "-h":
                throw CLIError.help
            default:
                if imagePath == nil {
                    imagePath = argument
                } else {
                    throw CLIError.unexpectedArgument(argument)
                }
            }
            index += 1
        }

        guard let imagePath else {
            throw CLIError.help
        }

        self.imageURL = URL(fileURLWithPath: imagePath)
        self.locale = locale
        self.baseYear = baseYear
        self.debugDirectoryURL = debugDirectoryPath.map { URL(fileURLWithPath: $0) }
        self.webJSONURL = webJSONPath.map { URL(fileURLWithPath: $0) }
    }

    private static func value(at index: Int, in arguments: [String], for option: String) throws -> String {
        guard index < arguments.count else {
            throw CLIError.missingValue(option)
        }
        return arguments[index]
    }
}

private enum CLIError: LocalizedError {
    case missingValue(String)
    case invalidYear(String)
    case unexpectedArgument(String)
    case help

    var errorDescription: String? {
        switch self {
        case .missingValue(let option):
            return "Valeur manquante pour \(option)"
        case .invalidYear(let value):
            return "Année invalide: \(value)"
        case .unexpectedArgument(let value):
            return "Argument inattendu: \(value)"
        case .help:
            return """
            Usage:
              ocr --image /chemin/vers/image.jpg [--locale fr-FR] [--base-year 2025] [--web-json /chemin/sortie.json]

            Options:
              --image       Chemin de l'image calendrier
              --locale      Langue OCR/parseur, par défaut fr-FR
              --base-year   Année de départ de saison pour résoudre les bascules d'année
              --debug-dir   Dossier de sortie pour exporter le debug OCR/parseur
              --web-json    Fichier JSON normalisé pour usage web/calendrier
            """
        }
    }
}

private enum DebugWriter {
    static func write(debugDump: ExtractionDebugDump, webExport: WebCalendarExport, to directoryURL: URL, encoder: JSONEncoder) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)

        let resultData = try encoder.encode(debugDump.result)
        try resultData.write(to: directoryURL.appendingPathComponent("result.json"))

        let webData = try encoder.encode(webExport)
        try webData.write(to: directoryURL.appendingPathComponent("calendar-web.json"))

        let debugData = try encoder.encode(debugDump)
        try debugData.write(to: directoryURL.appendingPathComponent("debug.json"))

        let rawLines = debugDump.result.rawLines.joined(separator: "\n")
        try Data(rawLines.utf8).write(to: directoryURL.appendingPathComponent("raw-lines.txt"))
    }
}
