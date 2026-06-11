//
//  AvatarCropView.swift
//  Drive
//
import SwiftUI

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
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Nav bar
                HStack {
                    Button("Cancel") { onCancel() }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Move & Scale")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Button("Use Photo") { saveImage() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DS.Colors.accent)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Spacer()

                // ── Crop circle
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
                        .stroke(DS.Colors.accent.opacity(0.85), lineWidth: 2)
                        .shadow(color: DS.Colors.accent.opacity(0.5), radius: 10)
                )
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

                Spacer()

                Text("Drag and pinch to adjust")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.45))
                    .padding(.bottom, 44)
            }
        }
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
