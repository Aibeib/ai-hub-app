import SwiftUI

/// A deterministic WeChat-style swipe-to-delete row.
///
/// The previous ZStack implementation visually revealed the delete button, but SwiftUI
/// hit testing could still be captured by the offset content layer. This implementation
/// uses a single HStack: content + trailing delete button. The HStack itself is moved
/// left, so the delete button is physically in the tappable layout, not hidden behind
/// another layer.
struct SwipeToDeleteRow<Content: View>: View {
    let actionTitle: String
    var actionSystemImage: String = "trash"
    var actionTint: Color = DS.Palette.danger
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var horizontalOffset: CGFloat = 0
    @State private var isOpen = false

    private let actionWidth: CGFloat = 92
    private let fullSwipeThreshold: CGFloat = 150

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                content()
                    .frame(width: geometry.size.width, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isOpen {
                            close()
                        }
                    }

                VStack(spacing: 4) {
                    Image(systemName: actionSystemImage)
                        .font(.system(size: 15, weight: .semibold))
                    Text(actionTitle)
                        .font(DS.Typography.captionSmall.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .background(actionTint)
                .contentShape(Rectangle())
                .onTapGesture {
                    onDelete()
                }
            }
            .offset(x: horizontalOffset)
            .gesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onChanged { value in
                        let base = isOpen ? -actionWidth : 0
                        let proposed = base + value.translation.width
                        horizontalOffset = min(0, max(-actionWidth, proposed))
                    }
                    .onEnded { value in
                        let projected = horizontalOffset + value.predictedEndTranslation.width * 0.2
                        if projected < -fullSwipeThreshold {
                            withAnimation(.easeOut(duration: 0.14)) {
                                horizontalOffset = -geometry.size.width
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                                onDelete()
                            }
                        } else if projected < -actionWidth * 0.45 {
                            open()
                        } else {
                            close()
                        }
                    }
            )
        }
        .frame(height: 70)
        .clipped()
    }

    private func open() {
        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.88)) {
            horizontalOffset = -actionWidth
            isOpen = true
        }
    }

    private func close() {
        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.92)) {
            horizontalOffset = 0
            isOpen = false
        }
    }
}
