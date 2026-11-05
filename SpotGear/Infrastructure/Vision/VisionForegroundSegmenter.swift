import CoreGraphics
import CoreImage
import CoreVideo
import Vision

/// Local foreground segmentation. The result is only a suggestion; anything unclear falls back to the photo crop.
struct VisionForegroundSegmenter: ForegroundSegmenter {
    /// Minimum share of the crop covered by the chosen instance for the cutout to be offered.
    var minimumCoverage = 0.02

    private static let context = CIContext()

    func segment(_ image: CGImage) async throws -> SegmentationOutcome {
        try Task.checkCancellation()
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // Typically unsupported hardware or the simulator.
            return .notUsable(.unsupported)
        }
        try Task.checkCancellation()

        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            return .notUsable(.noInstance)
        }
        // Other people or cars in the crop are fine as long as one instance clearly dominates.
        let label: Int
        switch ForegroundInstancePicker.pick(Self.instanceStats(of: observation.instanceMask), minimumCoverage: minimumCoverage) {
        case .instance(let picked): label = picked
        case .noInstance: return .notUsable(.emptyMask)
        case .ambiguous: return .notUsable(.ambiguous)
        }

        do {
            let masked = try observation.generateMaskedImage(
                ofInstances: IndexSet(integer: label),
                from: handler,
                croppedToInstancesExtent: true
            )
            let ciImage = CIImage(cvPixelBuffer: masked)
            guard let cutout = Self.context.createCGImage(ciImage, from: ciImage.extent) else {
                return .notUsable(.failed)
            }
            return .cutout(cutout)
        } catch {
            return .notUsable(.failed)
        }
    }

    /// Area and centroid of every labelled instance in Vision's low-resolution label map (0 is background).
    static func instanceStats(of labels: CVPixelBuffer) -> [ForegroundInstanceStats] {
        CVPixelBufferLockBaseAddress(labels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(labels, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(labels) == kCVPixelFormatType_OneComponent8,
              let base = CVPixelBufferGetBaseAddress(labels)
        else { return [] }

        let width = CVPixelBufferGetWidth(labels)
        let height = CVPixelBufferGetHeight(labels)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(labels)
        guard width > 0, height > 0 else { return [] }

        var sums: [Int: (count: Int, x: Double, y: Double)] = [:]
        for row in 0..<height {
            let pixels = base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for column in 0..<width where pixels[column] != 0 {
                let current = sums[Int(pixels[column]), default: (0, 0, 0)]
                sums[Int(pixels[column])] = (current.count + 1, current.x + Double(column), current.y + Double(row))
            }
        }

        let area = Double(width * height)
        return sums.map { label, sum in
            let dx = (sum.x / Double(sum.count) + 0.5) / Double(width) - 0.5
            let dy = (sum.y / Double(sum.count) + 0.5) / Double(height) - 0.5
            return ForegroundInstanceStats(
                label: label,
                coverage: Double(sum.count) / area,
                centerDistance: (dx * dx + dy * dy).squareRoot()
            )
        }
    }
}
