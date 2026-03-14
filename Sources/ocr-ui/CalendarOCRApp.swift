import AppKit
import CalendarOCR
import SwiftUI
import UniformTypeIdentifiers

@main
struct CalendarOCRApp: App {
    @NSApplicationDelegateAdaptor(CalendarOCRAppDelegate.self) private var appDelegate
    @StateObject private var model = CalendarOCRViewModel()

    var body: some Scene {
        WindowGroup("F76 Roadmap Extractor") {
            CalendarOCRRootView(model: model)
                .frame(minWidth: 980, minHeight: 720)
        }
        .windowStyle(.titleBar)
    }
}

final class CalendarOCRAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.windows.forEach { $0.title = "F76 Roadmap Extractor" }
        if let iconURL = Bundle.module.url(forResource: "f76logo", withExtension: "png"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor
final class CalendarOCRViewModel: ObservableObject {
    private enum DefaultsKey {
        static let locale = "ui.selectedLocale"
        static let baseYear = "ui.baseYear"
        static let recentImages = "ui.recentImages"
    }

    enum AppLocale: String, CaseIterable, Identifiable {
        case fr = "fr-FR"
        case en = "en-US"
        case de = "de-DE"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .fr: return "FR"
            case .en: return "EN"
            case .de: return "DE"
            }
        }
    }

    @Published var selectedImageURL: URL?
    @Published var previewImage: NSImage?
    @Published var selectedLocale: AppLocale
    @Published var baseYearInput: String
    @Published var isRunning = false
    @Published var statusMessage = "Choisis une image pour commencer."
    @Published var extractionResult: ExtractionResult?
    @Published var debugDump: ExtractionDebugDump?
    @Published var webExport: WebCalendarExport?
    @Published var rawJSON = ""
    @Published var resultJSON = ""
    @Published var debugJSON = ""
    @Published var mergedLinesText = ""
    @Published var isDropTargeted = false
    @Published var recentImagePaths: [String]

    private let extractorFactory = CalendarExtractorFactory()
    private let exporter = WebCalendarExporter()
    private let defaults = UserDefaults.standard
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private var lastExportDirectoryURL: URL?

    init() {
        let storedLocale = UserDefaults.standard.string(forKey: DefaultsKey.locale)
        self.selectedLocale = AppLocale(rawValue: storedLocale ?? "") ?? .fr
        self.baseYearInput = UserDefaults.standard.string(forKey: DefaultsKey.baseYear) ?? ""
        self.recentImagePaths = UserDefaults.standard.stringArray(forKey: DefaultsKey.recentImages) ?? []
    }

    var parsedBaseYear: Int? {
        let trimmed = baseYearInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    var events: [WebCalendarEvent] {
        webExport?.events ?? []
    }

    var recentImageURLs: [URL] {
        recentImagePaths.map(URL.init(fileURLWithPath:))
    }

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK {
            setSelectedImage(panel.url)
        }
    }

    func setSelectedImage(_ url: URL?) {
        selectedImageURL = url
        previewImage = url.flatMap(NSImage.init(contentsOf:))
        if let url {
            inferSettings(from: url)
            rememberImage(url)
            statusMessage = "Image sélectionnée: \(url.lastPathComponent)"
        } else {
            statusMessage = "Aucune image sélectionnée"
        }
    }

    func runExtraction() {
        guard let selectedImageURL else {
            statusMessage = "Sélectionne d'abord une image."
            return
        }

        isRunning = true
        statusMessage = "Extraction en cours..."
        extractionResult = nil
        debugDump = nil
        webExport = nil
        rawJSON = ""
        resultJSON = ""
        debugJSON = ""
        mergedLinesText = ""

        let locale = selectedLocale.rawValue
        let baseYear = parsedBaseYear

        Task {
            do {
                let extractor = extractorFactory.make(baseYear: baseYear)
                let dump = try extractor.extractWithDebug(from: selectedImageURL, localeIdentifier: locale)
                let result = dump.result
                let web = exporter.export(result: result, fallbackBaseYear: baseYear)
                let jsonData = try encoder.encode(web)
                let jsonString = String(decoding: jsonData, as: UTF8.self)
                let resultData = try encoder.encode(result)
                let resultString = String(decoding: resultData, as: UTF8.self)
                let debugData = try encoder.encode(dump)
                let debugString = String(decoding: debugData, as: UTF8.self)
                let mergedLines = result.rawLines.joined(separator: "\n")

                extractionResult = result
                debugDump = dump
                webExport = web
                rawJSON = jsonString
                resultJSON = resultString
                debugJSON = debugString
                mergedLinesText = mergedLines
                statusMessage = "\(web.events.count) événement(s) extrait(s)."
                persistPreferences()
                isRunning = false
            } catch {
                extractionResult = nil
                debugDump = nil
                webExport = nil
                rawJSON = ""
                resultJSON = ""
                debugJSON = ""
                mergedLinesText = ""
                statusMessage = "Erreur: \((error as? LocalizedError)?.errorDescription ?? String(describing: error))"
                isRunning = false
            }
        }
    }

    func exportJSON(named defaultFileName: String, contents: String) {
        guard !contents.isEmpty else {
            statusMessage = "Aucun JSON à exporter pour \(defaultFileName)."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFileName

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try Data(contents.utf8).write(to: url)
            lastExportDirectoryURL = url.deletingLastPathComponent()
            statusMessage = "JSON exporté vers \(url.lastPathComponent)."
        } catch {
            statusMessage = "Erreur d'export: \((error as? LocalizedError)?.errorDescription ?? String(describing: error))"
        }
    }

    func exportDebugBundle() {
        guard let debugDump, let webExport else {
            statusMessage = "Aucun bundle debug à exporter."
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"

        guard panel.runModal() == .OK, let directory = panel.url else {
            return
        }

        let folder = directory.appendingPathComponent("calendar-ocr-debug", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(rawJSON.utf8).write(to: folder.appendingPathComponent("calendar-web.json"))
            try Data(resultJSON.utf8).write(to: folder.appendingPathComponent("result.json"))
            try Data(debugJSON.utf8).write(to: folder.appendingPathComponent("debug.json"))
            try Data(mergedLinesText.utf8).write(to: folder.appendingPathComponent("raw-lines.txt"))
            lastExportDirectoryURL = folder
            statusMessage = "Bundle debug exporté vers \(folder.lastPathComponent)."
            _ = debugDump
            _ = webExport
        } catch {
            statusMessage = "Erreur d'export debug: \((error as? LocalizedError)?.errorDescription ?? String(describing: error))"
        }
    }

    func copyToClipboard(_ contents: String, label: String) {
        guard !contents.isEmpty else {
            statusMessage = "Rien à copier pour \(label)."
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(contents, forType: .string)
        statusMessage = "\(label) copié dans le presse-papiers."
    }

    func openLastExportLocation() {
        guard let url = lastExportDirectoryURL else {
            statusMessage = "Aucun export récent à ouvrir."
            return
        }

        NSWorkspace.shared.open(url)
        statusMessage = "Ouverture de \(url.lastPathComponent)."
    }

    func handleDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            Task { @MainActor in
                self.setSelectedImage(url)
            }
        }

        return true
    }

    private func persistPreferences() {
        defaults.set(selectedLocale.rawValue, forKey: DefaultsKey.locale)
        defaults.set(baseYearInput, forKey: DefaultsKey.baseYear)
        defaults.set(recentImagePaths, forKey: DefaultsKey.recentImages)
    }

    private func rememberImage(_ url: URL) {
        let path = url.path
        recentImagePaths.removeAll(where: { $0 == path })
        recentImagePaths.insert(path, at: 0)
        recentImagePaths = Array(recentImagePaths.prefix(6))
        persistPreferences()
    }

    private func inferSettings(from url: URL) {
        let name = url.lastPathComponent.lowercased()

        if name.contains("-fr") {
            selectedLocale = .fr
        } else if name.contains("-en") {
            selectedLocale = .en
        } else if name.contains("-de") {
            selectedLocale = .de
        }

        if baseYearInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let inferredYear = inferYearFromFilename(name) {
            baseYearInput = String(inferredYear)
        }

        persistPreferences()
    }

    private func inferYearFromFilename(_ filename: String) -> Int? {
        let seasonMap: [Int: Int] = [
            13: 2023,
            15: 2024,
            18: 2024,
            21: 2025,
            23: 2025,
            24: 2026
        ]

        let pattern = /season(\d+)/
        if let match = filename.firstMatch(of: pattern),
           let season = Int(match.1),
           let year = seasonMap[season] {
            return year
        }

        return nil
    }
}

