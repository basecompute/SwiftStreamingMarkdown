//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI

/// The structural ancestors of a rendered text surface, retained for clipboard export.
struct MarkdownClipboardBlock: Equatable {
  let tag: String
  let id: String
  var index = 0
  var columns = 0
  var alignment = "left"
  var marker: String?
}

extension EnvironmentValues {
  @Entry var markdownClipboardPath: [MarkdownClipboardBlock] = []
}

extension View {
  func clipboardBlock(_ block: MarkdownRenderable) -> some View {
    transformEnvironment(\.markdownClipboardPath) { path in
      let tag: String
      var columns = 0
      switch block {
      case .heading(_, let level, _): tag = "h\(min(6, max(1, level)))"
      case .orderedList: tag = "ol"
      case .unorderedList: tag = "ul"
      case .table(_, let headers, _, _, _): tag = "table"; columns = headers.count
      case .blockQuote: tag = "blockquote"
      case .codeBlock: tag = "pre"
      default: tag = "p"
      }
      path.append(MarkdownClipboardBlock(tag: tag, id: block.id, columns: columns))
    }
  }

  func clipboardListItem(_ index: Int, checkbox: MarkdownListItem.Checkbox? = nil) -> some View {
    transformEnvironment(\.markdownClipboardPath) { path in
      path.append(MarkdownClipboardBlock(tag: "li", id: "item-\(index)", index: index + 1,
        marker: checkbox.map { $0 == .checked ? "☑" : "☐" }))
    }
  }

  func clipboardTableCell(row: Int, column: Int, alignment: MarkdownColumnAlignment) -> some View {
    transformEnvironment(\.markdownClipboardPath) { path in
      path.append(MarkdownClipboardBlock(tag: "tr", id: "row-\(row)", index: row))
      path.append(MarkdownClipboardBlock(tag: row == 0 ? "th" : "td", id: "column-\(column)", index: column,
        alignment: alignment == .center ? "center" : (alignment == .trailing ? "right" : "left")))
    }
  }
}
