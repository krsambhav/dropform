# Bundled conversion engines

Dropform invokes these engines as separate processes. Their copyright and license terms remain those of their respective authors. Original license files, notices and Homebrew recipes are retained in Contents/Resources/Engines/Cellar; LibreOffice's notices are in Engines/LibreOffice.app/Contents/Resources.

- FFmpeg: GPL-3.0-or-later (Homebrew build with GPL codecs). https://ffmpeg.org/legal.html
- ImageMagick: ImageMagick license. https://imagemagick.org/script/license.php
- Ghostscript: AGPL-3.0-or-later. https://www.ghostscript.com/licensing/index.html
- Pandoc: GPL-2.0-or-later. https://pandoc.org
- Python: PSF license. https://docs.python.org/3/license.html
- LibreOffice 25.8.2.2: MPL-2.0 and bundled third-party licenses. https://www.libreoffice.org/licenses/

The release's engine-sources archive contains pinned upstream source archives and the Homebrew recipes used for the installed binaries. The manifest inside Engines lists bundled package versions. The repository's scripts/bundle-engines.py records relocation changes; no upstream algorithmic source changes are made. LibreOffice source is available at https://downloadarchive.documentfoundation.org/libreoffice/old/25.8.2.2/src/ and its external dependency sources at https://dev-www.libreoffice.org/src/ (see download.lst in the matching source tree). Pandoc's Haskell package source versions are recorded in its cabal project and available from https://hackage.haskell.org/.

You may replace these separate engines and libraries with compatible modified versions, subject to their licenses. Ad-hoc signing may need to be repeated after modifying the application bundle. This build does not impose a proprietary engine license or restrict those rights.