private struct CalendarOCRRootView: View {
    @ObservedObject var model: CalendarOCRViewModel

    var body: some View {
        ZStack {
            FalloutTheme.appBackground.ignoresSafeArea()
            FalloutScreenEffect()

            HSplitView {
                controlsPanel
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: 400)

                resultsPanel
                    .frame(minWidth: 540)
            }
        }
    }

    private var controlsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("F76 Roadmap Extractor")
                    .font(.system(size: 30, weight: .black, design: .monospaced))
                    .foregroundStyle(FalloutTheme.primaryText)

                Text("Interface locale pour extraire les événements d'un calendrier et exporter le JSON web.")
                    .foregroundStyle(FalloutTheme.secondaryText)

                GroupBox("Image") {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("Choisir une image") {
                            model.chooseImage()
                        }

                        imagePreview

                        if let url = model.selectedImageURL {
                            Text(url.path)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(FalloutTheme.secondaryText)
                                .textSelection(.enabled)
                        } else {
                            Text("Aucune image sélectionnée")
                                .foregroundStyle(FalloutTheme.secondaryText)
                        }

                        if !model.recentImageURLs.isEmpty {
                            Divider()
                                .overlay(FalloutTheme.border)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Récents")
                                    .font(.system(.caption, design: .monospaced).weight(.bold))
                                    .foregroundStyle(FalloutTheme.secondaryText)

                                ForEach(model.recentImageURLs, id: \.path) { url in
                                    Button {
                                        model.setSelectedImage(url)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(url.lastPathComponent)
                                                .lineLimit(1)
                                            Text(url.deletingLastPathComponent().path)
                                                .font(.system(.caption2, design: .monospaced))
                                                .foregroundStyle(FalloutTheme.tertiaryText)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(FalloutButtonStyle(prominent: false))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .groupBoxStyle(FalloutPanelStyle())

                GroupBox("Paramètres") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Langue", selection: $model.selectedLocale) {
                            ForEach(CalendarOCRViewModel.AppLocale.allCases) { locale in
                                Text(locale.label).tag(locale)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(FalloutTheme.accent)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Année de base")
                                .foregroundStyle(FalloutTheme.secondaryText)
                            TextField("ex. 2026", text: $model.baseYearInput)
                                .textFieldStyle(FalloutTextFieldStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .groupBoxStyle(FalloutPanelStyle())

                GroupBox("Actions") {
                    VStack(alignment: .leading, spacing: 10) {
                        actionButton(
                            title: model.isRunning ? "Extraction en cours..." : "Lancer l'extraction",
                            systemImage: "sparkles.rectangle.stack",
                            prominent: true,
                            disabled: model.isRunning || model.selectedImageURL == nil
                        ) {
                            model.runExtraction()
                        }

                        actionButton(
                            title: "Exporter calendar-web.json",
                            systemImage: "doc.badge.arrow.down",
                            disabled: model.rawJSON.isEmpty
                        ) {
                            model.exportJSON(named: "calendar-web.json", contents: model.rawJSON)
                        }

                        actionButton(
                            title: "Exporter result.json",
                            systemImage: "doc.text",
                            disabled: model.resultJSON.isEmpty
                        ) {
                            model.exportJSON(named: "result.json", contents: model.resultJSON)
                        }

                        actionButton(
                            title: "Exporter le bundle debug",
                            systemImage: "shippingbox",
                            disabled: model.debugJSON.isEmpty
                        ) {
                            model.exportDebugBundle()
                        }

                        actionButton(
                            title: "Ouvrir le dernier dossier exporté",
                            systemImage: "folder",
                            disabled: false
                        ) {
                            model.openLastExportLocation()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .groupBoxStyle(FalloutPanelStyle())

                Text(model.statusMessage)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(FalloutTheme.secondaryText)
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .background(FalloutTheme.sidebarBackground)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $model.isDropTargeted) { providers in
            model.handleDroppedItems(providers)
        }
    }

    private var resultsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let export = model.webExport {
                TabView {
                    eventsTab(export: export)
                        .tabItem { Text("Événements") }

                    jsonTab
                        .tabItem { Text("JSON") }

                    resultTab
                        .tabItem { Text("Result") }

                    debugTab
                        .tabItem { Text("Debug") }
                }
                .tint(FalloutTheme.accent)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 42))
                        .foregroundStyle(FalloutTheme.accent)

                    Text("Aucun résultat")
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                        .foregroundStyle(FalloutTheme.primaryText)

                    Text("Lance une extraction pour voir les événements et le JSON.")
                        .foregroundStyle(FalloutTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(FalloutTheme.contentBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let export = model.webExport {
                Text(export.name)
                    .font(.system(size: 26, weight: .black, design: .monospaced))
                    .foregroundStyle(FalloutTheme.primaryText)
                HStack(spacing: 16) {
                    Text("Saison \(export.season.map(String.init) ?? "?")")
                    Text("\(export.events.count) événement(s)")
                }
                .foregroundStyle(FalloutTheme.secondaryText)
                .font(.system(.subheadline, design: .monospaced))
            } else {
                Text("Résultats")
                    .font(.system(size: 26, weight: .black, design: .monospaced))
                    .foregroundStyle(FalloutTheme.primaryText)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [FalloutTheme.headerTop, FalloutTheme.headerBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        systemImage: String,
        prominent: Bool = false,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .frame(width: 16)
                    Text(title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                }
            }
            .buttonStyle(FalloutButtonStyle(prominent: true))
            .disabled(disabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .frame(width: 16)
                    Text(title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                }
            }
            .buttonStyle(FalloutButtonStyle(prominent: false))
            .disabled(disabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func eventsTab(export: WebCalendarExport) -> some View {
        List(Array(export.events.enumerated()), id: \.offset) { _, event in
            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(FalloutTheme.primaryText)
                Text("\(event.dateStart) -> \(event.dateEnd)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(FalloutTheme.secondaryText)
            }
            .padding(.vertical, 4)
            .listRowBackground(FalloutTheme.listRow)
        }
        .scrollContentBackground(.hidden)
        .background(FalloutTheme.contentBackground)
    }

    private var jsonTab: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    model.copyToClipboard(model.rawJSON, label: "JSON web")
                } label: {
                    Label("Copier le JSON", systemImage: "doc.on.doc")
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                }
                .buttonStyle(FalloutButtonStyle(prominent: false))
                .disabled(model.rawJSON.isEmpty)
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }

            ScrollView {
                Text(model.rawJSON)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(FalloutTheme.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(20)
            }
        }
        .background(FalloutTheme.contentBackground)
    }

    private var resultTab: some View {
        ScrollView {
            Text(model.resultJSON)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(FalloutTheme.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(20)
        }
        .background(FalloutTheme.contentBackground)
    }

    private var debugTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let dump = model.debugDump {
                HStack(spacing: 16) {
                    Text("Profils OCR: \(dump.profiles.count)")
                    Text("Lignes fusionnées: \(dump.mergedLines.count)")
                }
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(FalloutTheme.secondaryText)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            TabView {
                ScrollView {
                    Text(model.mergedLinesText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(FalloutTheme.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(20)
                }
                .background(FalloutTheme.contentBackground)
                .tabItem { Text("Raw Lines") }

                ScrollView {
                    Text(model.debugJSON)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(FalloutTheme.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(20)
                }
                .background(FalloutTheme.contentBackground)
                .tabItem { Text("debug.json") }
            }
        }
    }

    private var imagePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(model.isDropTargeted ? FalloutTheme.accent.opacity(0.16) : FalloutTheme.previewBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(model.isDropTargeted ? FalloutTheme.accent : FalloutTheme.border, style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                )

            if let image = model.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(10)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 28))
                        .foregroundStyle(FalloutTheme.accent)
                    Text("Glisse-dépose une image ici")
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(FalloutTheme.primaryText)
                    Text("ou utilise le bouton de sélection")
                        .font(.caption)
                        .foregroundStyle(FalloutTheme.secondaryText)
                }
            }
        }
        .frame(height: 220)
    }
}

private struct CalendarExtractorFactory {
    func make(baseYear: Int?) -> CalendarExtractor {
        CalendarExtractor(baseYear: baseYear)
    }
}

private enum FalloutTheme {
    static let accent = Color(red: 0.43, green: 0.87, blue: 0.53)
    static let mutedAccent = Color(red: 0.61, green: 1.00, blue: 0.69)
    static let primaryText = Color(red: 0.84, green: 0.97, blue: 0.86)
    static let secondaryText = Color(red: 0.61, green: 0.88, blue: 0.67)
    static let tertiaryText = Color(red: 0.43, green: 0.71, blue: 0.53)
    static let border = Color(red: 0.33, green: 0.69, blue: 0.47).opacity(0.28)
    static let strongBorder = Color(red: 0.48, green: 0.92, blue: 0.56).opacity(0.70)
    static let headerTop = Color(red: 0.05, green: 0.12, blue: 0.09)
    static let headerBottom = Color(red: 0.03, green: 0.08, blue: 0.06)
    static let sidebarBackground = Color(red: 0.04, green: 0.09, blue: 0.07)
    static let contentBackground = Color(red: 0.02, green: 0.07, blue: 0.05)
    static let previewBackground = Color(red: 0.04, green: 0.08, blue: 0.06)
    static let listRow = Color(red: 0.05, green: 0.11, blue: 0.08)
    static let fieldBackground = Color(red: 0.04, green: 0.08, blue: 0.07)
    static let panelTop = Color(red: 0.04, green: 0.09, blue: 0.07)
    static let panelBottom = Color(red: 0.06, green: 0.12, blue: 0.09)
    static let glow = Color(red: 0.61, green: 1.00, blue: 0.69).opacity(0.18)
    static let buttonTop = Color(red: 0.07, green: 0.18, blue: 0.13)
    static let buttonBottom = Color(red: 0.05, green: 0.13, blue: 0.10)
    static let buttonSecondaryTop = Color(red: 0.05, green: 0.11, blue: 0.09)
    static let buttonSecondaryBottom = Color(red: 0.04, green: 0.08, blue: 0.07)

    static let appBackground = LinearGradient(
        colors: [
            Color(red: 0.02, green: 0.06, blue: 0.05),
            Color(red: 0.03, green: 0.08, blue: 0.06),
            Color(red: 0.05, green: 0.11, blue: 0.08)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct FalloutScreenEffect: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color.clear,
                        FalloutTheme.glow.opacity(0.18),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blur(radius: 40)

                VStack(spacing: 0) {
                    ForEach(0..<Int(max(proxy.size.height / 6, 1)), id: \.self) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.012))
                            .frame(height: 1)
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 5)
                    }
                }
                .blendMode(.screen)
                .opacity(0.10)
            }
            .allowsHitTesting(false)
        }
    }
}

