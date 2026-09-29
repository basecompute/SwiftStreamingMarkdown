//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(AppKit)
import AppKit
import SwiftUI

/// Selection offsets refer to source text, never the inline-code layout spacers.
/// Keeping offsets outside individual views also survives their replacement when
/// a streamed response switches to its finished representation.
@MainActor
final class MarkdownSelectionCoordinator: ObservableObject {
  private let participants = NSHashTable<ParagraphNSView>.weakObjects()
  private var anchor: Int?
  private(set) var range: NSRange?
  private var applying = false
  private var needsFocusRestoration = false
  // AppKit returns an opaque event-monitor token.
  // swiftlint:disable:next no_any
  private var clickMonitor: Any?
  private var scrollTimer: Timer?
  private weak var dragView: ParagraphNSView?
  private var dragEvent: NSEvent?

  struct Segment {
    let view: ParagraphNSView
    let text: NSAttributedString
    let start: Int
    let separator: String
    var end: Int { start + text.length }
  }

  func register(_ view: ParagraphNSView) {
    participants.add(view)
  }

  func unregister(_ view: ParagraphNSView) {
    if view.window?.firstResponder === view { needsFocusRestoration = true }
    participants.remove(view)
    if dragView === view { endDrag() }
  }

  var segments: [Segment] {
    let views = participants.allObjects.filter { $0.window != nil && !$0.isHiddenOrHasHiddenAncestor }
      .sorted {
        let left = $0.convert($0.bounds, to: nil)
        let right = $1.convert($1.bounds, to: nil)
        if abs(left.maxY - right.maxY) > 1 { return left.maxY > right.maxY }
        return left.minX < right.minX
      }
    var offset = 0
    return views.enumerated().map { index, view in
      let separator = index == 0 ? "" : view.selectionSeparator
      offset += (separator as NSString).length
      let text = view.paragraphContents
      let segment = Segment(view: view, text: text, start: offset, separator: separator)
      offset += text.length
      return segment
    }
  }

  func begin(in view: ParagraphNSView, event: NSEvent) {
    endDrag()
    monitorOutsideClicks()
    let offset = position(in: view, at: event.locationInWindow)
    if !event.modifierFlags.contains(.shift) || anchor == nil { anchor = offset }
    extend(to: offset)
    dragView = view
  }

