<div align="center">

<img src="App/SnagxViewer/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="160" alt="Snagx Viewer icon">

# Snagx Viewer

**Open, preview, and export Snagit captures on macOS without Snagit.**

A native SwiftUI viewer for `.snagx` files, Finder Quick Look previews and thumbnails,<br>
PNG/JPEG export (single or batch), and a scriptable CLI. Built so redacted content stays redacted.

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

## Why

Snagit saves captures as `.snagx`, a format only Snagit can open. If you've collected hundreds of them, you can't view them in Preview, see them in Finder, or turn them into ordinary images without opening Snagit one file at a time.

Snagx Viewer fixes that:

- 👀 **See them**: open any capture in a native viewer, or press <kbd>Space</kbd> in Finder.
- 🖼️ **Find them**: real Finder thumbnails instead of generic document icons.
- 📤 **Free them**: export to PNG or JPEG, one at a time or thousands at once.
- 🔒 **Stay safe**: exports default to the *annotated* image, so blurred API keys, emails, and faces stay blurred.

## Features

| | |
|---|---|
| **Viewer** | Opens via File › Open, drag & drop, or Finder's *Open With*. Zoom to fit, actual size, pinch, or ⌘+ / ⌘− / ⌘0 / ⌘9. |
| **Annotated ⇄ Original** | Switch between Snagit's rendered result and the untouched original capture. The original is clearly flagged. |
| **Info panel** | Source app and window, capture date, pixel and canvas size, DPI, annotation count, tags, and Snagit's recognized (OCR) text. |
| **Export** (⌘E) | PNG (keeps transparency) or JPEG (adjustable quality), at native Retina resolution or 1x. Keeps the color profile and correct DPI. |
| **Copy Image** (⇧⌘C) | Puts the image on the clipboard, ready to paste into Slack, Mail, or Keynote. |
| **Batch Export** (⌥⌘E) | Drop files or whole folders (optionally including subfolders), choose a format, and export with per-file progress and a summary. |
| **Quick Look** | Finder <kbd>Space</kbd> preview and thumbnails, always using the annotated image. |
| **CLI** | `snagx-export` for scripts, folders, and automation. It ships inside the app bundle. |

## Install

There are no prebuilt releases yet. Build from source: you need **macOS 26**, **Xcode 27+**, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
git clone https://github.com/olohmann/snagx-viewer.git
cd snagx-viewer

