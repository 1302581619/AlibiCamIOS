import SwiftUI
import UIKit
import AVFoundation

/// 把 AVCaptureVideoPreviewLayer 包装成 SwiftUI 视图
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainer {
        let v = PreviewContainer()
        v.preview.session = session
        v.preview.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewContainer, context: Context) {
        uiView.preview.frame = uiView.bounds
    }

    final class PreviewContainer: UIView {
        let preview = AVCaptureVideoPreviewLayer()
        override init(frame: CGRect) {
            super.init(frame: frame)
            layer.addSublayer(preview)
            backgroundColor = .black
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() {
            super.layoutSubviews()
            preview.frame = bounds
        }
    }
}
