//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import iosMath
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - LatexAttachmentData Color Resolution

extension LatexAttachmentData {
  var resolvedTextColor: MDColor {
    let fallback = MDColor(Color.Theme.Foreground.Primary.Primary750)
    #if canImport(UIKit)
    guard let lightColor = UIColor(hex: lightTextColor),
          let darkColor = UIColor(hex: darkTextColor) else {
      return fallback
    }
    return UIColor { trait in
      trait.userInterfaceStyle == .dark ? darkColor : lightColor
    }
    #elseif canImport(AppKit)
    guard let lightColor = NSColor(hex: lightTextColor),
          let darkColor = NSColor(hex: darkTextColor) else {
      return fallback
    }
    return NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return isDark ? darkColor : lightColor
    }
    #endif
  }
}

// MARK: - Latex View Provider

final class LatexViewProvider: NSTextAttachmentViewProvider {
  private let latex: String
  private let fontSize: CGFloat
  private let textColor: MDColor
  private static let jsonDecoder = JSONDecoder()

  private struct DecodedAttachment {
    var latex: String = ""
    var fontSize: CGFloat = Typography.base.mdFont.pointSize
    var textColor: MDColor = MDColor(Color.Theme.Foreground.Primary.Primary750)
  }

  #if canImport(UIKit)
  required override init(textAttachment attachment: NSTextAttachment,
                         parentView: UIView?,
                         textLayoutManager: NSTextLayoutManager?,
                         location: any NSTextLocation) {
    let decoded = Self.decode(attachment: attachment)
    (latex, fontSize, textColor) = (decoded.latex, decoded.fontSize, decoded.textColor)
    super.init(textAttachment: attachment, parentView: parentView,
               textLayoutManager: textLayoutManager, location: location)
    tracksTextAttachmentViewBounds = true
  }
  #elseif canImport(AppKit)
  required override init(textAttachment attachment: NSTextAttachment,
                         parentView: NSView?,
                         textLayoutManager: NSTextLayoutManager?,
                         location: any NSTextLocation) {
    let decoded = Self.decode(attachment: attachment)
    (latex, fontSize, textColor) = (decoded.latex, decoded.fontSize, decoded.textColor)
    super.init(textAttachment: attachment, parentView: parentView,
               textLayoutManager: textLayoutManager, location: location)
    tracksTextAttachmentViewBounds = true
  }
  #endif

  private static func decode(attachment: NSTextAttachment) -> DecodedAttachment {
    var result = DecodedAttachment()
    if let data = attachment.contents,
       let attachmentData = try? jsonDecoder.decode(LatexAttachmentData.self, from: data) {
      result.latex = attachmentData.latex
      result.fontSize = attachmentData.fontSize
      result.textColor = attachmentData.resolvedTextColor
    }
    return result
  }

  override func loadView() {
    let label = MTMathUILabel()
    label.latex = latex
    label.textColor = textColor
    label.displayErrorInline = false
    label.fontSize = fontSize
    label.setContentHuggingPriority(.defaultHigh, for: .vertical)
    self.view = label

    // TextKit 1 (the AppKit NSTextView path) takes an attachment's
    // vertical placement from NSTextAttachment.bounds, not from the
    // provider's attachmentBounds override — with the default y = 0 the
    // label's BOTTOM sat on the text baseline and any formula with
    // depth (fractions, subscripts) floated by exactly its descent.
    // Typeset now and encode the true baseline into the bounds.
    let size = label.intrinsicContentSize
    label.frame = CGRect(origin: .zero, size: size)
    #if canImport(UIKit)
    label.layoutIfNeeded()
    #elseif canImport(AppKit)
    label.layoutSubtreeIfNeeded()
    if let display = label.displayList {
      let descent = display.descent.rounded(.up) + 1.0
      let ascent = display.ascent.rounded(.up)
      // Reserve the formula's depth in the line box…
      textAttachment?.bounds = CGRect(x: 0, y: -descent,
                                      width: size.width.rounded(.up),
                                      height: ascent + descent)
      // …and place the glyphs on the baseline ourselves: AppKit's
      // TextKit 1 provider support pins the view's BOTTOM to the text
      // baseline whatever the bounds' y says, so the label hangs inside
      // a carrier view, shifted down by its descent. The carrier does
      // not clip, letting the depth draw below the carrier's bottom.
      let carrier = NSView(frame: CGRect(origin: .zero, size: size))
      // Exact, unrounded depth: the rounded/padded value above reserves
      // line space, but using it for the shift pushes the formula a
      // point-and-a-half low.
      label.frame.origin = CGPoint(x: 0, y: -display.descent)
      carrier.addSubview(label)
      self.view = carrier
    }
    #endif
  }

  override func attachmentBounds(for attributes: [NSAttributedString.Key: Any],
                                 location: any NSTextLocation,
                                 textContainer: NSTextContainer?,
                                 proposedLineFragment: CGRect,
                                 position: CGPoint) -> CGRect {
    guard let mathLabel = view as? MTMathUILabel else {
      return .zero
    }
    #if canImport(UIKit)
    mathLabel.sizeToFit()
    mathLabel.layoutIfNeeded()
    let size = mathLabel.bounds.size
    #elseif canImport(AppKit)
    let size = mathLabel.intrinsicContentSize
    mathLabel.layoutSubtreeIfNeeded()
    #endif
    // The display list knows the formula's true baseline: placing the
    // attachment at y = -descent puts the math baseline exactly on the
    // text baseline. Fall back to cap-height centering only when the
    // label has not typeset yet.
    if let display = mathLabel.displayList {
      let ascent = display.ascent.rounded(.up)
      let descent = display.descent.rounded(.up) + 1.0
      return CGRect(x: 0, y: -descent,
                    width: size.width.rounded(.up),
                    height: ascent + descent)
    }
    let height = size.height.rounded(.up) + 1.0
    let font = attributes[.font] as? MDFont ?? MDFont.systemFont(ofSize: fontSize)
    let yOffset = (font.capHeight - height) / 2.0
    return CGRect(x: 0, y: yOffset, width: size.width.rounded(.up), height: height)
  }
}
