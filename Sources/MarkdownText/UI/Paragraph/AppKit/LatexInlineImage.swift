//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(AppKit)
import AppKit
import iosMath

/// Inline math on macOS renders as a plain image attachment.
///
/// The view-provider route is TextKit 2 machinery; the AppKit paragraph
/// views are TextKit 1, whose compatibility layer half-supports provider
/// views (it pins the view's bottom to the text baseline regardless of
/// the attachment bounds, and composites non-flipped subviews
/// inconsistently). Image attachments are the classic TextKit 1 path:
/// bounds are honored exactly, so the formula's baseline can be placed
/// on the text baseline and its depth reserved in the line box.
enum LatexInlineImage {
  /// Builds an attachment whose image draws the formula at the given
  /// font size, resolving light/dark text color at draw time.
  static func attachment(latex: String, fontSize: CGFloat,
                         lightColor: NSColor, darkColor: NSColor) -> NSTextAttachment? {
    let label = MTMathUILabel()
    // Text style: standard inline rendering (compact scripts), matching
    // how LaTeX itself sets math inside a paragraph.
    label.mode = .text  // inline style: compact scripts, like LaTeX in-paragraph math
    label.latex = latex
    label.fontSize = fontSize
    label.displayErrorInline = false
    let size = label.intrinsicContentSize
    label.frame = CGRect(origin: .zero, size: size)
    label.layoutSubtreeIfNeeded()
    guard let display = label.displayList else { return nil }

    let ascent = display.ascent.rounded(.up)
    let descent = display.descent.rounded(.up)
    let width = max(size.width.rounded(.up), 1)
    let height = max(ascent + descent, 1)

    let image = NSImage(size: NSSize(width: width, height: height),
                        flipped: false) { _ in
      guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
      let appearance = NSAppearance.currentDrawing()
      let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      display.textColor = dark ? darkColor : lightColor
      // Bottom-left origin: the math baseline sits `descent` above the
      // image bottom, mirroring the attachment bounds below.
      display.position = CGPoint(x: 0, y: descent)
      display.draw(ctx)
      return true
    }

    let attachment = NSTextAttachment()
    attachment.image = image
    attachment.bounds = CGRect(x: 0, y: -descent, width: width, height: height)
    return attachment
  }
}
#endif
