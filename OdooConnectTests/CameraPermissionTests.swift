import Testing
import AVFoundation
@testable import OdooConnect

@Suite struct CameraPermissionTests {
    typealias Permission = BarcodeScannerView.ScannerController.CameraPermission

    @Test func authorizedMapsToAuthorized() {
        #expect(BarcodeScannerView.ScannerController.permission(for: .authorized) == .authorized)
    }

    @Test func notDeterminedMapsToNeedsPrompt() {
        #expect(BarcodeScannerView.ScannerController.permission(for: .notDetermined) == .needsPrompt)
    }

    @Test func deniedMapsToDenied() {
        #expect(BarcodeScannerView.ScannerController.permission(for: .denied) == .denied)
    }

    @Test func restrictedMapsToDenied() {
        #expect(BarcodeScannerView.ScannerController.permission(for: .restricted) == .denied)
    }
}
