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
final class MarkdownClipboardTests: XCTestCase {
  private let sample = """
  # Copy formatting

  A **bold** and *italic* paragraph with `inline code`, a [link](https://example.com), and café 👩🏽‍💻.

  1. First item
     - Nested item
  2. Second item

  - [x] Done
  - [ ] Pending

  > Quoted text

  | Name | Count |
  | :--- | ---: |
  | Alpha | 12 |
  | Beta | 34 |

  ```swift
  let answer = 42
    print(answer)
  ```
  """

  private func richText(_ content: MarkdownClipboardContent) throws -> NSAttributedString {
    try NSAttributedString(data: XCTUnwrap(content.rtf),
      options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
  }

  func testFullDocumentExportsSemanticHTMLAndNativeRTFTablesAndLists() async throws {
    let document = await MarkdownParserImpl().parse(text: sample, config: .default)
    let content = MarkdownClipboardContent(document: document)
    for tag in ["<h1", "<ol", "<ul", "<li", "<blockquote", "<table", "<th", "<td", "<pre", "<code"] {
      XCTAssertTrue(content.html.contains(tag), "Missing \(tag)")
    }
    XCTAssertTrue(content.html.contains("text-align:right"))
    XCTAssertTrue(content.html.contains("font-family:'Arial'"))
    XCTAssertTrue(content.html.contains("font-weight:normal;font-style:normal;text-decoration:none;background-color:#ffffff;"))
    XCTAssertTrue(content.html.contains("<ol start=\"1\" style=\"font-size:17.0pt;"))
    XCTAssertTrue(content.html.contains("☑"))
    XCTAssertTrue(content.html.contains("https://example.com"))
    let rich = try richText(content)
    var tableCells = 0
    var listParagraphs = 0
    var shadedCode = false
    rich.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: rich.length)) { value, _, _ in
      guard let style = value as? NSParagraphStyle else { return }
      if style.textBlocks.contains(where: { $0 is NSTextTableBlock }) { tableCells += 1 }
      if !style.textLists.isEmpty { listParagraphs += 1 }
    }
    let codeRange = (rich.string as NSString).range(of: "inline code")
    if codeRange.location != NSNotFound { shadedCode = rich.attribute(.backgroundColor, at: codeRange.location, effectiveRange: nil) != nil }
    XCTAssertGreaterThanOrEqual(tableCells, 6)
    XCTAssertGreaterThanOrEqual(listParagraphs, 4)
    XCTAssertTrue(shadedCode)
    XCTAssertTrue(rich.string.contains("  print(answer)"))
    XCTAssertTrue(rich.string.contains("café 👩🏽‍💻"))
    if ProcessInfo.processInfo.environment["MARKDOWN_CLIPBOARD_FIXTURE"] != nil {
      try content.html.write(toFile: "/tmp/markdown-rich-copy.html", atomically: true, encoding: .utf8)
      try content.rtf?.write(to: URL(fileURLWithPath: "/tmp/markdown-rich-copy.rtf"))
    }
  }

  func testClipboardPublishesFormatsInOneItem() async throws {
    let document = await MarkdownParserImpl().parse(text: "Hello **world**", config: .default)
    let content = MarkdownClipboardContent(document: document)
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    XCTAssertTrue(content.write(to: board))
    XCTAssertEqual(board.pasteboardItems?.count, 1)
    XCTAssertEqual(board.string(forType: .string), "Hello world")
    XCTAssertEqual(board.string(forType: .html), content.html)
    XCTAssertEqual(board.data(forType: .rtf), content.rtf)
  }

  func testPlainTextOverrideKeepsOriginalMarkdownWithoutChangingRichFormats() async {
    let markdown = "Hello **world**"
    let document = await MarkdownParserImpl().parse(text: markdown, config: .default)
    let standard = MarkdownClipboardContent(document: document)
    let content = MarkdownClipboardContent(document: document, plainText: markdown)
    XCTAssertEqual(content.plainText, markdown)
    XCTAssertEqual(content.html, standard.html)
    XCTAssertEqual(content.rtf, standard.rtf)
  }

  func testEscapesSourceAndRejectsExecutableLinks() throws {
    let source = NSAttributedString(string: "<script>alert('x')</script> & \"quoted\"", attributes: [
      .link: "javascript:alert(1)", .foregroundColor: NSColor.white
    ])
    let content = MarkdownClipboardContent(records: [.init(text: source, path: [])], plainText: source.string)
    XCTAssertFalse(content.html.contains("<script>"))
    XCTAssertFalse(content.html.contains("javascript:"))
    XCTAssertTrue(content.html.contains("&lt;script&gt;"))
    XCTAssertTrue(content.html.contains("&amp;"))
    let rich = try richText(content)
    XCTAssertEqual(rich.string, source.string)
    XCTAssertNil(rich.attribute(.link, at: 0, effectiveRange: nil))
    let color = try XCTUnwrap(rich.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor).usingColorSpace(.sRGB)
    XCTAssertLessThan(color?.redComponent ?? 1, 0.3)
  }

  func testPartialTableSelectionCreatesEmptyCellsWithoutLeakingOtherText() throws {
    let table = MarkdownClipboardBlock(tag: "table", id: "table", columns: 3)
    let selected = MarkdownClipboardContent.Record(text: NSAttributedString(string: "selected"), path: [
      table, .init(tag: "tr", id: "row-4", index: 4), .init(tag: "td", id: "column-1", index: 1)
    ])
    let content = MarkdownClipboardContent(records: [selected], plainText: "selected")
    XCTAssertEqual(content.html.components(separatedBy: "<td ").count - 1, 3)
    XCTAssertEqual(content.plainText, "selected")
    let rich = try richText(content)
    let range = (rich.string as NSString).range(of: "selected")
    let style = try XCTUnwrap(rich.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
    let cell = try XCTUnwrap(style.textBlocks.first as? NSTextTableBlock)
    XCTAssertEqual(cell.startingRow, 0)
    XCTAssertEqual(cell.startingColumn, 1)
    XCTAssertEqual(cell.table.numberOfColumns, 3)
  }

  func testSelectedListStartsAtItsOriginalNumber() throws {
    let record = MarkdownClipboardContent.Record(text: NSAttributedString(string: "third"), path: [
      .init(tag: "ol", id: "list"), .init(tag: "li", id: "item-2", index: 3), .init(tag: "p", id: "paragraph")
    ])
    let content = MarkdownClipboardContent(records: [record], plainText: "third")
    XCTAssertTrue(content.html.contains("<ol start=\"3\""))
    let rich = try richText(content)
    XCTAssertTrue(String(data: try XCTUnwrap(content.rtf), encoding: .ascii)?.contains("\\levelstartat3") == true)
    let style = try XCTUnwrap(rich.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
    XCTAssertEqual(style.textLists.first?.startingItemNumber, 3)
  }

  func testRenderedSelectionCarriesTableListAndHeadingStructure() async throws {
    _ = NSApplication.shared
    let document = await MarkdownParserImpl().parse(text: sample, config: .default)
    let selection = MarkdownSelectionCoordinator()
    let host = NSHostingView(rootView: DocumentView(renderableDocument: document)
      .environment(\.markdownSelection, selection).frame(width: 460))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 1600),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host
    host.frame = NSRect(x: 0, y: 0, width: 460, height: 1600)
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    host.layoutSubtreeIfNeeded()
    selection.selectAll()
    let content = try XCTUnwrap(selection.clipboardContent)
    for tag in ["<h1", "<ol", "<ul", "<li", "<blockquote", "<table", "<pre", "<code"] {
      XCTAssertTrue(content.html.contains(tag), "Selected content missing \(tag)")
    }
    let cell = try XCTUnwrap(selection.segments.first(where: { $0.text.string == "Alpha" }))
    cell.view.setSelectedRange(NSRange(location: 1, length: 3))
    selection.adoptNativeSelection(in: cell.view)
    let partial = try XCTUnwrap(selection.clipboardContent)
    XCTAssertEqual(partial.plainText, "lph")
    XCTAssertTrue(partial.html.contains("<table"))
    XCTAssertFalse(partial.html.contains("Beta"))
    XCTAssertFalse(partial.html.contains("Alpha"))
    XCTAssertFalse(partial.html.contains(">12</span>"))
  }
}
#endif
