//
//  AvatarCropView.swift
//  Drive
//
//  Profile photo crop (Profile → photo). v2 styling: flat 2 pt rim, V2 type
//  and tokens, always dark like the system's own photo editors.
//
import SwiftUI
import UIKit

struct AvatarCropView: View {
    let image: UIImage
    let onSave: (Data) -> Void
    let onCancel: () -> Void

    private let cropDiameter: CGFloat = 280

    // Scale: 1.0 = fill crop circle. User can zoom in further.
    @State private var scale: CGFloat     = 1.0
    @State private var baseScale: CGFloat = 1.0
    @State private var offset: CGSize     = .zero
    @State private var lastOffset: CGSize = .zero

    // The scale that makes the image cover the crop circle exactly.
    // Guard against 0-dimension images to prevent NaN frame values crashing SwiftUI.
    private var fillScale: CGFloat {
        let w = max(image.size.width, 1)
        let h = max(image.size.height, 1)
        return max(cropDiameter / w, cropDiameter / h)
    }

    private var displayWidth: CGFloat  { image.size.width  * fillScale * scale }
    private var displayHeight: CGFloat { image.size.height * fillScale * scale }

    var body: some View {
        ZStack {
            // A photo editor is dark in either appearance, like the system's.
            V2.fixed(0x000000).ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Nav bar
                HStack(spacing: 12) {
                    Button { onCancel() } label: {
                        Text("Cancel")
                            .font(V2Type.body)
                            .foregroundStyle(V2.label)
                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                    Text("Move and Scale")
                        .font(V2Type.headline)
                        .foregroundStyle(V2.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Button { saveImage() } label: {
                        Text("Choose")
                            .font(V2Type.headline)
                            .foregroundStyle(V2.tint)
                            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(1)
                }
                .padding(.horizontal, V2.margin)
                .padding(.top, 8)
                .padding(.bottom, 8)

                Spacer()

                // ── Crop circle: flat 2 pt rim, no glow
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: displayWidth, height: displayHeight)
                        .offset(offset)
                }
                .frame(width: cropDiameter, height: cropDiameter)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(V2.label, lineWidth: 2)
                )
                .contentShape(Circle())
                .gesture(
                    SimultaneousGesture(
                        DragGesture()
                            .onChanged { v in
                                offset = clampOffset(CGSize(
                                    width:  lastOffset.width  + v.translation.width,
                                    height: lastOffset.height + v.translation.height
                                ))
                            }
                            .onEnded { _ in lastOffset = offset },
                        MagnificationGesture()
                            .onChanged { v in
                                scale = max(1.0, baseScale * v)
                            }
                            .onEnded { v in
                                baseScale = max(1.0, baseScale * v)
                                offset    = clampOffset(offset)
                                lastOffset = offset
                            }
                    )
                )
                .accessibilityElement()
                .accessibilityLabel("Photo preview")
                .accessibilityHint("Drag to move it, pinch to zoom.")

                Spacer()

                Text("Drag and pinch to adjust")
                    .font(V2Type.footnote)
                    .foregroundStyle(V2.label2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, V2.margin)
                    .padding(.bottom, 44)
                    .accessibilityHidden(true)
            }
        }
        // Tokens resolve dark over the black backdrop whatever the app's appearance.
        .environment(\.colorScheme, .dark)
    }

    // Clamp pan so image edges never expose background inside the circle
    private func clampOffset(_ proposed: CGSize) -> CGSize {
        let maxX = max(0, (displayWidth  - cropDiameter) / 2)
        let maxY = max(0, (displayHeight - cropDiameter) / 2)
        return CGSize(
            width:  min(max(proposed.width,  -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func saveImage() {
        let outputPx: CGFloat = 400
        let ratio = outputPx / cropDiameter

        let imgW = displayWidth  * ratio
        let imgH = displayHeight * ratio
        let imgX = (outputPx - imgW) / 2 + offset.width  * ratio
        let imgY = (outputPx - imgH) / 2 + offset.height * ratio

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputPx, height: outputPx))
        let data = renderer.jpegData(withCompressionQuality: 0.92) { _ in
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: outputPx, height: outputPx)).addClip()
            image.draw(in: CGRect(x: imgX, y: imgY, width: imgW, height: imgH))
        }
        onSave(data)
    }
}
