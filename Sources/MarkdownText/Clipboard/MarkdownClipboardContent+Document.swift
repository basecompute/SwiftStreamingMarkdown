//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(AppKit)
import AppKit

extension MarkdownClipboardContent {
  static func records(_ blocks: [MarkdownRenderable], config: MarkdownRenderConfig,
                      path: [MarkdownClipboardBlock] = []) -> [Record] {
    blocks.flatMap { block -> [Record] in
      func leaf(_ text: NSAttributedString, tag: String = "p") -> [Record] {
        [Record(text: text, path: path + [MarkdownClipboardBlock(tag: tag, id: block.id)])]
      }
      switch block {
      case .paragraph(_, let text): return leaf(text)
      case .heading(_, let level, let text): return leaf(text, tag: "h\(min(6, max(1, level)))")
      case .codeBlock(_, _, let code):
        return leaf(NSAttributedString(string: code, attributes: [.font: config.codeBlockConfig.codeTextFonts.normal]), tag: "pre")
      case .orderedList(_, let items), .unorderedList(_, let items, _):
        let ordered: Bool
        if case .orderedList = block { ordered = true } else { ordered = false }
        let list = path + [MarkdownClipboardBlock(tag: ordered ? "ol" : "ul", id: block.id)]
        return items.enumerated().flatMap { index, item in
          records(item.children, config: config, path: list + [MarkdownClipboardBlock(
            tag: "li", id: "item-\(index)", index: index + 1,
            marker: item.checkbox.map { $0 == .checked ? "☑" : "☐" })])
        }
      case .table(_, let headers, let rows, let alignments, _):
        let table = path + [MarkdownClipboardBlock(tag: "table", id: block.id, columns: headers.count)]
        return ([headers] + rows).enumerated().flatMap { row, cells in
          cells.enumerated().map { column, text in
            let alignment = column < alignments.count ? alignments[column] : .leading
            return Record(text: text, path: table + [
              MarkdownClipboardBlock(tag: "tr", id: "row-\(row)", index: row),
              MarkdownClipboardBlock(tag: row == 0 ? "th" : "td", id: "column-\(column)", index: column,
                alignment: alignment == .center ? "center" : (alignment == .trailing ? "right" : "left"))])
          }
        }
      case .blockQuote(_, let item):
        return quoteRecords(item.quoteType, path: path + [MarkdownClipboardBlock(tag: "blockquote", id: block.id)])
      case .latex(_, let source): return leaf(NSAttributedString(string: source), tag: "pre")
      case .image(_, let data): return leaf(NSAttributedString(string: data.alt))
      case .thematicBreak: return []
      }
    }
  }

  private static func quoteRecords(_ quote: BlockQuoteType, path: [MarkdownClipboardBlock]) -> [Record] {
    switch quote {
    case .text(let text): return [Record(text: NSAttributedString(string: text), path: path)]
    case .attributedText(let text, _): return [Record(text: text, path: path)]
    case .nested(let children):
      return children.enumerated().flatMap { index, child in
        quoteRecords(child, path: path + [MarkdownClipboardBlock(tag: child.isNested ? "blockquote" : "p", id: "quote-\(index)")])
      }
    }
  }
}
#endif
