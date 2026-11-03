import XCTest
import AppKit
import CoreImage.CIFilterBuiltins
@testable import QRScanner

final class ScanCoreTests: XCTestCase {
    func testWindowOrderingUsesFrontmostContainingWindow() {
        let windows = [
            WindowCandidate(id: 1, frame: CGRect(x: 20, y: 20, width: 100, height: 100), title: "front"),
            WindowCandidate(id: 2, frame: CGRect(x: 0, y: 0, width: 300, height: 300), title: "back")
        ]
        XCTAssertEqual(ScanGeometry.window(at: CGPoint(x: 50, y: 50), candidates: windows)?.id, 1)
        XCTAssertEqual(ScanGeometry.window(at: CGPoint(x: 200, y: 200), candidates: windows)?.id, 2)
        XCTAssertNil(ScanGeometry.window(at: CGPoint(x: -1, y: 0), candidates: windows))
    }
    func testClickVersusDragThreshold() {
        XCTAssertFalse(ScanGeometry.isDrag(from: .zero, to: CGPoint(x: 3, y: 4)))
        XCTAssertTrue(ScanGeometry.isDrag(from: .zero, to: CGPoint(x: 4, y: 4)))
    }
    func testReverseDragAndScreenClipping() {
        let bounds = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        XCTAssertEqual(ScanGeometry.region(from: CGPoint(x: -100, y: 500), to: CGPoint(x: -400, y: 100), within: bounds),
                       CGRect(x: -400, y: 100, width: 300, height: 400))
        XCTAssertEqual(ScanGeometry.region(from: CGPoint(x: -100, y: 500), to: CGPoint(x: 100, y: 800), within: bounds),
                       CGRect(x: -100, y: 500, width: 100, height: 200))
    }
    func testCoordinatesAcrossDisplays() {
        XCTAssertEqual(ScanGeometry.appKitRect(CGRect(x: -1200, y: -300, width: 800, height: 600), mainScreenTop: 900),
                       CGRect(x: -1200, y: 600, width: 800, height: 600))
        XCTAssertEqual(ScanGeometry.pixelCrop(region: CGRect(x: -1100, y: 100, width: 200, height: 100),
            screen: CGRect(x: -1440, y: -200, width: 1440, height: 900), width: 2880, height: 1800),
            CGRect(x: 680, y: 1000, width: 400, height: 200))
    }
    func testURLPolicy() {
        for payload in ["https://example.com/path?q=1", "http://localhost:8080", " HTTPS://example.com "] {
            XCTAssertNotNil(PayloadPolicy.webURL(payload), payload)
        }
        for payload in ["hello", "javascript:alert(1)", "file:///tmp/a", "mailto:a@example.com", "https:///", "https://user:password@example.com", "https://user@example.com", "WIFI:T:WPA;S:test;P:password;;"] {
            XCTAssertNil(PayloadPolicy.webURL(payload), payload)
        }
    }
    func testKnownQRCodeRoundTripAndBlank() throws {
        let payload = "https://example.com/qr-test?value=42"
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        let image = try XCTUnwrap(filter.outputImage)
        // White quiet zone surrounding a known, deterministic QR fixture.
        let scaled = image.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let extent = scaled.extent.insetBy(dx: -32, dy: -32)
        let white = CIImage(color: .white).cropped(to: extent)
        let output = scaled.composited(over: white)
        let cg = try XCTUnwrap(CIContext().createCGImage(output, from: extent))
        XCTAssertEqual(try QRDecoder.decode(cg), [payload])
        let blank = try XCTUnwrap(CIContext().createCGImage(CIImage(color: .white), from: CGRect(x: 0, y: 0, width: 200, height: 200)))
        XCTAssertEqual(try QRDecoder.decode(blank), [])
    }
}
