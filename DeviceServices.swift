import Foundation
import Network
import Observation
import UIKit
import Photos
import AVFoundation

// MARK: - Connectivity

@MainActor @Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    @ObservationIgnored var onBecameOnline: (() -> Void)?
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.update(online) }
        }
        monitor.start(queue: DispatchQueue(label: "portabill.network"))
    }

    private func update(_ online: Bool) {
        let wasOnline = isOnline
        isOnline = online
        if online && !wasOnline { onBecameOnline?() }
    }
}

// MARK: - Images

enum ImageProcessor {
    /// Downscales and JPEG-compresses a meter photo off the main thread.
    static func optimized(_ image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.7) async -> Data? {
        await Task.detached(priority: .userInitiated) { () -> Data? in
            let size = image.size
            guard size.width > 0, size.height > 0 else { return nil }
            let scale = min(1, maxDimension / max(size.width, size.height))
            let target = CGSize(width: size.width * scale, height: size.height * scale)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: target, format: format)
            let resized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: target))
            }
            return resized.jpegData(compressionQuality: quality)
        }.value
    }

    /// Keeps a copy of camera shots in the Photos library (needs NSPhotoLibraryAddUsageDescription).
    static func saveToPhotoLibrary(_ data: Data, accountNo: String) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return }
        let stamp = DateFormatter.make("yyyyMMdd_HHmmss").string(from: Date())
        try? await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = "account_\(accountNo)_\(stamp).jpg"
            request.addResource(with: .photo, data: data, options: options)
        }
    }
}

// MARK: - Torch

enum Flashlight {
    static var isAvailable: Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch ?? false
    }

    @discardableResult
    static func set(_ on: Bool) -> Bool {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return false }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }
}
