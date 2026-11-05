import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Local tone and sharpness polish of an alpha cutout. Keeps hue, shape and the car's own brightness.
enum CutoutEnhancer {
    static let sharpness: Float = 0.3
    static let sampleMaxPixelSize = 512

    /// Works on encoded values so the levels math matches the histogram it was derived from.
    private static let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

    /// Falls back to the untouched cutout when rendering fails.
    static func enhanced(_ cutout: CGImage) -> CGImage {
        let levels = ToneLevels(histogram: luminanceHistogram(of: cutout))
        let input = CIImage(cgImage: cutout)
        var image = input

        if !levels.isIdentity {
            let scale = CGFloat(levels.scale)
            let bias = CGFloat(levels.bias)
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = image.unpremultiplyingAlpha()
            matrix.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
            matrix.gVector = CIVector(x: 0, y: scale, z: 0, w: 0)
            matrix.bVector = CIVector(x: 0, y: 0, z: scale, w: 0)
            matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            matrix.biasVector = CIVector(x: bias, y: bias, z: bias, w: 0)
            let clamp = CIFilter.colorClamp()
            clamp.inputImage = matrix.outputImage
            guard let leveled = clamp.outputImage else { return cutout }
            image = leveled.premultiplyingAlpha()
        }

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = image
        sharpen.sharpness = sharpness
        sharpen.radius = 1
        guard let output = sharpen.outputImage?.cropped(to: input.extent),
              let colorSpace = cutout.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let result = context.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: colorSpace)
        else { return cutout }
        return result
    }

    /// 256-bin Rec. 709 luminance histogram of the clearly opaque pixels, from a downsampled copy.
    static func luminanceHistogram(of image: CGImage) -> [Int] {
        var histogram = [Int](repeating: 0, count: 256)
        let longest = max(image.width, image.height)
        guard longest > 0 else { return histogram }
        let scale = min(1, Double(sampleMaxPixelSize) / Double(longest))
        let width = max(Int(Double(image.width) * scale), 1)
        let height = max(Int(Double(image.height) * scale), 1)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: buffer.baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return histogram }

        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3])
            guard alpha >= 192 else { continue }
            let luma = (0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1]) + 0.0722 * Double(pixels[offset + 2]))
                * 255 / alpha
            histogram[min(max(Int(luma.rounded()), 0), 255)] += 1
        }
        return histogram
    }
}
