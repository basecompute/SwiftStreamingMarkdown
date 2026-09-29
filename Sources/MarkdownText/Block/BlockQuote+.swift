//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import Markdown
import SwiftUI

extension BlockQuote: BlockConvertible {
  var quoteTypes: BlockQuoteType { quoteTypes(config: .default) }

  func quoteTypes(config: MarkdownRenderConfig) -> BlockQuoteType {
    var finalQuoteTypes = [BlockQuoteType]()

    for child in children {
      if let inlineContainer = child as? InlineContainer {
        #if canImport(AppKit)
        guard let block = child as? BlockMarkup else { continue }
        let container: NSAttributeContainer = [
          .font: config.blockQuoteStyle.textFonts.normal,
          .foregroundColor: MDColor(config.blockQuoteStyle.textColor)
        ]
        finalQuoteTypes.append(.attributedText(
          block.buildParagraphContent(container: container, config: config),
          plainText: inlineContainer.extractPlainText(removeHeading: false)))
        #else
        finalQuoteTypes.append(.text(inlineContainer.extractPlainText(removeHeading: false)))
        #endif
      } else if let blockQuoteContainer = child as? BlockQuote {
        finalQuoteTypes.append(blockQuoteContainer.quoteTypes(config: config))
      }
    }

    return .nested(finalQuoteTypes)
  }

  func convert(attributeContainer: NSAttributeContainer, config: MarkdownRenderConfig) -> MarkdownRenderable {
    .blockQuote(id: id, item: .init(quoteType: quoteTypes(config: config)))
  }
}

struct BlockQuoteRenderable: Equatable {
  let quoteType: BlockQuoteType
}
