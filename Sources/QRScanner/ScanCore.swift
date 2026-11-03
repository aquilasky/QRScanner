import Foundation
import CoreGraphics
import Vision

struct WindowCandidate {
    let id: CGWindowID
    let frame: CGRect // AppKit global coordinates, origin at bottom left.
    let title: String
}

enum ScanGeometry {
    static let dragThreshold: CGFloat = 5

    static func appKitRect(_ rect: CGRect, mainScreenTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainScreenTop - rect.maxY, width: rect.width, height: rect.height)
    }

    static func region(from start: CGPoint, to end: CGPoint, within bounds: CGRect) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(start.x - end.x), height: abs(start.y - end.y)).intersection(bounds)
    }

    static func isDrag(from start: CGPoint, to end: CGPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) > dragThreshold
    }

    static func window(at point: CGPoint, candidates: [WindowCandidate]) -> WindowCandidate? {
        candidates.first { $0.frame.contains(point) }
    }

    static func pixelCrop(region: CGRect, screen: CGRect, width: Int, height: Int) -> CGRect {
        let intersection = region.intersection(screen)
        guard !intersection.isNull, screen.width > 0, screen.height > 0 else { return .null }
        let sx = CGFloat(width) / screen.width
        let sy = CGFloat(height) / screen.height
        return CGRect(x: (intersection.minX - screen.minX) * sx,
                      y: (screen.maxY - intersection.maxY) * sy,
                      width: intersection.width * sx, height: intersection.height * sy)
            .integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

enum PayloadPolicy {
    static func webURL(_ payload: String) -> URL? {
        guard let parts = URLComponents(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              let url = parts.url else { return nil }
        return url
    }
}

enum QRDecoder {
    static func decode(_ image: CGImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image).perform([request])
        var seen = Set<String>()
        return (request.results ?? []).compactMap(\.payloadStringValue).filter { seen.insert($0).inserted }
    }
}
