import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal

final class TraceImageProcessor: @unchecked Sendable {
    static let shared = TraceImageProcessor()

    private let ciContext: CIContext
    private let cacheLock = NSLock()
    private var cachedKey: TraceFilterSettings.FilterCacheKey?
    private var cachedCGImage: CGImage?

    init() {
        let options: [CIContextOption: Any] = [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false,
            .workingColorSpace: CGColorSpaceCreateDeviceRGB()
        ]
        if let mtlDevice = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: mtlDevice, options: options)
        } else {
            self.ciContext = CIContext(options: options)
        }
    }

    /// Normalizes EXIF orientation and downsamples large photos to keep AR textures fast and memory-safe on A14.
    func normalizeAndDownsample(_ image: UIImage, maxDimension: CGFloat = 1600) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth > 0, pixelHeight > 0 else { return image }

        let longestEdge = max(pixelWidth, pixelHeight)
        if longestEdge <= maxDimension && image.imageOrientation == .up && image.scale == 1.0 {
            return image
        }

        let ratio = min(1.0, maxDimension / longestEdge)
        let targetSize = CGSize(
            width: max(1, (pixelWidth * ratio).rounded()),
            height: max(1, (pixelHeight * ratio).rounded())
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        format.preferredRange = .standard

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    func process(
        source: UIImage,
        sourceID: UUID,
        settings: TraceFilterSettings
    ) -> CGImage? {
        if !settings.requiresImageProcessing {
            return source.cgImage
        }

        let key = TraceFilterSettings.FilterCacheKey(sourceID: sourceID, settings: settings)
        cacheLock.lock()
        if cachedKey == key, let hit = cachedCGImage {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        guard let baseCI = CIImage(image: source) else {
            return source.cgImage
        }

        let extent = baseCI.extent
        guard !extent.isEmpty else { return source.cgImage }

        let outputCI: CIImage
        if settings.isOutlineOnly {
            outputCI = buildOutlinePipeline(
                input: baseCI,
                extent: extent,
                intensity: Float(settings.edgeIntensity),
                invertLines: settings.isInverted
            )
        } else {
            outputCI = buildTonePipeline(
                input: baseCI,
                grayscale: settings.isGrayscale,
                invert: settings.isInverted
            )
        }

        guard let rendered = ciContext.createCGImage(
            outputCI,
            from: extent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        ) else {
            return source.cgImage
        }

        cacheLock.lock()
        cachedKey = key
        cachedCGImage = rendered
        cacheLock.unlock()

        return rendered
    }

    func purgeCache() {
        cacheLock.lock()
        cachedKey = nil
        cachedCGImage = nil
        cacheLock.unlock()
        ciContext.clearCaches()
    }

    private func buildTonePipeline(
        input: CIImage,
        grayscale: Bool,
        invert: Bool
    ) -> CIImage {
        var current = input

        if grayscale {
            let controls = CIFilter.colorControls()
            controls.inputImage = current
            controls.saturation = 0.0
            controls.contrast = 1.05
            if let out = controls.outputImage {
                current = out
            }
        }

        if invert {
            let inverter = CIFilter.colorInvert()
            inverter.inputImage = current
            if let out = inverter.outputImage {
                current = out
            }
        }

        return current
    }

    /// Produces crisp contour lines on a transparent background so physical paper and pencil remain clearly visible.
    private func buildOutlinePipeline(
        input: CIImage,
        extent: CGRect,
        intensity: Float,
        invertLines: Bool
    ) -> CIImage {
        var current = input

        // 1. Desaturate to luminance for clean single-channel edge magnitude.
        let preControls = CIFilter.colorControls()
        preControls.inputImage = current
        preControls.saturation = 0.0
        preControls.contrast = 1.12
        if let out = preControls.outputImage {
            current = out
        }

        // 2. Mild blur suppresses camera JPEG grain before Sobel/edge pass.
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = current.clampedToExtent()
        blur.radius = 0.7
        if let out = blur.outputImage?.cropped(to: extent) {
            current = out
        }

        // 3. Core Image edge detector.
        let edges = CIFilter.edges()
        edges.inputImage = current.clampedToExtent()
        edges.intensity = intensity
        if let out = edges.outputImage?.cropped(to: extent) {
            current = out
        }

        // 4. Normalize edge output to grayscale intensity.
        let postControls = CIFilter.colorControls()
        postControls.inputImage = current
        postControls.saturation = 0.0
        postControls.contrast = 1.3
        if let out = postControls.outputImage {
            current = out
        }

        // 5. Map edge strength into premultiplied RGBA so flat regions become transparent.
        //    invertLines == false -> dark ink outlines (0, 0, 0, A)
        //    invertLines == true  -> bright white outlines (A, A, A, A) for dark paper / dim rooms
        let gain: CGFloat = 2.2
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = current
        if invertLines {
            let v = CIVector(x: gain, y: 0, z: 0, w: 0)
            matrix.rVector = v
            matrix.gVector = v
            matrix.bVector = v
            matrix.aVector = v
        } else {
            let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
            matrix.rVector = zero
            matrix.gVector = zero
            matrix.bVector = zero
            matrix.aVector = CIVector(x: gain, y: 0, z: 0, w: 0)
        }
        matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        if let out = matrix.outputImage {
            current = out
        }

        let clamp = CIFilter.colorClamp()
        clamp.inputImage = current
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        if let out = clamp.outputImage {
            current = out
        }

        return current
    }
}
