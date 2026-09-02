//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI

struct BlockView: View {

  @Environment(\.markdownConfig) var config: MarkdownRenderConfig
  @Environment(\.isActiveStreamingMarkdownBlock) var isParentActive

  let renderables: [MarkdownRenderable]

  init(renderables: [MarkdownRenderable]) {
    self.renderables = renderables
  }

  var body: some View {
    VStack(alignment: .leading, spacing: config.blockSpacing) {
      ForEach(renderables) { renderable in
        SingleBlockView(renderable: renderable)
          .environment(
            \.isActiveStreamingMarkdownBlock,
            isParentActive && renderable.id == renderables.last?.id
          )
      }
    }
  }
}

struct SingleBlockView: View {

  @Environment(\.markdownConfig) var config: MarkdownRenderConfig

  let renderable: MarkdownRenderable

  init(renderable: MarkdownRenderable) {
    self.renderable = renderable
  }

  var body: some View {
    Group {
      switch renderable {
      case .heading(_, _, let contents):
        ParagraphView(contents: contents)
          .transition(.opacity)
          .accessibilityAddTraits(.isHeader)
      case .paragraph(_, let contents):
        ParagraphView(contents: contents, lineSpacing: 5)
          .fixedSize(horizontal: false, vertical: true)
          .transition(.opacity)
      case .latex(_, let latexString):
        if BlockMathView.canTypeset(latexString) {
          // Display math is conventionally centered, with breathing room —
          // it was pinned leading and hugged its glyphs vertically. When it
          // is wider than the container, fall back to a horizontal scroll.
          ViewThatFits(in: .horizontal) {
            BlockMathView(latex: latexString, color: config.paragraphStyle.textColor)
              .padding(.vertical, 6)
              .frame(maxWidth: .infinity, alignment: .center)
            ScrollView(.horizontal) {
              BlockMathView(latex: latexString, color: config.paragraphStyle.textColor)
                .padding(.vertical, 6)
            }.scrollIndicators(.hidden)
          }
        } else {
          // The typesetter covers a LaTeX subset; commands outside it
          // used to render NOTHING, so whole formulas silently vanished.
          // Standard renderer practice (KaTeX, MathJax) is to show the
          // source when typesetting fails.
          ScrollView(.horizontal) {
            Text(latexString)
              .font(.system(size: 12, design: .monospaced))
              .foregroundStyle(config.paragraphStyle.textColor.opacity(0.75))
              .padding(8)
          }
          .scrollIndicators(.hidden)
          .background(config.inlineStyle.codeBackgroundColor)
          .clipShape(RoundedRectangle(cornerRadius: 6))
        }
      case .orderedList(_, let items):
        OrderedListView(items: items)
      case .unorderedList(_, let items, let nestedLevel):
        UnorderedListView(items: items, nestedLevel: nestedLevel)
      case .codeBlock(_, let language, let code):
        CodeBlockView(language: language ?? "",
                      code: code)
      case .thematicBreak:
        ThematicBreakView()
      case .table(_, let headers, let rows, let alignments, let rawMarkdown):
        TableView(headings: headers,
                  rows: rows,
                  alignments: alignments,
                  rawMarkdown: rawMarkdown)
      case .blockQuote(_, let item):
        BlockQuoteView(item: item)
      case .image(let id, let data):
        BlockImageView(data: data)
          .id(id)
      }
    }
  }
}
