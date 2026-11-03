import AppKit
import CoreImage.CIFilterBuiltins

@main
struct QRScannerEntry {
@MainActor static func main() throws {
// Deterministic fixture for automated recognition tests and real-window acceptance.
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--make-fixture" {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data("https://example.com/".utf8)
    filter.correctionLevel = "M"
    let context = CIContext()
    guard let image = filter.outputImage,
          let cg = context.createCGImage(image.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
                                         from: image.extent.applying(CGAffineTransform(scaleX: 12, y: 12))) else {
        fatalError("Unable to create fixture")
    }
    let bitmap = NSBitmapImageRep(cgImage: cg)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}

}
}
