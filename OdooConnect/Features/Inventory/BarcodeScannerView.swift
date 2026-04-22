import SwiftUI
@preconcurrency import AVFoundation
import UIKit

/// Thin AVFoundation wrapper. Fires `onScan` once per resolved code and then
/// ignores further frames until the parent dismisses or resets the view.
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onError: onError)
    }

    func makeUIViewController(context: Context) -> ScannerController {
        let vc = ScannerController()
        vc.coordinator = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onScan: (String) -> Void
        let onError: (String) -> Void
        private var handled = false

        init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onScan = onScan
            self.onError = onError
        }

        nonisolated func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard
                let first = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                let value = first.stringValue
            else { return }
            Task { @MainActor [weak self] in
                guard let self, !self.handled else { return }
                self.handled = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.onScan(value)
            }
        }
    }

    final class ScannerController: UIViewController {
        var coordinator: Coordinator?
        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private let reticle = CAShapeLayer()

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            configureSession()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            if !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { [session] in
                    session.startRunning()
                }
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning {
                session.stopRunning()
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
            layoutReticle()
        }

        private func configureSession() {
            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else {
                coordinator?.onError("Kamera nicht verfügbar.")
                return
            }
            session.beginConfiguration()
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                coordinator?.onError("Barcode-Ausgabe nicht verfügbar.")
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(coordinator, queue: .main)
            output.metadataObjectTypes = [
                .ean8, .ean13, .code128, .code39, .code93,
                .upce, .qr, .pdf417, .itf14, .dataMatrix
            ]
            session.commitConfiguration()

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
            previewLayer = layer

            reticle.strokeColor = UIColor.systemGreen.cgColor
            reticle.fillColor = UIColor.clear.cgColor
            reticle.lineWidth = 3
            view.layer.addSublayer(reticle)
        }

        private func layoutReticle() {
            let side = min(view.bounds.width, view.bounds.height) * 0.6
            let origin = CGPoint(
                x: view.bounds.midX - side / 2,
                y: view.bounds.midY - side / 2
            )
            let rect = CGRect(origin: origin, size: CGSize(width: side, height: side))
            reticle.path = UIBezierPath(roundedRect: rect, cornerRadius: 16).cgPath
        }
    }
}