private struct FalloutButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: prominent
                                ? [FalloutTheme.buttonTop, FalloutTheme.buttonBottom]
                                : [FalloutTheme.buttonSecondaryTop, FalloutTheme.buttonSecondaryBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(prominent ? FalloutTheme.strongBorder : FalloutTheme.border, lineWidth: 1.2)
            )
            .foregroundStyle(prominent ? FalloutTheme.primaryText : FalloutTheme.secondaryText)
            .shadow(color: prominent ? FalloutTheme.glow.opacity(0.35) : .clear, radius: 4, x: 0, y: 0)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
    }
}

private struct FalloutTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(FalloutTheme.fieldBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(FalloutTheme.border, lineWidth: 1)
            )
            .foregroundStyle(FalloutTheme.primaryText)
    }
}

private struct FalloutPanelStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
                .font(.system(.headline, design: .monospaced).weight(.bold))
                .foregroundStyle(FalloutTheme.accent)

            configuration.content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [FalloutTheme.panelTop, FalloutTheme.panelBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(FalloutTheme.border, lineWidth: 1.2)
        )
        .shadow(color: FalloutTheme.glow.opacity(0.45), radius: 4, x: 0, y: 0)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(FalloutTheme.strongBorder.opacity(0.18), lineWidth: 0.5)
        )
    }
}
