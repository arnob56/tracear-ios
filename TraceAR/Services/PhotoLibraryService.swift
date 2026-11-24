import UIKit
import Photos

enum PhotoLibraryService {
    static func saveImageToPhotos(_ image: UIImage) async -> Result<Void, AppErrorState> {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let resolvedStatus: PHAuthorizationStatus

        switch currentStatus {
        case .notDetermined:
            resolvedStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        default:
            resolvedStatus = currentStatus
        }

        switch resolvedStatus {
        case .authorized, .limited:
            break
        case .denied, .restricted, .notDetermined:
            return .failure(.photoSavePermissionDenied())
        @unknown default:
            return .failure(.photoSavePermissionDenied())
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return .success(())
        } catch {
            return .failure(
                .saveFailed(detail: "Photos couldn't store the image (\(error.localizedDescription)). Check available storage or share the file instead.")
            )
        }
    }

    static func writeTemporaryPNG(_ image: UIImage, filenamePrefix: String = "TraceAR") -> URL? {
        guard let pngData = image.pngData() else { return nil }
        let stamp = Int(Date().timeIntervalSince1970)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filenamePrefix)-\(stamp).png")
        do {
            try pngData.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
