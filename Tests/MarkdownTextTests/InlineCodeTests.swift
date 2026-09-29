//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(AppKit)
import AppKit
import XCTest
@testable import SwiftStreamingMarkdown

final class InlineCodeTests: XCTestCase {
  func testPaddingDoesNotChangeExportedUnicodeOrWhitespace() throws {
    let link = try XCTUnwrap(URL(string: "https://example.com"))
    let source = NSMutableAttributedString(string: "Use α/😀\u{00A0}file.swift, then continue.", attributes: [.font: NSFont.systemFont(ofSize: 13)])
    let range = (source.string as NSString).range(of: "α/😀\u{00A0}file.swift")
    source.addAttributes([.inlineCodeFill: NSColor.gray,
                          .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                          .link: link], range: range)
    let padded = InlineCodeStyle.padded(source)
    XCTAssertEqual(padded.length, source.length + 2)
    let exported = InlineCodeStyle.unpadded(padded)
    XCTAssertEqual(exported.string, source.string)
    XCTAssertEqual(exported.attribute(.link, at: range.location, effectiveRange: nil) as? URL,
                   URL(string: "https://example.com"))
    // Selection starting inside the chip still preserves user-authored NBSP.
    let partial = padded.attributedSubstring(from: NSRange(location: range.location + 2, length: range.length))
    XCTAssertFalse(InlineCodeStyle.unpadded(partial).string.hasSuffix("\u{00A0}"))
    XCTAssertTrue(InlineCodeStyle.unpadded(partial).string.contains("\u{00A0}"))
  }

  func testPlainTextIsUnchanged() {
    let source = NSAttributedString(string: "ordinary text\u{00A0}with a real space")
    XCTAssertTrue(InlineCodeStyle.padded(source).isEqual(to: source))
  }

  @MainActor
  func testQuoteAndTableKeepInlineCodeAttributes() async {
    let document = await MarkdownParserImpl().parse(
      text: "> Use `git status`.\n\n| Key | Value |\n|---|---|\n| `timeout` | `30` |",
      config: .default)
    var foundQuote = false
    var foundTable = false
    for block in document.renderables {
      if case .blockQuote(_, let item) = block,
         case .nested(let children) = item.quoteType,
         case .attributedText(let text, _) = children.first {
        let range = (text.string as NSString).range(of: "git status")
        XCTAssertNotNil(text.attribute(.inlineCodeFill, at: range.location, effectiveRange: nil))
        XCTAssertEqual(text.string, "Use git status.")
        foundQuote = true
      }
      if case .table(_, let headers, let rows, let alignments, let rawMarkdown) = block {
        let table = TableView(headings: headers, rows: rows, alignments: alignments, rawMarkdown: rawMarkdown)
        if case .containsAttachment(let content) = table.rows[0][0] {
          XCTAssertEqual(content.string, "timeout")
          XCTAssertNotNil(content.attribute(.inlineCodeFill, at: 0, effectiveRange: nil))
          foundTable = true
        }
      }
    }
    XCTAssertTrue(foundQuote)
    XCTAssertTrue(foundTable)
  }

  func testQuotedCitationExportPreservesTitles() async {
    let source = "> Use `git status` and [9F742443](http://example.com?citationMarker=9F742443&citationTitle=Microsoft&citationA11yValue=Microsoft)."
    let document = await MarkdownParserImpl().parse(text: source, config: .default)
    XCTAssertTrue(document.plainText.contains("git status"))
    XCTAssertTrue(document.plainText.contains("Microsoft"))
    XCTAssertFalse(document.plainText.contains("9F742443"))
    XCTAssertFalse(document.plainText.contains("\u{FFFC}"))
  }

  @MainActor
  func testNarrowLayoutAndNativeCopy() throws {
    let source = NSMutableAttributedString(string: "path/with/a/very/long/component/file.swift", attributes: [
      .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
      .inlineCodeFill: NSColor.gray])
    let view = ParagraphNSView()
    view.setParagraphContents(source, animatedByWord: false)
    let narrow = view.measureSize(fittingWidth: 90)
    let wide = view.measureSize(fittingWidth: 500)
    XCTAssertGreaterThan(narrow.height, wide.height)
    XCTAssertLessThanOrEqual(narrow.width, 90)
    view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    XCTAssertTrue(view.writeSelection(to: pasteboard, type: .string))
    XCTAssertEqual(pasteboard.string(forType: .string), source.string)
    XCTAssertEqual(view.accessibilityLabel(), source.string)
    XCTAssertEqual(view.paragraphContents.string, source.string)
    XCTAssertTrue(view.writeSelection(to: pasteboard, type: .rtf))
    let exportedRTF = try NSAttributedString(data: XCTUnwrap(pasteboard.data(forType: .rtf)),
      options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
    XCTAssertEqual(exportedRTF.string, source.string)
    let nextSnapshot = NSMutableAttributedString(attributedString: source)
    nextSnapshot.append(NSAttributedString(string: " next"))
    view.setParagraphContents(nextSnapshot, animatedByWord: true)
    view.finishTextAnimations()
    XCTAssertEqual(InlineCodeStyle.unpadded(try XCTUnwrap(view.textStorage)).string, nextSnapshot.string)
  }
}

extension InlineCodeTests {
  private func fixture(code: String = "git status", surroundingSize: CGFloat = 13,
                       lineSpacing: CGFloat = 0, codeSize: CGFloat = 12,
                       width: CGFloat = 500) -> (NSTextStorage, InlineCodeLayoutManager, NSTextContainer) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = lineSpacing
    let font = NSFont.monospacedSystemFont(ofSize: codeSize, weight: .regular)
    let source = NSMutableAttributedString(string: "Before ", attributes: [
      .font: NSFont.systemFont(ofSize: surroundingSize), .paragraphStyle: paragraph])
    source.append(NSAttributedString(string: code, attributes: [
      .font: font, .inlineCodeFill: NSColor.gray, .paragraphStyle: paragraph]))
    source.append(NSAttributedString(string: " after\nNext line", attributes: [
      .font: NSFont.systemFont(ofSize: surroundingSize), .paragraphStyle: paragraph]))
    let storage = NSTextStorage(attributedString: InlineCodeStyle.padded(source))
    let manager = InlineCodeLayoutManager()
    let container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = InlineCodeMetrics(font: font).horizontalPadding
    storage.addLayoutManager(manager)
    manager.addTextContainer(container)
    manager.ensureLayout(for: container)
    return (storage, manager, container)
  }