make install SIGN=adhoc       # build, copy to /Applications, register Quick Look extensions
make install-cli              # optional: link snagx-export into ~/.local/bin
```

> [!TIP]
> If you have an Apple Developer account, use `make install TEAM=<YOUR_TEAM_ID>` instead of `SIGN=adhoc`. To share the app with other Macs, sign it with your Developer ID and notarize it (see [Signing](#signing--distribution)).

### Make Finder use Snagx Viewer's previews

If Snagit is installed, its own Quick Look extensions compete for `.snagx` files. If Finder keeps showing Snagit's previews, pick Snagx Viewer in **System Settings › General › Login Items & Extensions › Quick Look**, or disable Snagit's extensions:

```sh
pluginkit -e ignore -i com.TechSmith.Snagit.Snagit-QuickLook
pluginkit -e ignore -i com.TechSmith.Snagit2024.Snagit-Thumbnail
qlmanage -r && qlmanage -r cache        # reload Quick Look
```

To re-enable Snagit's, use `-e use`. Snagx Viewer registers as an *alternate* handler, so double-clicking still opens Snagit. Use **Open With › Snagx Viewer**, or make it the default in Finder's *Get Info*.

## CLI

```sh
snagx-export capture.snagx                       # → capture.png next to the source
snagx-export -f jpg -q 85 --scale 1x -o out/ ~/Captures
snagx-export -r -o out/ ~/Captures               # recurse into subfolders
snagx-export --raw capture.snagx                 # original, unredacted → capture-raw.png
snagx-export --info --ocr capture.snagx          # print metadata (+ recognized text)
```

| Option | Description |
|---|---|
| `-o, --output <dir>` | Output folder (default: next to each source file) |
| `-f, --format png\|jpg` | Image format (default `png`) |
| `-q, --quality 0–100` | JPEG quality (default `90`) |
| `--scale native\|1x` | Native Retina resolution (default) or one pixel per point |
| `--raw` | Export the original capture instead of the annotated image |
| `-r, --recursive` | Search folders recursively |
| `--overwrite` | Overwrite existing files (default: pick a unique name such as `capture 2.png`) |
| `--info`, `--ocr` | Print metadata instead of exporting, optionally including OCR text |

Exports run in parallel. On a 2,400-capture library a full batch export takes about 30 seconds. Warnings go to stderr, and the exit code is non-zero if any file fails.

## How it works

A `.snagx` file is a ZIP archive:

```
capture.snagx
├── index.json                 → list of pages
├── {GUID}.json                → canvas size, DPI, annotation objects, effects
├── {GUID}.png                 → ORIGINAL capture (before any edits)
├── thumbnail.png              → Snagit's full-resolution ANNOTATED render
└── metadata.json              → app, window, capture date, tags, OCR text
```

Despite its name, `thumbnail.png` is Snagit's full-resolution render with every arrow, callout, blur, and crop applied. That makes it exactly what Snagit itself would export. Snagx Viewer uses it as the source of truth:

| Archive contains | "Annotated" image shown and exported | Quick Look |
|---|---|---|
| `thumbnail.png` | Snagit's annotated render | ✅ preview and thumbnail |
| no `thumbnail.png`, no edits | Original capture (identical) | ✅ preview and thumbnail |
| no `thumbnail.png`, but edits present | Original capture **with a warning** | 🚫 notice only, no thumbnail |

Snagx Viewer doesn't re-implement Snagit's annotation renderer. It never guesses how an arrow or blur should look; it uses Snagit's own output.

## Privacy & redaction safety

Original captures often contain things you deliberately blurred: tokens, passwords, customer names. Snagx Viewer treats them carefully:

- **Annotated by default.** The viewer, exports, and the CLI always start from the annotated image. The Original view and `--raw` are explicit opt-ins, and the Original view is shown under a red warning banner.
- **Quick Look never shows originals.** If a capture can't be rendered safely, you get a notice instead of a preview, and Finder shows no thumbnail.
- **OCR text is treated as sensitive.** Snagit's recognized text comes from the *original* capture, so it includes text you blurred. For edited captures, the info panel hides it until you click *Show Recognized Text*.
- **Local only.** No network access and no telemetry. The app and extensions are sandboxed and only read files you open.

## Development

```
SnagxCore/                 Swift package
├── Sources/SnagxKit/      .snagx reader, render policy, PNG/JPEG export, batch export
├── Sources/snagx-export/  CLI (swift-argument-parser)
└── Tests/SnagxKitTests/   unit tests with generated fixtures
App/
├── SnagxViewer/           SwiftUI document-based app
├── SnagxQuickLook/        Quick Look preview extension
└── SnagxThumbnail/        Quick Look thumbnail extension
Design/                    icon artwork and the script that builds the icon set
project.yml                XcodeGen spec (the .xcodeproj is generated)
```

```sh
make test        # swift test for SnagxKit
make build       # Debug build
make run         # build and launch
make release     # Release build (universal, hardened runtime)
make clean
```

The Xcode project is generated from `project.yml`, so edit that file instead of the `.xcodeproj`. Tests build synthetic `.snagx` archives on the fly. Please never commit real captures, because they may contain unredacted content (`*.snagx` is git-ignored).

### Signing & distribution

| Command | Result |
|---|---|
| `make build SIGN=adhoc` | Ad-hoc signed, for running on your own Mac |
| `make build TEAM=ABCDE12345` | Debug: Apple Development. Release: Developer ID with hardened runtime |
| `make notarize TEAM=… NOTARY_PROFILE=…` | Notarized and stapled `dist/SnagxViewer.zip`, ready to share |

Notarization needs a stored `notarytool` keychain profile:
`xcrun notarytool store-credentials <profile> --apple-id <you@example.com> --team-id <TEAM>`.

## Disclaimer

Snagx Viewer is an independent project. It isn't affiliated with, endorsed by, or sponsored by TechSmith Corporation. *Snagit* is a trademark of TechSmith Corporation. The `.snagx` format support is based on inspecting files produced by Snagit.

## License

[MIT](LICENSE) © Oliver Lohmann
