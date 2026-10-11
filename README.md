# Dropform

A native personal macOS menu-bar utility for local file conversion and compression. Offline React/shadcn workbench in WKWebView, AppKit drop basket, no uploads or web server.

## Run

```sh
./scripts/build.sh
open dist/Dropform.app
```

Building requires macOS 13+, Swift command line tools, Node.js/npm (`npm --prefix ui ci`), and local conversion engines. The app discovers Homebrew FFmpeg, ImageMagick and Ghostscript, Pandoc, and LibreOffice in `/Applications`. It also recognizes this Mac's existing bundled LibreOffice launcher. Engine binaries are not bundled into the app.

Drag a file in Finder: a basket appears on the right side of the current screen. Drop onto it to open the workbench. The menu bar also provides a manual basket action. Closing the window leaves the menu-bar utility running. Quit from its menu.

## Included

- Batch conversion with per-file formats, failures and Finder reveal
- Images, video, audio, office documents, spreadsheets, presentations, subtitles, Markdown/EPUB and EML email
- Searchable output formats, including descriptive names such as Word and Excel
- Multistep document-to-image conversion, preserving all rendered pages
- PDF to PNG/JPG/WebP/TIFF/BMP and selectable-text Word/ODT/RTF/HTML/TXT export
- Embedded images to Word/ODT/HTML; video first-frame extraction
- PDF recompression via Ghostscript
- PDF merging, page splitting, page-to-PNG and text extraction
- Image collections to PDF, ZIP archive creation
- Compression in the original format; larger results are not saved
- Image resizing and video downscaling, quality/audio bitrate controls
- Optional image/media metadata removal
- Per-file quality controls and live bytes-written/final output sizes
- Automatic real conversion previews for files under 10 MB, debounced by 350 ms; stale work is cancelled, temporary output can be inspected with the eye button and is removed when replaced or the app quits, and previews stop after eight seconds
- Output folder selection, non-overwriting names, cancellation
- Adaptive light/dark appearance with shadcn controls and locally bundled Plus Jakarta Sans

## Current limits

This is a working first version, not complete parity with howtoconvert.co's thousands of conversion routes. MSG email, archive extraction, OCR, visual cropping, vectorization and specialist routes are not implemented. EML exports headers and readable body text; attachments are listed but not extracted. PDF-to-document conversion exports selectable text, not the original layout or images. See [coverage](COVERAGE.md). Installed engine codecs determine which particular files work. Some source formats have no same-format encoder: use Convert with an available target. Lossless formats may not get smaller. Quality/resize/metadata controls apply to relevant image/media engines, not Office documents; PDF quality selects a Ghostscript preset. Multipage image conversions that would produce separate files are rejected instead of silently dropping pages.

The automatic basket observes macOS's drag pasteboard while the primary mouse button is held. Finder file drags are the intended workflow; virtual attachments and drags that do not expose file URLs may not trigger it. A manual menu action is available. Login launch and packaged dependency installation are not included yet.

## Verification

```sh
./scripts/check.sh
```

Validated on this Mac: 123 engine tests, 4 live-preview integration checks and 20 interface tests. The engine suite runs real conversions across image, audio, video, Office and subtitle targets, PDF tools, ZIP round trips, resizing, output validation, source preservation, collision-safe naming, invalid input cleanup and active cancellation/recovery. Interface tests cover bridge actions, state updates, keyboard interaction, processing locks and compression eligibility.

A workbench image conversion and output-folder selection were also checked through the running app. The installed release was opened and the manual basket remained visible after closing the workbench. Automatic appearance during a real Finder drag still requires manual verification: the automation environment denied Finder access. These checks do not establish every possible codec/input combination or full production readiness.

Third-party notices are included under `LICENSES` in the application resources. Conversion engines remain separately installed software under their own licenses.
