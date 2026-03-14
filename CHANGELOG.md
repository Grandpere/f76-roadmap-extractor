# Changelog

All notable changes to this project will be documented in this file.

The format is inspired by Keep a Changelog, with lightweight version notes adapted to this project.

## [1.0.0] - 2026-03-14

### Added

- Initial public release of F76 Roadmap Extractor
- Local OCR extraction based on Apple Vision
- Specialized parsing for official Fallout 76 roadmap images
- JSON export for integration with [f76-tools](https://github.com/Grandpere/f76-tools)
- Support for `FR`, `EN`, and `DE` roadmap inputs
- macOS SwiftUI application
- CLI workflow for direct extraction and debug export
- Debug artifacts: `calendar-web.json`, `result.json`, `debug.json`, and `raw-lines.txt`
- Packaging scripts for `.app` and `.dmg`
- French and English README files

### Improved

- Editorial cleanup of extracted titles for web-facing JSON
- Fallout-inspired terminal theme for the macOS app
- Usability improvements in the app:
  - clipboard copy for JSON
  - recent images
  - remembered locale and base year
  - open last export location

### Notes

- Optimized for the Fallout 76 official roadmap visual family
- Runs fully locally without paid OCR services or external APIs
