//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(AppKit)
import AppKit

/// Font-relative decoration, independent of paragraph leading and glyph ink.
/// Keep the original code font even when TextKit substitutes an emoji font.
struct InlineCodeMetrics {
  let font: NSFont
  var horizontalPadding: CGFloat { font.pointSize * 0.4 }
  var verticalPadding: CGFloat { font.pointSize * 0.2 }
  var cornerRadius: CGFloat { font.pointSize * 0.25 }
  var ascent: CGFloat { font.ascender + verticalPadding }
  var descent: CGFloat { -font.descender + verticalPadding }
  var height: CGFloat { ascent + descent }
}

#endif