  func testCodeHeightAndBaselineIgnoreSurroundingFontsAndLineSpacing() throws {
    let (referenceStorage, reference, _) = fixture()
    let expectedHeight = try withExtendedLifetime(referenceStorage) {
      try XCTUnwrap(reference.inlineCodeBackgrounds(forGlyphRange: NSRange(location: 0, length: reference.numberOfGlyphs)).first).rect.height
    }
    // Reproduces the original 17.3 / 22.3 / 30.3 pt inconsistency. Content with
    // descenders, accents, emoji or font fallback must not resize the decoration.
    for size: CGFloat in [11, 13, 24, 32] {
      for spacing: CGFloat in [0, 5, 18] {
        for code in ["x", "git status", "gyjp", "éàÎ", "git 😀", "設定"] {
          let (storage, manager, _) = fixture(code: code, surroundingSize: size, lineSpacing: spacing)
          let backgrounds = manager.inlineCodeBackgrounds(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs))
          XCTAssertEqual(backgrounds.count, 1)
          guard let background = backgrounds.first else { continue }
          XCTAssertEqual(background.rect.height, expectedHeight, accuracy: 0.001, "size=\(size), spacing=\(spacing), code=\(code)")
          // Seven prefix characters plus the opening layout spacer.
          let glyph = manager.glyphIndexForCharacter(at: 8)
          let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
          let baseline = line.minY + manager.location(forGlyphAt: glyph).y
          let codeFont = try XCTUnwrap(storage.attribute(.inlineCodeFont, at: 8, effectiveRange: nil) as? NSFont)
          XCTAssertEqual(baseline - background.rect.minY - codeFont.ascender, 2.4, accuracy: 0.001)
          XCTAssertEqual(background.rect.maxY - baseline + codeFont.descender, 2.4, accuracy: 0.001)
        }
      }
    }
  }

  func testWrappedFragmentsHaveConsistentPaddingAndStayInsideLayout() throws {
    let code = "path/to/a/very/long/component/with/no/spaces/file.swift"
    for size: CGFloat in [10, 12, 18] {
      for width: CGFloat in [95, 150, 280] {
        let (storage, manager, container) = fixture(code: code, lineSpacing: 5, codeSize: size, width: width)
        let backgrounds = manager.inlineCodeBackgrounds(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs))
        XCTAssertGreaterThan(backgrounds.count, 1)
        let expectedHeight = try XCTUnwrap(backgrounds.first).rect.height
        let used = manager.usedRect(for: container)
        for background in backgrounds {
          XCTAssertEqual(background.rect.height, expectedHeight, accuracy: 0.001)
          XCTAssertGreaterThanOrEqual(background.rect.minX, -0.001)
          XCTAssertLessThanOrEqual(background.rect.maxX, width + 0.001)
          XCTAssertGreaterThanOrEqual(background.rect.minY, -0.001)
          XCTAssertLessThanOrEqual(background.rect.maxY, used.maxY + 0.001)
        }
        XCTAssertEqual(InlineCodeStyle.unpadded(storage).string, "Before \(code) after\nNext line")
      }
    }
  }

  @MainActor
  func testSingleLineCodeIsNotClippedAndMeasuredHeightMatchesDisplay() throws {
    for size: CGFloat in [10, 12, 18] {
      let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
      let view = ParagraphNSView()
      view.inlineCodeFont = font
      view.setParagraphContents(NSMutableAttributedString(string: "x", attributes: [
        .font: font, .inlineCodeFill: NSColor.gray]), animatedByWord: false)
      let measured = view.measureSize(fittingWidth: 100)
      view.frame = NSRect(x: 0, y: 0, width: 100, height: measured.height)
      let manager = try XCTUnwrap(view.layoutManager as? InlineCodeLayoutManager)
      let container = try XCTUnwrap(view.textContainer)
      manager.ensureLayout(for: container)
      let background = try XCTUnwrap(manager.inlineCodeBackgrounds(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)).first)
      XCTAssertGreaterThanOrEqual(background.rect.minY, -0.001)
      XCTAssertLessThanOrEqual(background.rect.maxY, measured.height + 0.001)
      XCTAssertEqual(manager.usedRect(for: container).height.rounded(.up), measured.height)
    }
  }
}
#endif
