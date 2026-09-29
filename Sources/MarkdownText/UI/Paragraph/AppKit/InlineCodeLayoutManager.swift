//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(AppKit)
import AppKit

final class InlineCodeLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
  struct Background {
    let rect: NSRect
    let fill: NSColor
    let cornerRadius: CGFloat
  }

  override init() {
    super.init()
    delegate = self
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    delegate = self
  }

  /// Reserve space only where a decorated run would protrude above/below the
  /// line. Paragraph spacing stays outside the background. This also keeps the
  /// first/last line from clipping without adding insets to every paragraph.
  func layoutManager(_ layoutManager: NSLayoutManager,
                     shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                     lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
                     baselineOffset: UnsafeMutablePointer<CGFloat>,
                     in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
    guard let storage = textStorage else { return false }
    let characters = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    storage.enumerateAttribute(.inlineCodeFont, in: characters) { value, range, _ in
      guard let font = value as? NSFont else { return }
      let metrics = InlineCodeMetrics(font: font)
      let offset = (storage.attribute(.baselineOffset, at: range.location, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0
      ascent = max(ascent, metrics.ascent + offset)
      descent = max(descent, metrics.descent - offset)
    }
    guard ascent > 0 else { return false }
    let extraAbove = max(0, ascent - baselineOffset.pointee)
    let extraBelow = max(0, descent - (lineFragmentUsedRect.pointee.height - baselineOffset.pointee))
    guard extraAbove + extraBelow > 0 else { return false }
    baselineOffset.pointee += extraAbove
    lineFragmentRect.pointee.size.height += extraAbove + extraBelow
    lineFragmentUsedRect.pointee.size.height += extraAbove + extraBelow
    return true
  }

  /// Shared by drawing and geometry regression tests. Height is always the code
  /// font's ascent + descent + 0.4em, never the enclosing line's bounding height.
  func inlineCodeBackgrounds(forGlyphRange visible: NSRange) -> [Background] {
    guard let storage = textStorage, storage.length > 0, visible.length > 0 else { return [] }
    let characters = characterRange(forGlyphRange: visible, actualGlyphRange: nil)
    var backgrounds: [Background] = []
    storage.enumerateAttribute(.inlineCodeFill, in: characters) { value, range, _ in
      guard let fill = value as? NSColor else { return }
      var codeRange = NSRange()
      _ = storage.attribute(.inlineCodeFill, at: range.location,
                            longestEffectiveRange: &codeRange,
                            in: NSRange(location: 0, length: storage.length))
      // Measure actual code, excluding our invisible layout spacers. Applying
      // padding once here gives both wrapped and unwrapped fragments the same box.
      while codeRange.length > 0,
            storage.attribute(.inlineCodePadding, at: codeRange.location, effectiveRange: nil) as? Bool == true {
        codeRange.location += 1
        codeRange.length -= 1
      }
      while codeRange.length > 0,
            storage.attribute(.inlineCodePadding, at: NSMaxRange(codeRange) - 1, effectiveRange: nil) as? Bool == true {
        codeRange.length -= 1
      }
      guard codeRange.length > 0,
            let font = storage.attribute(.inlineCodeFont, at: codeRange.location, effectiveRange: nil) as? NSFont else { return }
      let metrics = InlineCodeMetrics(font: font)
      let glyphs = glyphRange(forCharacterRange: codeRange, actualCharacterRange: nil)
      enumerateLineFragments(forGlyphRange: NSIntersectionRange(glyphs, visible)) { lineRect, _, container, line, _ in
        let fragment = NSIntersectionRange(glyphs, line)
        let contentBounds = self.boundingRect(forGlyphRange: fragment, in: container)
        let baseline = lineRect.minY + self.location(forGlyphAt: fragment.location).y
        let rect = NSRect(x: contentBounds.minX - metrics.horizontalPadding,
                          y: baseline - metrics.ascent,
                          width: contentBounds.width + 2 * metrics.horizontalPadding,
                          height: metrics.height)
        backgrounds.append(Background(rect: rect, fill: fill, cornerRadius: metrics.cornerRadius))
      }
    }
    return backgrounds
  }

  override func drawBackground(forGlyphRange visible: NSRange, at origin: NSPoint) {
    for background in inlineCodeBackgrounds(forGlyphRange: visible) {
      let rect = background.rect.offsetBy(dx: origin.x, dy: origin.y)
      let path = NSBezierPath(roundedRect: rect, xRadius: background.cornerRadius,
                             yRadius: background.cornerRadius)
      background.fill.setFill()
      path.fill()
    }
    // Native selection is painted over the fill, so selected code stays legible.
    super.drawBackground(forGlyphRange: visible, at: origin)
  }
}
#endif
