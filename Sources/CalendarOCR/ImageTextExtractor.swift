import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

public struct OCRTextLine: Equatable {
    public let text: String
    public let minX: CGFloat
    public let minY: CGFloat
    public let profile: OCRProfile

    public init(text: String, minX: CGFloat, minY: CGFloat, profile: OCRProfile) {
        self.text = text
        self.minX = minX
        self.minY = minY
        self.profile = profile
    }
}

public enum OCRProfile: String, CaseIterable, Codable {
    case original
    case boostedContrast
    case desaturated
}

public final class ImageTextExtractor {
    private let ciContext = CIContext()

    public init() {}

    public func extractLines(
        from imageURL: URL,
        localeIdentifier: String = "fr-FR",
        profiles: [OCRProfile] = OCRProfile.allCases
    ) throws -> [OCRTextLine] {
        guard let baseImage = CIImage(contentsOf: imageURL) else {
            throw OCRExtractorError.cannotLoadImage(imageURL.path)
        }

        var seen: Set<String> = []
        var collected: [OCRTextLine] = []

        for profile in profiles {
            let image = preprocess(image: baseImage, profile: profile)
            let recognized = try recognizeText(in: image, localeIdentifier: localeIdentifier, profile: profile)
            for line in recognized {
                let dedupeKey = "\(round(line.minX * 1000))|\(round(line.minY * 1000))|\(normalize(line.text))"
                if seen.insert(dedupeKey).inserted {
                    collected.append(line)
                }
            }
        }

        return collected.sorted {
            let verticalDistance = abs($0.minY - $1.minY)
            if verticalDistance > 0.015 {
                return $0.minY > $1.minY
            }
            return $0.minX < $1.minX
        }
    }

    public func extractDebugDump(
        from imageURL: URL,
        localeIdentifier: String = "fr-FR",
        profiles: [OCRProfile] = OCRProfile.allCases
    ) throws -> (merged: [OCRTextLine], perProfile: [OCRDebugProfileDump]) {
        guard let baseImage = CIImage(contentsOf: imageURL) else {
            throw OCRExtractorError.cannotLoadImage(imageURL.path)
        }

        var seen: Set<String> = []
        var collected: [OCRTextLine] = []
        var profileDumps: [OCRDebugProfileDump] = []

        for profile in profiles {
            let image = preprocess(image: baseImage, profile: profile)
            let recognized = try recognizeText(in: image, localeIdentifier: localeIdentifier, profile: profile)
            profileDumps.append(
                OCRDebugProfileDump(
                    profile: profile.rawValue,
                    lines: recognized.map(Self.debugLine(from:))
                )
            )
            for line in recognized {
                let dedupeKey = "\(round(line.minX * 1000))|\(round(line.minY * 1000))|\(normalize(line.text))"
                if seen.insert(dedupeKey).inserted {
                    collected.append(line)
                }
            }
        }

        let merged = collected.sorted {
            let verticalDistance = abs($0.minY - $1.minY)
            if verticalDistance > 0.015 {
                return $0.minY > $1.minY
            }
            return $0.minX < $1.minX
        }

        return (merged, profileDumps)
    }

    private func preprocess(image: CIImage, profile: OCRProfile) -> CIImage {
        switch profile {
        case .original:
            return image
        case .boostedContrast:
            let filter = CIFilter.colorControls()
            filter.inputImage = image
            filter.saturation = 0
            filter.contrast = 1.55
            filter.brightness = 0.05
            return filter.outputImage ?? image
        case .desaturated:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.saturation = 0
            controls.contrast = 1.25

            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = controls.outputImage
            sharpen.sharpness = 0.6
            return sharpen.outputImage ?? image
        }
    }

    private func recognizeText(in image: CIImage, localeIdentifier: String, profile: OCRProfile) throws -> [OCRTextLine] {
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            throw OCRExtractorError.cannotRenderImage
        }

        var observations: [VNRecognizedTextObservation] = []
        let request = VNRecognizeTextRequest { request, error in
            if error != nil {
                return
            }
            observations = (request.results as? [VNRecognizedTextObservation]) ?? []
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [localeIdentifier]
        request.minimumTextHeight = 0.012

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }
            return OCRTextLine(text: text, minX: observation.boundingBox.minX, minY: observation.boundingBox.minY, profile: profile)
        }
    }

    private static func debugLine(from line: OCRTextLine) -> OCRDebugLine {
        OCRDebugLine(
            text: line.text,
            minX: Double(line.minX),
            minY: Double(line.minY),
            profile: line.profile.rawValue
        )
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum OCRExtractorError: Error, LocalizedError {
    case cannotLoadImage(String)
    case cannotRenderImage

    public var errorDescription: String? {
        switch self {
        case .cannotLoadImage(let path):
            return "Impossible de charger l'image: \(path)"
        case .cannotRenderImage:
            return "Impossible de rendre l'image pour l'OCR"
        }
    }
}
