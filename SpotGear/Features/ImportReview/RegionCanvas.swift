import SwiftUI

/// The oriented photo drawn aspect-fit with draggable, resizable region frames.
struct RegionCanvas: View {
    let image: CGImage
    let regions: [RegionDraft]
    @Binding var selectedID: UUID?
    let onChange: (UUID, CropRect) -> Void

    @State private var preview: Preview?

    private struct Preview: Equatable {
        var regionID: UUID
        var crop: CropRect
    }

    var body: some View {
        GeometryReader { geometry in
            let fitted = ImageGeometry.aspectFitRect(
                imageSize: CGSize(width: image.width, height: image.height),
                in: geometry.size
            )
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityHidden(true)

                ForEach(regions) { region in
                    RegionOverlay(
                        region: region,
                        crop: preview?.regionID == region.id ? preview!.crop : region.crop,
                        fitted: fitted,
                        isSelected: region.id == selectedID,
                        onSelect: { selectedID = region.id },
                        onPreview: { preview = Preview(regionID: region.id, crop: $0) },
                        onCommit: { crop in
                            preview = nil
                            onChange(region.id, crop)
                        }
                    )
                }
            }
            .coordinateSpace(name: "regionCanvas")
        }
    }
}

private struct RegionOverlay: View {
    let region: RegionDraft
    let crop: CropRect
    let fitted: CGRect
    let isSelected: Bool
    let onSelect: () -> Void
    let onPreview: (CropRect) -> Void
    let onCommit: (CropRect) -> Void

    private static let step = RegionAdjustControls.step

    var body: some View {
        let rect = ImageGeometry.viewRect(for: crop, in: fitted)
        frameShape
            .frame(width: max(rect.width, 1), height: max(rect.height, 1))
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .highPriorityGesture(moveGesture)
            .overlay(alignment: .topLeading) {
                RegionNumberBadge(number: region.number, isSelected: isSelected)
                    .padding(4)
            }
            .overlay(alignment: .bottomTrailing) {
                if isSelected { resizeHandle }
            }
            .position(x: rect.midX, y: rect.midY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Car \(region.number)")
            .accessibilityIdentifier("regions.frame.\(region.number)")
            .accessibilityValue(Text(verbatim: crop.accessibilityDescription))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityAction(named: "Select to Edit", onSelect)
            .accessibilityAction(named: "Move Left") { onCommit(crop.moved(dx: -Self.step, dy: 0)) }
            .accessibilityAction(named: "Move Right") { onCommit(crop.moved(dx: Self.step, dy: 0)) }
            .accessibilityAction(named: "Move Up") { onCommit(crop.moved(dx: 0, dy: -Self.step)) }
            .accessibilityAction(named: "Move Down") { onCommit(crop.moved(dx: 0, dy: Self.step)) }
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onCommit(crop.resized(dWidth: Self.step, dHeight: Self.step))
                case .decrement: onCommit(crop.resized(dWidth: -Self.step, dHeight: -Self.step))
                @unknown default: break
                }
            }
    }

    @ViewBuilder
    private var frameShape: some View {
        if isSelected {
            Rectangle()
                .strokeBorder(Theme.gold, lineWidth: 3)
                .background(Theme.gold.opacity(0.12))
        } else {
            Rectangle()
                .strokeBorder(Color.white, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .shadow(color: .black.opacity(0.6), radius: 1)
        }
    }

    private var moveGesture: some Gesture {
        // The frame itself moves during a drag. Measuring in its local coordinates
        // feeds that movement back into the next translation and makes it jump.
        DragGesture(minimumDistance: 4, coordinateSpace: .named("regionCanvas"))
            .onChanged { value in
                onSelect()
                let delta = ImageGeometry.normalizedDelta(value.translation, in: fitted)
                onPreview(region.crop.moved(dx: delta.dx, dy: delta.dy))
            }
            .onEnded { value in
                let delta = ImageGeometry.normalizedDelta(value.translation, in: fitted)
                onCommit(region.crop.moved(dx: delta.dx, dy: delta.dy))
            }
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Theme.gold)
            .overlay(Rectangle().strokeBorder(Theme.night, lineWidth: 2))
            .frame(width: 20, height: 20)
            .frame(width: Spacing.minimumTapTarget, height: Spacing.minimumTapTarget)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("regionCanvas"))
                    .onChanged { value in
                        let delta = ImageGeometry.normalizedDelta(value.translation, in: fitted)
                        onPreview(region.crop.resizedFromBottomRight(dx: delta.dx, dy: delta.dy))
                    }
                    .onEnded { value in
                        let delta = ImageGeometry.normalizedDelta(value.translation, in: fitted)
                        onCommit(region.crop.resizedFromBottomRight(dx: delta.dx, dy: delta.dy))
                    }
            )
            .accessibilityHidden(true)
    }
}
