//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(AppKit)
import AppKit

/// Portable, editable clipboard representations of rendered Markdown.
/// HTML and RTF retain tables/lists; plain text remains available to text-only apps.
public struct MarkdownClipboardContent {
  public let plainText: String
  public let html: String
  public let rtf: Data?

  struct Record {
    let text: NSAttributedString
    let path: [MarkdownClipboardBlock]
  }

  @MainActor
  public init(document: RenderableDocument, config: MarkdownRenderConfig = .default, plainText: String? = nil) {
    self.init(records: Self.records(document.renderables, config: config), plainText: plainText ?? document.plainText)
  }

  @MainActor
  init(records: [Record], plainText: String) {
    self.plainText = plainText
    let records = Self.rectangularTables(records)
    html = Self.htmlDocument(records)
    let richText = Self.richText(records)
    rtf = try? richText.data(from: NSRange(location: 0, length: richText.length),
                            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
  }

  /// Write all formats in one pasteboard item, so the recipient chooses its preferred format.
  @MainActor
  @discardableResult
  public func write(to pasteboard: NSPasteboard = .general) -> Bool {
    let item = NSPasteboardItem()
    item.setString(plainText, forType: .string)
    item.setString(html, forType: .html)
    if let rtf { item.setData(rtf, forType: .rtf) }
    pasteboard.clearContents()
    return pasteboard.writeObjects([item])
  }

  @MainActor
  func write(to pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
    switch type {
    case .string: return pasteboard.setString(plainText, forType: type)
    case .html: return pasteboard.setString(html, forType: type)
    case .rtf:
      guard let rtf else { return false }
      return pasteboard.setData(rtf, forType: type)
    default: return false
    }
  }

  // Keep a selected table rectangular, without including text from unselected cells.
  static func rectangularTables(_ records: [Record]) -> [Record] {
    var result: [Record] = []
    var index = 0
    while index < records.count {
      let record = records[index]
      guard let tableIndex = record.path.firstIndex(where: { $0.tag == "table" }),
            record.path.count > tableIndex + 2 else {
        result.append(record); index += 1; continue
      }
      let prefix = Array(record.path.prefix(tableIndex + 1))
      var cells: [Record] = []
      while index < records.count, Array(records[index].path.prefix(tableIndex + 1)) == prefix {
        cells.append(records[index]); index += 1
      }
      let rows = Dictionary(grouping: cells, by: { $0.path[tableIndex + 1].index })
      for row in rows.keys.sorted() {
        guard let rowCells = rows[row], let first = rowCells.first else { continue }
        for column in 0..<max(1, prefix[tableIndex].columns) {
          if let cell = rowCells.first(where: { $0.path[tableIndex + 2].index == column }) {
            result.append(cell)
          } else {
            let path = prefix + [first.path[tableIndex + 1], MarkdownClipboardBlock(
              tag: row == 0 ? "th" : "td", id: "column-\(column)", index: column)]
            result.append(Record(text: NSAttributedString(string: ""), path: path))
          }
        }
      }
    }
    return result
  }
}
#endif
