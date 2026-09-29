//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(AppKit)
import AppKit

extension MarkdownClipboardContent {
  /// Uses native table/list attributes directly: no WebKit HTML import or nested run loop on Copy.
  static func richText(_ records: [Record]) -> NSAttributedString {
    let output = NSMutableAttributedString()
    var tables: [String: NSTextTable] = [:]
    var firstRows: [String: Int] = [:]
    var lists: [String: NSTextList] = [:]
    var emittedItems = Set<String>()
    for (recordIndex, record) in records.enumerated() {
      let text = NSMutableAttributedString(attributedString: portableText(record.text))
      let paragraph = NSMutableParagraphStyle()
      paragraph.paragraphSpacing = 6
      var ancestors: [String] = []
      var listStack: [NSTextList] = []
      var marker: String?
      var table: NSTextTable?
      var tableKey = ""
      var row = 0
      for node in record.path {
        ancestors.append(node.id)
        let key = ancestors.joined(separator: "/")
        switch node.tag {
        case "ol", "ul":
          let list = lists[key] ?? NSTextList(markerFormat: node.tag == "ol" ? NSTextList.MarkerFormat(rawValue: "{decimal}.") : .disc, options: 0)
          if lists[key] == nil {
            list.startingItemNumber = record.path.drop(while: { $0 != node }).first(where: { $0.tag == "li" })?.index ?? 1
            lists[key] = list
          }
          listStack.append(list)
        case "li":
          if let checkbox = node.marker, !listStack.isEmpty {
            listStack[listStack.count - 1] = NSTextList(markerFormat: NSTextList.MarkerFormat(rawValue: checkbox), options: 0)
          }
          if !emittedItems.contains(key) {
            marker = node.marker ?? listStack.last?.marker(forItemNumber: node.index)
            emittedItems.insert(key)
          }
        case "blockquote": paragraph.headIndent += 16; paragraph.firstLineHeadIndent += 16
        case "table":
          let value = tables[key] ?? NSTextTable()
          value.numberOfColumns = max(1, node.columns)
          value.collapsesBorders = true
          value.setContentWidth(100, type: .percentageValueType)
          tables[key] = value
          table = value
          tableKey = key
        case "tr":
          if firstRows[tableKey] == nil { firstRows[tableKey] = node.index }
          row = node.index - (firstRows[tableKey] ?? 0)
        case "th", "td":
          if let table {
            let cell = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: node.index, columnSpan: 1)
            cell.setWidth(6, type: .absoluteValueType, for: .padding)
            cell.setWidth(0.5, type: .absoluteValueType, for: .border)
            cell.setBorderColor(NSColor(white: 0.74, alpha: 1))
            if node.tag == "th" { cell.backgroundColor = NSColor(white: 0.95, alpha: 1) }
            paragraph.textBlocks = [cell]
            paragraph.paragraphSpacing = 0
            paragraph.alignment = node.alignment == "center" ? .center : (node.alignment == "right" ? .right : .left)
          }
        case "pre":
          text.addAttribute(.backgroundColor, value: NSColor(white: 0.95, alpha: 1), range: NSRange(location: 0, length: text.length))
        default: break
        }
      }
      if !listStack.isEmpty {
        paragraph.textLists = listStack
        paragraph.headIndent += CGFloat(listStack.count) * 20
        paragraph.firstLineHeadIndent = paragraph.headIndent - 15
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: paragraph.headIndent)]
        if let marker {
          let font = text.length > 0 ? text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil
          text.insert(NSAttributedString(string: "\t\(marker)\t", attributes: [.font: font ?? NSFont.systemFont(ofSize: 13)]), at: 0)
        }
      }
      if table != nil || !listStack.isEmpty {
        if !text.string.hasSuffix("\n") { text.append(NSAttributedString(string: "\n")) }
      } else if recordIndex < records.count - 1 {
        text.append(NSAttributedString(string: "\n\n"))
      }
      let full = NSRange(location: 0, length: text.length)
      text.addAttribute(.paragraphStyle, value: paragraph, range: full)
      output.append(text)
    }
    return output
  }

  /// Map renderer-only decoration to standard attributes and a white-page palette.
  static func portableText(_ source: NSAttributedString) -> NSAttributedString {
    let result = NSMutableAttributedString(attributedString: InlineCodeStyle.unpadded(source))
    let full = NSRange(location: 0, length: result.length)
    result.enumerateAttributes(in: full, options: .reverse) { attributes, range, _ in
      if let citation = attributes[.attachment] as? InlineCitationAttachment, let data = citation.citationData {
        result.replaceCharacters(in: range, with: NSAttributedString(string: data.title, attributes: [.link: data.url]))
        return
      }
      let color = (attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB)
      if let color, color.alphaComponent > 0.5,
         0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent < 0.6 {
        result.addAttribute(.foregroundColor, value: color.withAlphaComponent(1), range: range)
      } else { result.addAttribute(.foregroundColor, value: NSColor(white: 0.12, alpha: 1), range: range) }
      if attributes[.inlineCodeFill] != nil {
        result.addAttribute(.backgroundColor, value: NSColor(white: 0.95, alpha: 1), range: range)
      }
      let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 13)
      if font.familyName?.hasPrefix(".") != false {
        let monospaced = font.isFixedPitch || font.familyName?.lowercased().contains("monospaced") == true
        var portable = NSFont(name: monospaced ? "Courier New" : "Helvetica", size: font.pointSize) ?? font
        if font.fontDescriptor.symbolicTraits.contains(.bold) { portable = NSFontManager.shared.convert(portable, toHaveTrait: .boldFontMask) }
        if font.fontDescriptor.symbolicTraits.contains(.italic) { portable = NSFontManager.shared.convert(portable, toHaveTrait: .italicFontMask) }
        result.addAttribute(.font, value: portable, range: range)
      }
      if attributes[.link] != nil, safeLink(attributes[.link]) == nil { result.removeAttribute(.link, range: range) }
    }
    return result
  }
}
#endif
