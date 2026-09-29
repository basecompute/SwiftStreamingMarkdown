//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(AppKit)
import AppKit

extension NSAttributedString.Key {
  static let inlineCodeFill = Self("LocalInlineCodeFill")
  static let inlineCodeFont = Self("LocalInlineCodeFont")
  static let inlineCodePadding = Self("LocalInlineCodePadding")
}

/// Decoration belongs to the view's storage. The parsed document keeps its
/// original characters, so document export and accessibility remain unchanged.
enum InlineCodeStyle {
  static func padded(_ source: NSAttributedString) -> NSMutableAttributedString {
    let result = NSMutableAttributedString(attributedString: source)
    let full = NSRange(location: 0, length: source.length)
    var runs: [NSRange] = []
    source.enumerateAttribute(.inlineCodeFill, in: full) { value, range, _ in
      if value != nil { runs.append(range) }
    }
    for range in runs.reversed() {
      var attributes = source.attributes(at: range.location, effectiveRange: nil)
      let font = attributes[.font] as? NSFont ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
      let metrics = InlineCodeMetrics(font: font)
      result.addAttribute(.inlineCodeFont, value: font, range: range)
      attributes[.inlineCodeFont] = font
      // Reserve the same 0.4em on both boundaries. Wrapped fragments use the
      // container gutter; every background is drawn from content bounds + 0.4em.
      attributes[.inlineCodePadding] = true
      attributes[.kern] = metrics.horizontalPadding - ("\u{00A0}" as NSString).size(withAttributes: [.font: font]).width
      let spacer = NSAttributedString(string: "\u{00A0}", attributes: attributes)
      result.insert(spacer, at: NSMaxRange(range))
      result.insert(spacer, at: range.location)
    }
    return result
  }

  static func unpadded(_ source: NSAttributedString) -> NSAttributedString {
    let result = NSMutableAttributedString(attributedString: source)
    source.enumerateAttribute(.inlineCodePadding, in: NSRange(location: 0, length: source.length),
                              options: .reverse) { value, range, _ in
      if (value as? Bool) == true { result.deleteCharacters(in: range) }
    }
    return result
  }
}

#endif