  private func monitorOutsideClicks() {
    if clickMonitor == nil {
      clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
        MainActor.assumeIsolated {
          guard let self else { return event }
          var hit = event.window?.contentView?.hitTest(event.locationInWindow)
          while let view = hit {
            if let paragraph = view as? ParagraphNSView, paragraph.selectionCoordinator === self { return event }
            hit = view.superview
          }
          self.clear()
          return event
        }
      }
    }
  }

  func drag(_ event: NSEvent) {
    dragEvent = event
    updateDrag()
    if scrollTimer == nil {
      let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.updateDrag() }
      }
      RunLoop.main.add(timer, forMode: .common)
      scrollTimer = timer
    }
  }

  func endDrag() {
    scrollTimer?.invalidate()
    scrollTimer = nil
    dragEvent = nil
    dragView = nil
  }

  private func updateDrag() {
    guard let event = dragEvent, let origin = dragView else { return }
    // Let each enclosing scroller move only along its scrollable axes.
    var ancestor = origin.superview
    while let view = ancestor {
      if let scroll = view as? NSScrollView,
         let document = scroll.documentView,
         (document.bounds.height > scroll.contentView.bounds.height
          || document.bounds.width > scroll.contentView.bounds.width) {
        _ = document.autoscroll(with: event)
      }
      ancestor = view.superview
    }
    let point = event.locationInWindow
    let candidates = segments
    let nearest = candidates.min { left, right in
      distance(point, to: left.view) < distance(point, to: right.view)
    }
    guard let nearest else { return }
    extend(to: position(in: nearest.view, at: point))
  }

  private func distance(_ point: NSPoint, to view: NSView) -> CGFloat {
    let rect = view.convert(view.bounds, to: nil)
    let vertical = max(rect.minY - point.y, 0, point.y - rect.maxY)
    let horizontal = max(rect.minX - point.x, 0, point.x - rect.maxX)
    // Reading order across rows takes precedence over the horizontal distance.
    return vertical * 10_000 + horizontal
  }

  func position(in view: ParagraphNSView, at point: NSPoint) -> Int {
    guard let segment = segments.first(where: { $0.view === view }) else { return 0 }
    let local = view.convert(point, from: nil)
    let index: Int
    if local.y < view.bounds.minY { index = 0 }
    else if local.y > view.bounds.maxY { index = view.string.utf16.count }
    else { index = view.characterIndexForInsertion(at: local) }
    return segment.start + view.sourceOffset(forDisplayOffset: index)
  }

  func extend(to offset: Int) {
    guard let anchor else { return }
    range = NSRange(location: min(anchor, offset), length: abs(offset - anchor))
    apply()
  }

  func adoptNativeSelection(in view: ParagraphNSView) {
    monitorOutsideClicks()
    guard let segment = segments.first(where: { $0.view === view }) else { return }
    let native = view.selectedRange()
    anchor = segment.start + view.sourceOffset(forDisplayOffset: native.location)
    extend(to: segment.start + view.sourceOffset(forDisplayOffset: NSMaxRange(native)))
  }

  func clear() {
    endDrag()
    if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    clickMonitor = nil
    needsFocusRestoration = false
    anchor = nil
    range = nil
    for view in participants.allObjects { view.setSharedSelection(nil) }
  }

  func selectAll() {
    monitorOutsideClicks()
    anchor = 0
    extend(to: segments.last?.end ?? 0)
  }

  deinit {
    scrollTimer?.invalidate()
    if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
  }

  func apply() {
    guard !applying, let range else { return }
    applying = true
    defer { applying = false }
    for segment in segments {
      let start = max(segment.start, range.location)
      let end = min(segment.end, NSMaxRange(range))
      let local = NSRange(location: max(0, min(segment.text.length, start - segment.start)),
                          length: max(0, end - start))
      segment.view.setSharedSelection(local)
      if needsFocusRestoration, local.length > 0 {
        segment.view.window?.makeFirstResponder(segment.view)
        needsFocusRestoration = false
      }
    }
  }

  var clipboardContent: MarkdownClipboardContent? {
    guard let range, let plainText = selectedText?.string else { return nil }
    let records = segments.compactMap { segment -> MarkdownClipboardContent.Record? in
      let selected = NSIntersectionRange(range, NSRange(location: segment.start, length: segment.text.length))
      guard selected.length > 0 else { return nil }
      let text = segment.text.attributedSubstring(from: NSRange(location: selected.location - segment.start, length: selected.length))
      return .init(text: text, path: segment.view.clipboardPath)
    }
    return MarkdownClipboardContent(records: records, plainText: plainText)
  }

  var selectedText: NSAttributedString? {
    guard let range, range.length > 0 else { return nil }
    let result = NSMutableAttributedString()
    for segment in segments {
      let separatorStart = segment.start - (segment.separator as NSString).length
      let separatorRange = NSIntersectionRange(range, NSRange(location: separatorStart,
                                                               length: segment.start - separatorStart))
      if separatorRange.length > 0 {
        let text = (segment.separator as NSString).substring(with: NSRange(
          location: separatorRange.location - separatorStart, length: separatorRange.length))
        result.append(NSAttributedString(string: text))
      }
      let selected = NSIntersectionRange(range, NSRange(location: segment.start, length: segment.text.length))
      if selected.length > 0 {
        result.append(segment.text.attributedSubstring(from: NSRange(location: selected.location - segment.start,
                                                                     length: selected.length)))
      }
    }
    return result
  }
}
#endif
