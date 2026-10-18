import Foundation

let bundledEngineRoot = Bundle.main.resourceURL?.appendingPathComponent("Engines")
func bundledExecutable(_ name: String) -> String? {
    let paths = ["rsvg-convert":"opt/librsvg/bin/rsvg-convert", "ffmpeg":"opt/ffmpeg/bin/ffmpeg", "magick":"opt/imagemagick/bin/magick", "gs":"opt/ghostscript/bin/gs", "pandoc":"opt/pandoc/bin/pandoc", "python3":"opt/python@3.14/bin/python3.14", "soffice":"LibreOffice.app/Contents/MacOS/soffice"]
    guard let path = paths[name], let url = bundledEngineRoot?.appendingPathComponent(path), FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
    return url.path
}
func engineEnvironment() -> [String:String] {
    var env = ProcessInfo.processInfo.environment
    guard let root = bundledEngineRoot, FileManager.default.fileExists(atPath: root.path) else { return env }
    let path = root.path
    env["PATH"] = ["ffmpeg","imagemagick","ghostscript","pandoc","python@3.14"].map { path + "/opt/\($0)/bin" }.joined(separator: ":") + ":/usr/bin:/bin"
    env["SAL_USE_VCLPLUGIN"] = "svp"
    env["MAGICK_HOME"] = path + "/opt/imagemagick"
    env["MAGICK_CONFIGURE_PATH"] = path + "/opt/imagemagick/etc/ImageMagick-7:" + path + "/opt/imagemagick/share/ImageMagick-7"
    env["MAGICK_CODER_MODULE_PATH"] = path + "/opt/imagemagick/lib/ImageMagick/modules-Q16HDRI/coders"
    env["PYTHONHOME"] = path + "/opt/python@3.14/Frameworks/Python.framework/Versions/3.14"
    env.removeValue(forKey: "PYTHONPATH")
    let gs = root.appendingPathComponent("opt/ghostscript/share/ghostscript")
    env["GS_LIB"] = gs.path + "/Resource/Init:" + gs.path + "/lib:" + gs.path + "/Resource/Font:" + gs.path + "/fonts"
    return env
}
