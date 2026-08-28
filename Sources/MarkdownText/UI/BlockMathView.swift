//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import SwiftUI
import iosMath

extension BlockMathView {
  /// Whether iosMath can parse this source at all — a failed parse
  /// renders an empty label, so callers show the raw source instead.
  static func canTypeset(_ latex: String) -> Bool {
    // The throwing bridge returns partial lists alongside errors, so a
    // failed parse can look like success; the instance API is explicit.
    let builder = MTMathListBuilder(string: latex)
    let list = builder.build()
    return list != nil && builder.error == nil
  }
}

#if canImport(UIKit)

struct BlockMathView: UIViewRepresentable {
  let latex: String
  let color: Color
  let pointSize: CGFloat

  init(latex: String, color: Color = Color.Theme.Foreground.Primary.Primary750, pointSize: CGFloat = Typography.base.mdFont.pointSize) {
    self.latex = latex
    self.color = color
    self.pointSize = pointSize
  }

  func makeUIView(context: Context) -> MTMathUILabel {
    let label = MTMathUILabel()
    label.latex = latex
    label.textColor = UIColor(color)
    label.displayErrorInline = false
    label.fontSize = pointSize
    label.setContentHuggingPriority(.defaultHigh, for: .vertical)
    return label
  }

  func updateUIView(_ uiView: MTMathUILabel, context: Context) {
    uiView.textColor = UIColor(color)
    uiView.latex = latex
  }

  func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTMathUILabel, context: Context) -> CGSize? {
    uiView.sizeToFit()
    let size = uiView.bounds.size
    // It's a known issue that MTMathUILabel may be cut off for some short statement. Manually add 1 to the height fix it.
    return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up) + 1)
  }
}

#elseif canImport(AppKit)

struct BlockMathView: NSViewRepresentable {
  let latex: String
  let color: Color
  let pointSize: CGFloat

  init(latex: String, color: Color = Color.Theme.Foreground.Primary.Primary750, pointSize: CGFloat = Typography.base.mdFont.pointSize) {
    self.latex = latex
    self.color = color
    self.pointSize = pointSize
  }

  func makeNSView(context: Context) -> MTMathUILabel {
    let label = MTMathUILabel()
    label.latex = latex
    label.textColor = NSColor(color)
    label.displayErrorInline = false
    label.fontSize = pointSize
    label.setContentHuggingPriority(.defaultHigh, for: .vertical)
    return label
  }

  func updateNSView(_ nsView: MTMathUILabel, context: Context) {
    nsView.textColor = NSColor(color)
    nsView.latex = latex
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: MTMathUILabel, context: Context) -> CGSize? {
    let size = nsView.intrinsicContentSize
    return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up) + 1)
  }
}

#endif
