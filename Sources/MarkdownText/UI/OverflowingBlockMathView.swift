//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import SwiftUI

/// Display math wider than its container: scrolls horizontally, with a
/// trailing chevron that signals the hidden part and scrolls to it. A
/// clipped formula gives no hint that anything is cut off, and the
/// system scroller only appears while scrolling.
struct OverflowingBlockMathView: View {
  let latex: String
  let color: Color

  @State private var containerWidth: CGFloat = 0
  @State private var contentTrailingEdge: CGFloat = 0

  private var hasHiddenTrailingContent: Bool {
    contentTrailingEdge > containerWidth + 1
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal) {
        BlockMathView(latex: latex, color: color)
          .padding(.vertical, 6)
          .padding(.trailing, 32)
          .background(
            GeometryReader { geometry in
              Color.clear.preference(
                key: TrailingEdgeKey.self,
                value: geometry.frame(in: .named(Self.scrollSpace)).maxX)
            }
          )
          .id(Self.endAnchor)
      }
      .coordinateSpace(name: Self.scrollSpace)
      .scrollIndicators(.visible)
      .background(
        GeometryReader { geometry in
          Color.clear.preference(key: ContainerWidthKey.self, value: geometry.size.width)
        }
      )
      .onPreferenceChange(TrailingEdgeKey.self) { contentTrailingEdge = $0 }
      .onPreferenceChange(ContainerWidthKey.self) { containerWidth = $0 }
      .overlay(alignment: .trailing) {
        if hasHiddenTrailingContent {
          Button {
            withAnimation { proxy.scrollTo(Self.endAnchor, anchor: .trailing) }
          } label: {
            Image(systemName: "chevron.right")
              .font(.caption.weight(.bold))
              .foregroundStyle(color)
              .padding(6)
              .background(.ultraThinMaterial, in: Circle())
          }
          .buttonStyle(.plain)
          .padding(.trailing, 4)
          .accessibilityLabel("Scroll to the end of the formula")
          .transition(.opacity)
        }
      }
    }
  }

  private static let scrollSpace = "OverflowingBlockMathView"
  private static let endAnchor = "end"

  private struct TrailingEdgeKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
  }

  private struct ContainerWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
  }
}
