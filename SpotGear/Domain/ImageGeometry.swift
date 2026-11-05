import CoreGraphics

/// Conversions between normalized crops and on-screen geometry of an aspect-fit image.
enum ImageGeometry {
    /// Rectangle occupied by an image of `imageSize` drawn aspect-fit and centered in `container`.
    static func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return .zero
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    static func viewRect(for crop: CropRect, in fitted: CGRect) -> CGRect {
        CGRect(
            x: fitted.minX + crop.x * fitted.width,
            y: fitted.minY + crop.y * fitted.height,
            width: crop.width * fitted.width,
            height: crop.height * fitted.height
        )
    }

    /// Converts a translation in view points to a normalized delta of the displayed image.
    static func normalizedDelta(_ translation: CGSize, in fitted: CGRect) -> (dx: Double, dy: Double) {
        guard fitted.width > 0, fitted.height > 0 else { return (0, 0) }
        return (translation.width / fitted.width, translation.height / fitted.height)
    }

    /// Pixel size after applying an EXIF orientation (1–8). Orientations 5–8 swap the axes.
    static func orientedSize(width: Int, height: Int, exifOrientation: Int) -> CGSize {
        (5...8).contains(exifOrientation)
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
    }
}
