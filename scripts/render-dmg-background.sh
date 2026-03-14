#!/bin/zsh

set -euo pipefail

OUTPUT_PATH="${1:?missing output path}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOGO_PATH="${ROOT_DIR}/Sources/ocr-ui/Resources/f76logo.png"

mkdir -p "$(dirname "${OUTPUT_PATH}")"

/usr/bin/swift - <<'SWIFT' "${OUTPUT_PATH}" "${LOGO_PATH}"
import AppKit
import Foundation

let args = CommandLine.arguments
let outputURL = URL(fileURLWithPath: args[1])
let logoURL = URL(fileURLWithPath: args[2])

let width = 800
let height = 500
let image = NSImage(size: NSSize(width: width, height: height))

image.lockFocus()

let background = NSRect(x: 0, y: 0, width: width, height: height)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.02, green: 0.06, blue: 0.05, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.10, blue: 0.08, alpha: 1),
    NSColor(calibratedRed: 0.05, green: 0.14, blue: 0.10, alpha: 1)
])!
gradient.draw(in: background, angle: -25)

NSColor(calibratedRed: 0.61, green: 1.00, blue: 0.69, alpha: 0.08).setStroke()
let gridPath = NSBezierPath()
for x in stride(from: 0, through: width, by: 28) {
    gridPath.move(to: NSPoint(x: x, y: 0))
    gridPath.line(to: NSPoint(x: x, y: height))
}
for y in stride(from: 0, through: height, by: 28) {
    gridPath.move(to: NSPoint(x: 0, y: y))
    gridPath.line(to: NSPoint(x: width, y: y))
}
gridPath.lineWidth = 1
gridPath.stroke()

let glowRect = NSRect(x: 65, y: 115, width: 285, height: 285)
let glow = NSBezierPath(ovalIn: glowRect)
NSColor(calibratedRed: 0.61, green: 1.00, blue: 0.69, alpha: 0.09).setFill()
glow.fill()

if let logo = NSImage(contentsOf: logoURL) {
    let target = NSRect(x: 90, y: 140, width: 240, height: 240)
    logo.draw(in: target)
}

let title = "F76 ROADMAP EXTRACTOR"
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 30, weight: .heavy),
    .foregroundColor: NSColor(calibratedRed: 0.84, green: 0.97, blue: 0.86, alpha: 1)
]
title.draw(at: NSPoint(x: 375, y: 325), withAttributes: titleAttributes)

let subtitle = "Drag the app into Applications"
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.61, green: 0.88, blue: 0.67, alpha: 1)
]
subtitle.draw(at: NSPoint(x: 375, y: 286), withAttributes: subtitleAttributes)

let hint = "Local OCR for Fallout 76 community calendars"
let hintAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
    .foregroundColor: NSColor(calibratedRed: 0.43, green: 0.71, blue: 0.53, alpha: 1)
]
hint.draw(at: NSPoint(x: 375, y: 254), withAttributes: hintAttributes)

for index in 0..<height/6 {
    let y = index * 6
    NSColor(calibratedWhite: 1, alpha: 0.018).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: y, width: width, height: 1)).fill()
}

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fputs("failed to render background\n", stderr)
    exit(1)
}

try png.write(to: outputURL)
SWIFT
