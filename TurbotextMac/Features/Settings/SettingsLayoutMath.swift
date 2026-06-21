import Foundation
import SwiftUI

enum PopoverSizing {
    static func clampedHeight(
        contentHeight: CGFloat,
        chrome: CGFloat,
        screenHeight: CGFloat,
        minHeight: CGFloat,
        screenMarginFraction: CGFloat
    ) -> CGFloat {
        let desired = contentHeight + chrome
        let maxAllowed = screenHeight * screenMarginFraction
        return min(max(desired, minHeight), maxAllowed)
    }

    static func clampedWidth(contentWidth: CGFloat, minWidth: CGFloat, maxWidth: CGFloat) -> CGFloat {
        min(max(contentWidth, minWidth), maxWidth)
    }
}

enum AutoGrowingTextHeight {
    static func clamped(measured: CGFloat, minHeight: CGFloat, maxHeight: CGFloat) -> CGFloat {
        min(max(measured, minHeight), maxHeight)
    }
}

private struct TextMeasurementHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// TextEditor that grows with its content between minHeight and maxHeight,
/// then scrolls internally beyond maxHeight (TextEditor's native scroll behavior).
struct AutoGrowingTextEditor: View {
    @Binding var text: String
    var font: Font
    var minHeight: CGFloat
    var maxHeight: CGFloat

    @State private var measuredHeight: CGFloat = 0

    private var isScrollable: Bool {
        measuredHeight > maxHeight
    }

    var body: some View {
        TextEditor(text: $text)
            .font(font)
            .frame(height: AutoGrowingTextHeight.clamped(measured: measuredHeight, minHeight: minHeight, maxHeight: maxHeight))
            .scrollDisabled(!isScrollable)
            .scrollIndicators(isScrollable ? .automatic : .hidden)
            .background(
                Text(text.isEmpty ? " " : text)
                    .font(font)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 5)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(key: TextMeasurementHeightKey.self, value: geometry.size.height)
                        }
                    )
            )
            .onPreferenceChange(TextMeasurementHeightKey.self) { measuredHeight = $0 }
    }
}
