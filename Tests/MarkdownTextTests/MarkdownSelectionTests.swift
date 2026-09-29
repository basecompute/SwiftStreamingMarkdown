//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(AppKit)
import AppKit
import SwiftUI
import XCTest
@testable import SwiftStreamingMarkdown

@MainActor
final class MarkdownSelectionTests: XCTestCase {
  private func window() -> NSWindow {
    _ = NSApplication.shared
    return NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
                    styleMask: [.borderless], backing: .buffered, defer: false)
  }

  private func paragraph(_ text: String, y: CGFloat, window: NSWindow,
                         selection: MarkdownSelectionCoordinator, x: CGFloat = 0) -> ParagraphNSView {
    let view = ParagraphNSView()
    view.setParagraphContents(NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14)]),
                              animatedByWord: false)
    view.frame = NSRect(x: x, y: y, width: 200, height: 30)
    window.contentView?.addSubview(view)
    view.selectionCoordinator = selection
    return view
  }

  private func select(_ range: NSRange, in view: ParagraphNSView, selection: MarkdownSelectionCoordinator) {
    view.setSelectedRange(range)
    selection.adoptNativeSelection(in: view)
  }

  func testForwardAndReversePartialSelectionAndCopy() throws {
    let window = window()
    let selection = MarkdownSelectionCoordinator()
    let first = paragraph("First paragraph", y: 400, window: window, selection: selection)
    let second = paragraph("Second paragraph", y: 300, window: window, selection: selection)
    select(NSRange(location: 6, length: 0), in: first, selection: selection)
    selection.extend(to: 15 + 2 + 6)
    XCTAssertEqual(selection.selectedText?.string, "paragraph\n\nSecond")
    XCTAssertEqual(first.selectedRange(), NSRange(location: 6, length: 9))
    XCTAssertEqual(second.selectedRange(), NSRange(location: 0, length: 6))
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    XCTAssertTrue(first.writeSelection(to: board, type: .string))
    XCTAssertEqual(board.string(forType: .string), "paragraph\n\nSecond")
    select(NSRange(location: 6, length: 0), in: second, selection: selection)
    selection.extend(to: 6)
    XCTAssertEqual(selection.selectedText?.string, "paragraph\n\nSecond")
  }

  func testInlineCodeUnicodeAndRichCopyContainNoLayoutSpacers() throws {
    let window = window()
    let selection = MarkdownSelectionCoordinator()
    let first = paragraph("before", y: 400, window: window, selection: selection)
    let second = paragraph("unused", y: 300, window: window, selection: selection)
    let code = NSMutableAttributedString(string: "café 👩🏽‍💻\tvalue", attributes: [
      .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .inlineCodeFill: NSColor.gray
    ])
    second.setParagraphContents(code, animatedByWord: false)
    select(NSRange(location: 0, length: 0), in: first, selection: selection)
    selection.extend(to: 8 + code.length)
    XCTAssertEqual(selection.selectedText?.string, "before\n\ncafé 👩🏽‍💻\tvalue")
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    XCTAssertTrue(second.writeSelection(to: board, type: .rtf))
    let data = try XCTUnwrap(board.data(forType: .rtf))
    let copied = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
    XCTAssertEqual(copied.string, selection.selectedText?.string)
  }

  func testTableReadingOrderAndSeparatorsIgnoreRegistrationOrder() {
    let window = window()
    let selection = MarkdownSelectionCoordinator()
    let bottomRight = paragraph("D", y: 300, window: window, selection: selection, x: 220)
    bottomRight.selectionSeparator = "\t"
    let topRight = paragraph("B", y: 400, window: window, selection: selection, x: 220)
    topRight.selectionSeparator = "\t"
    let bottomLeft = paragraph("C", y: 300, window: window, selection: selection)
    bottomLeft.selectionSeparator = "\n"
    let topLeft = paragraph("A", y: 400, window: window, selection: selection)
    select(NSRange(location: 0, length: 0), in: topLeft, selection: selection)
    selection.extend(to: 7)
    XCTAssertEqual(selection.selectedText?.string, "A\tB\nC\tD")
  }

  func testStreamingAppendAndReplacementPreserveSourceSelection() {
    let window = window()
    let selection = MarkdownSelectionCoordinator()
    let first = paragraph("Hello", y: 400, window: window, selection: selection)
    let second = paragraph("world", y: 300, window: window, selection: selection)
    select(NSRange(location: 2, length: 0), in: first, selection: selection)
    selection.extend(to: 10)
    second.setParagraphContents(NSMutableAttributedString(string: "world and more"), animatedByWord: false)
    selection.apply()
    XCTAssertEqual(selection.selectedText?.string, "llo\n\nwor")
    selection.unregister(first)
    first.removeFromSuperview()
    let replacement = paragraph("Hello", y: 400, window: window, selection: selection)
    selection.apply()
    XCTAssertEqual(replacement.selectedRange(), NSRange(location: 2, length: 3))
    XCTAssertEqual(selection.selectedText?.string, "llo\n\nwor")
  }

  func testHiddenContentAndOtherScopesAreExcluded() {
    let window = window()
    let selection = MarkdownSelectionCoordinator()
    let first = paragraph("visible", y: 400, window: window, selection: selection)
    let hidden = paragraph("hidden", y: 350, window: window, selection: selection)
    hidden.isHidden = true
    let other = MarkdownSelectionCoordinator()
    _ = paragraph("other response", y: 300, window: window, selection: other)
    select(NSRange(location: 0, length: 7), in: first, selection: selection)
    XCTAssertEqual(selection.selectedText?.string, "visible")
    XCTAssertNil(other.selectedText)
  }

  func testMouseDragUsesNativeHitTestingAcrossParagraphs() throws {
    let window = window()
    let selection = MarkdownSelectionCoordinator()
    let first = paragraph("First paragraph", y: 400, window: window, selection: selection)
    let second = paragraph("Second paragraph", y: 300, window: window, selection: selection)
    func event(_ type: NSEvent.EventType, point: NSPoint) throws -> NSEvent {
      try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                      clickCount: 1, pressure: 1))
    }
    let start = first.convert(NSPoint(x: 45, y: 8), to: nil)
    let finish = second.convert(NSPoint(x: 55, y: 8), to: nil)
    let startOffset = selection.position(in: first, at: start)
    let endOffset = selection.position(in: second, at: finish)
    first.mouseDown(with: try event(.leftMouseDown, point: start))
    first.mouseDragged(with: try event(.leftMouseDragged, point: finish))
    first.mouseUp(with: try event(.leftMouseUp, point: finish))
    XCTAssertEqual(selection.range, NSRange(location: startOffset, length: endOffset - startOffset))
    XCTAssertTrue(selection.selectedText?.string.contains("\n\n") == true)
    XCTAssertGreaterThan(second.selectedRange().length, 0)
  }
  func testRenderedDocumentIncludesCodeTableListAndQuoteInReadingOrder() async throws {
    // Explicit colors also work in SwiftPM's uncompiled asset-catalog test bundle.
    let fonts = MarkdownRenderConfig.default.paragraphStyle.textFonts
    let heading = MarkdownRenderConfig.default.headingStyle
    let config = MarkdownRenderConfig(
      blockQuoteStyle: .init(textFonts: fonts, textColor: .black),
      headingStyle: .init(h1Font: heading.h1Font, h2Font: heading.h2Font, h3Font: heading.h3Font,
                          h4Font: heading.h4Font, h5Font: heading.h5Font, h6Font: heading.h6Font, textColor: .black),
      orderedListStyle: .init(textFonts: fonts, textColor: .black),
      paragraphStyle: .init(textFonts: fonts, textColor: .black),
      tableStyle: .init(textFonts: fonts, headerTextColor: .black, regularTextColor: .black,
                        headerBackgroundColor: .gray.opacity(0.1), borderColor: .gray, actionButtonColor: .blue),
      inlineStyle: .init(boldTextColor: .black, linkTextFont: fonts.normal, linkTextColor: .blue,
                         codeTextFont: .monospacedSystemFont(ofSize: 14, weight: .regular), codeTextColor: .black,
                         codeBackgroundColor: .gray.opacity(0.1), codeUnderlineColor: .clear))
    let document = await MarkdownParserImpl().parse(text: """
    # Heading

    First `inline` paragraph.

    - List item

    > Quoted words

    ```swift
    let value = 42
      indented()
    ```

    | Key | Value |
    | --- | --- |
    | name | example |

    Last paragraph.
    """, config: config)
    let window = window()
    let selection = MarkdownSelectionCoordinator()
    let host = NSHostingView(rootView: DocumentView(renderableDocument: document, config: config)
      .environment(\.markdownSelection, selection)
      .frame(width: 460, alignment: .topLeading).padding(20)
      .background(Color.white).environment(\.colorScheme, .light))
    window.contentView = host
    host.frame = NSRect(x: 0, y: 0, width: 500, height: 850)
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    host.layoutSubtreeIfNeeded()
    window.appearance = NSAppearance(named: .aqua)
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    host.displayIfNeeded()
    selection.selectAll()
    let copied = try XCTUnwrap(selection.selectedText?.string)
    XCTAssertEqual(copied, "Heading\n\nFirst inline paragraph.\n\nList item\n\nQuoted words\n\nlet value = 42\n  indented()\n\n\nKey\tValue\nname\texample\n\nLast paragraph.")
    XCTAssertEqual(selection.segments.count, 10)
    for segment in selection.segments {
      XCTAssertGreaterThan(segment.view.bounds.height, 0)
      XCTAssertLessThan(segment.view.bounds.width, 500)
    }
    // A diagnostic image is useful when running this UI regression locally.
    if ProcessInfo.processInfo.environment["MARKDOWN_SELECTION_SNAPSHOT"] != nil,
       let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
      host.cacheDisplay(in: host.bounds, to: image)
      try image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/markdown-selection.png"))
    }
  }

  func testLinkClickStillOpensButDraggingDoesNot() throws {
    let window = window()
    let selection = MarkdownSelectionCoordinator()
    let view = paragraph("a link", y: 400, window: window, selection: selection)
    let url = try XCTUnwrap(URL(string: "https://example.com"))
    let content = NSMutableAttributedString(string: "a link", attributes: [.font: NSFont.systemFont(ofSize: 14), .link: url])
    view.setParagraphContents(content, animatedByWord: false)
    var opened: [URL] = []
    view.onUrlTap = { opened.append($0) }
    let point = view.convert(NSPoint(x: 12, y: 8), to: nil)
    func event(_ type: NSEvent.EventType) throws -> NSEvent {
      try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                      clickCount: 1, pressure: 1))
    }
    view.mouseDown(with: try event(.leftMouseDown))
    view.mouseUp(with: try event(.leftMouseUp))
    XCTAssertEqual(opened, [url])
    view.mouseDown(with: try event(.leftMouseDown))
    view.mouseDragged(with: try event(.leftMouseDragged))
    view.mouseUp(with: try event(.leftMouseUp))
    XCTAssertEqual(opened, [url])
  }

  func testDraggingOutsideTranscriptAutoscrolls() throws {
    let window = window()
    let selection = MarkdownSelectionCoordinator()
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
    scroll.hasVerticalScroller = true
    let document = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 1200))
    scroll.documentView = document
    window.contentView = scroll
    let view = ParagraphNSView()
    view.setParagraphContents(NSMutableAttributedString(string: "Start selection here"), animatedByWord: false)
    view.frame = NSRect(x: 0, y: 600, width: 300, height: 30)
    document.addSubview(view)
    view.selectionCoordinator = selection
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 400))
    let before = scroll.contentView.bounds.origin.y
    func event(_ type: NSEvent.EventType, point: NSPoint) throws -> NSEvent {
      try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                      clickCount: 1, pressure: 1))
    }
    view.mouseDown(with: try event(.leftMouseDown, point: view.convert(NSPoint(x: 10, y: 5), to: nil)))
    view.mouseDragged(with: try event(.leftMouseDragged, point: NSPoint(x: 30, y: -25)))
    view.mouseUp(with: try event(.leftMouseUp, point: NSPoint(x: 30, y: -25)))
    XCTAssertNotEqual(scroll.contentView.bounds.origin.y, before)
  }

  func testCommandArrowReplacesSharedRangeWithNativeSelection() throws {
    let window = window()
    let selection = MarkdownSelectionCoordinator()
    let first = paragraph("First paragraph", y: 400, window: window, selection: selection)
    _ = paragraph("Second paragraph", y: 300, window: window, selection: selection)
    window.makeFirstResponder(first)
    select(NSRange(location: 6, length: 0), in: first, selection: selection)
    selection.extend(to: 23)
    let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
      modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber, context: nil,
      characters: "\u{f703}", charactersIgnoringModifiers: "\u{f703}", isARepeat: false, keyCode: 124))
    first.keyDown(with: event)
    XCTAssertEqual(selection.range?.length, first.selectedRange().length)
    XCTAssertNil(selection.selectedText)
    selection.apply()
    XCTAssertEqual(first.selectedRange().length, 0)
  }

}
#endif
