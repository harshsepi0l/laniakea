import AVFoundation
import SwiftUI

/// What the overlay needs to line up with the camera picture.
struct CameraOptics: Equatable {
    /// Field of view along the sensor's long side, in degrees.
    let fieldOfViewDeg: Double
    /// Sensor long side over short side, such as 16/9.
    let aspect: Double
}

/// The back camera, full screen and filling it. Reports its optics so the sky overlay can match
/// the picture, and turns the picture with the screen. Shows black where there's no camera or
/// permission.
struct CameraPreview: UIViewRepresentable {
    /// UIInterfaceOrientation raw value: 1 portrait, 2 upside down, 3 landscape right, 4 landscape left.
    let interfaceOrientation: Int
    let onOptics: (CameraOptics) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        Task { await configure(view) }
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.rotate(for: interfaceOrientation)
    }

    static func dismantleUIView(_ view: PreviewView, coordinator: ()) {
        let session = view.previewLayer.session
        DispatchQueue.global(qos: .userInitiated).async { session?.stopRunning() }
    }

    @MainActor
    private func configure(_ view: PreviewView) async {
        guard await AVCaptureDevice.requestAccess(for: .video),
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }
        let session = AVCaptureSession()
        session.sessionPreset = .high
        guard session.canAddInput(input) else { return }
        session.addInput(input)
        view.previewLayer.session = session
        view.rotate(for: interfaceOrientation)
        let size = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let aspect = Double(max(size.width, size.height)) / Double(max(min(size.width, size.height), 1))
        onOptics(CameraOptics(fieldOfViewDeg: Double(device.activeFormat.videoFieldOfView), aspect: aspect))
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        func rotate(for orientation: Int) {
            let angle: CGFloat
            switch orientation {
            case 2: angle = 270
            case 3: angle = 0
            case 4: angle = 180
            default: angle = 90
            }
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }
}
