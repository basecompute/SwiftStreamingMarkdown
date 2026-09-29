//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(AppKit)
import AppKit

extension MarkdownClipboardContent {
  static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
  }

  static func htmlDocument(_ records: [Record]) -> String {
    var html = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body style=\"color:#202124;background-color:#ffffff;font-family:Helvetica,Arial,sans-serif;font-size:13pt\"><!--StartFragment-->"
    var open: [MarkdownClipboardBlock] = []
    for record in records {
      let path = record.path.isEmpty ? [MarkdownClipboardBlock(tag: "p", id: UUID().uuidString)] : record.path
      let shared = zip(open, path).prefix(while: { $0 == $1 }).count
      for node in open.dropFirst(shared).reversed() { html += "</\(node.tag)>" }
      var pendingMarker: String?
      for node in path.dropFirst(shared) {
        var attributes = ""
        switch node.tag {
        case "table": attributes = " style=\"border-collapse:collapse;width:100%;margin:8pt 0\""
        case "th", "td":
          attributes = " style=\"border:1px solid #bcc0c4;padding:6pt;text-align:\(node.alignment);vertical-align:top;\(node.tag == "th" ? "background-color:#f1f3f5;" : "")\""
        case "pre": attributes = " style=\"white-space:pre-wrap;background-color:#f1f3f5;padding:9pt;font-family:monospace;margin:8pt 0\""
        case "blockquote": attributes = " style=\"margin:8pt 0 8pt 12pt;padding-left:9pt;border-left:3px solid #bcc0c4\""
        case "p": attributes = " style=\"margin:0 0 6pt 0\""
        case "ol":
          let firstItem = path.drop(while: { $0 != node }).first(where: { $0.tag == "li" })
          attributes = " start=\"\(firstItem?.index ?? 1)\""
        case "li":
          if node.marker != nil { attributes = " style=\"list-style-type:none\"" }
        default: break
        }
        html += "<\(node.tag)\(attributes)>"
        if let marker = node.marker { pendingMarker = marker }
        if node.tag == "p", let marker = pendingMarker { html += escape(marker) + " "; pendingMarker = nil }
      }
      if let marker = pendingMarker { html += escape(marker) + " " }
      html += inlineHTML(record.text, preformatted: path.contains(where: { $0.tag == "pre" }))
      open = path
    }
    for node in open.reversed() { html += "</\(node.tag)>" }
    return html + "<!--EndFragment--></body></html>"
  }

  private static func inlineHTML(_ source: NSAttributedString, preformatted: Bool) -> String {
    let source = portableText(source)
    var result = ""
    source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attributes, range, _ in
      var text = escape(source.attributedSubstring(from: range).string)
      if !preformatted { text = text.replacingOccurrences(of: "\n", with: "<br>") }
      let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 13)
      let color = attributes[.foregroundColor] as? NSColor ?? .black
      var style = "font-family:'\(escape(font.familyName ?? "Helvetica"))';font-size:\(font.pointSize)pt;color:\(cssColor(color));"
      let traits = font.fontDescriptor.symbolicTraits
      if traits.contains(.bold) { style += "font-weight:bold;" }
      if traits.contains(.italic) { style += "font-style:italic;" }
      if let underline = attributes[.underlineStyle] as? Int, underline != 0 { style += "text-decoration:underline;" }
      if let strike = attributes[.strikethroughStyle] as? Int, strike != 0 { style += "text-decoration:line-through;" }
      if let fill = attributes[.backgroundColor] as? NSColor { style += "background-color:\(cssColor(fill));" }
      let isCode = attributes[.inlineCodeFill] != nil
      let tag = isCode ? "code" : "span"
      if isCode { style += "padding:0.15em 0.3em;border-radius:3px;" }
      var run = "<\(tag) style=\"\(style)\">\(text)</\(tag)>"
      if let url = safeLink(attributes[.link]) { run = "<a href=\"\(escape(url.absoluteString))\">\(run)</a>" }
      result += run
    }
    return result
  }

  private static func cssColor(_ color: NSColor) -> String {
    guard let rgb = color.usingColorSpace(.sRGB) else { return "#202124" }
    return String(format: "#%02x%02x%02x", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
  }

  // Clipboard HTML contains only generated markup and inert, escaped source text.
  // swiftlint:disable:next no_any
  static func safeLink(_ value: Any?) -> URL? {
    let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
    guard let url, let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "tel"].contains(scheme) else { return nil }
    return url
  }
}
#endif
