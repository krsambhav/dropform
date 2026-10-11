# Conversion coverage

Reference reviewed: https://howtoconvert.co/ (11 October 2026).

The reference advertises direct and multistage conversions across images, video, audio, documents, email and subtitles. Dropform does not yet match its full catalog.

| Area | Dropform today | Remaining gaps |
| --- | --- | --- |
| PDF → images | PNG, JPG, WebP, TIFF, BMP; every page; multipage output folder | Other image targets, page-range selection |
| PDF → documents | DOCX, DOC, ODT, RTF, HTML, TXT from selectable text | Layout reconstruction, embedded images, OCR, presentations |
| PDF tools | Recompression, merge, split, rendering, text extraction | Fine-grained PDF optimization settings |
| Images | Common raster conversion, resizing, metadata stripping; embedded images to DOCX/DOC/ODT/HTML | RAW coverage, vectorization, cropping, specialist formats |
| Video/audio | Common FFmpeg targets, quality, resizing, audio extraction; first-frame PNG/JPG/WebP | Trimming, complete codec/format matrix |
| Office | Common document, spreadsheet and presentation targets; all pages to images; Markdown/EPUB/reStructuredText via Pandoc | Complex cross-type semantics such as PDF tables to spreadsheets |
| Subtitles | SRT, VTT, ASS; text/Word/PDF with timing cues | Remaining specialist subtitle formats |
| Email | EML headers and readable body → TXT/HTML/PDF/DOCX/PNG/JPG | MSG, attachment extraction, original HTML styling |
| Archives | ZIP creation | Extraction and comic-book formats |

The application’s format library is the source of truth for currently exposed routes. Options are not added solely to inflate the format count. New routes need output validation and tests, including multipage handling, cancellation and source preservation.
