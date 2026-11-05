import CoreGraphics
import CoreVideo
import Vision

/// Finds cars with system Vision requests only: foreground instances (or salient objects as a fallback)
/// propose boxes and image classification keeps those that show a car. Cars hidden behind other objects
/// or far in the background are often not proposed; the user can still add them by hand.
struct VisionVehicleDetector: VehicleDetector {
    /// Classification confidence for a box to count as a car. Measured on real photos: cars 0.76–0.89,
    /// buildings, plants, pavement and a lone wheel 0. Not a probability of a correct detection.
    var minimumScore: Float = 0.3

    private static let carLabels: Set<String> = [
        "automobile", "car", "convertible", "jeep", "limousine", "police_car", "sportscar", "suv", "truck", "van",
    ]

    func detect(_ image: CGImage) async throws -> VehicleDetectionOutcome {
        try Task.checkCancellation()
        var proposals = foregroundProposals(in: image)
        if proposals?.isEmpty != false {
            try Task.checkCancellation()
            proposals = salientProposals(in: image) ?? proposals
        }
        guard let proposals else { return .unavailable }

        var cars: [CropRect] = []
        for box in proposals {
            try Task.checkCancellation()
            guard let crop = CardRenderer.crop(image, to: box) else { continue }
            guard let score = carScore(of: crop) else { return .unavailable }
            if score >= minimumScore { cars.append(box) }
        }
        return .found(cars)
    }

    /// Nil when the request is not supported, typically on the simulator.
    private func foregroundProposals(in image: CGImage) -> [CropRect]? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return [] }
        return Self.instanceBounds(of: observation.instanceMask)
    }

    private func salientProposals(in image: CGImage) -> [CropRect]? {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
        } catch {
            return nil
        }
        return request.results?.first?.salientObjects?.map { CropRect(visionRect: $0.boundingBox) } ?? []
    }

    private func carScore(of image: CGImage) -> Float? {
        let request = VNClassifyImageRequest()
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
        } catch {
            return nil
        }
        return (request.results ?? [])
            .filter { Self.carLabels.contains($0.identifier) }
            .map(\.confidence)
            .max() ?? 0
    }

    /// Bounding box of every labelled instance in Vision's low-resolution label map (0 is background).
    static func instanceBounds(of labels: CVPixelBuffer) -> [CropRect] {
        CVPixelBufferLockBaseAddress(labels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(labels, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(labels) == kCVPixelFormatType_OneComponent8,
              let base = CVPixelBufferGetBaseAddress(labels)
        else { return [] }

        let width = CVPixelBufferGetWidth(labels)
        let height = CVPixelBufferGetHeight(labels)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(labels)
        guard width > 0, height > 0 else { return [] }

        var bounds: [UInt8: (minX: Int, minY: Int, maxX: Int, maxY: Int)] = [:]
        for row in 0..<height {
            let pixels = base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for column in 0..<width where pixels[column] != 0 {
                let current = bounds[pixels[column]] ?? (column, row, column, row)
                bounds[pixels[column]] = (
                    min(current.minX, column), min(current.minY, row),
                    max(current.maxX, column), max(current.maxY, row)
                )
            }
        }
        return bounds.values.map { box in
            CropRect(
                x: Double(box.minX) / Double(width),
                y: Double(box.minY) / Double(height),
                width: Double(box.maxX - box.minX + 1) / Double(width),
                height: Double(box.maxY - box.minY + 1) / Double(height)
            )
        }
    }
}
