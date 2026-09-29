//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(AppKit)
import AppKit

extension ParagraphNSView {
  func sourceOffset(forDisplayOffset offset: Int) -> Int {
    guard let textStorage else { return 0 }
    let prefix = textStorage.attributedSubstring(from: NSRange(location: 0, length: min(max(0, offset), textStorage.length)))
    return InlineCodeStyle.unpadded(prefix).length
  }

  private func displayOffset(forSourceOffset offset: Int) -> Int {
    guard let textStorage else { return 0 }
    var source = 0
    for index in 0..<textStorage.length {
      if textStorage.attribute(.inlineCodePadding, at: index, effectiveRange: nil) as? Bool == true { continue }
      if source == offset { return index }
      source += 1
    }
    return textStorage.length
  }

  func setSharedSelection(_ sourceRange: NSRange?) {
    if nativeSelectionAttributes == nil { nativeSelectionAttributes = selectedTextAttributes }
    selectedTextAttributes = sourceRange == nil
      ? (nativeSelectionAttributes ?? [:]) : [.backgroundColor: NSColor.clear]
    let displayRange: NSRange
    if let sourceRange {
      let start = displayOffset(forSourceOffset: sourceRange.location)
      let end = displayOffset(forSourceOffset: NSMaxRange(sourceRange))
      displayRange = NSRange(location: start, length: end - start)
    } else { displayRange = NSRange(location: 0, length: 0) }
    (layoutManager as? InlineCodeLayoutManager)?.sharedSelection = displayRange
    if selectedRange() != displayRange { setSelectedRange(displayRange) }
    needsDisplay = true
  }

  override func mouseDown(with event: NSEvent) {
    guard let selectionCoordinator else { super.mouseDown(with: event); return }
    if event.clickCount > 1 || event.modifierFlags.contains(.option) {
      selectionCoordinator.clear()
      super.mouseDown(with: event)
      selectionCoordinator.adoptNativeSelection(in: self)
      return
    }
    window?.makeFirstResponder(self)
    selectionMouseDown = event
    selectionDidDrag = false
    selectionCoordinator.begin(in: self, event: event)
  }

  override func mouseDragged(with event: NSEvent) {
    guard selectionMouseDown != nil else { super.mouseDragged(with: event); return }
    selectionDidDrag = true
    selectionCoordinator?.drag(event)
  }

  override func mouseUp(with event: NSEvent) {
    guard let down = selectionMouseDown else { super.mouseUp(with: event); return }
    selectionCoordinator?.endDrag()
    selectionMouseDown = nil
    if !selectionDidDrag, !down.modifierFlags.contains(.shift) {
      let index = characterIndexForInsertion(at: convert(down.locationInWindow, from: nil))
      if let textStorage, index < textStorage.length,
         let link = textStorage.attribute(.link, at: index, effectiveRange: nil) {
        clicked(onLink: link, at: index)
      }
    }
  }

  override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
    [.html] + super.writablePasteboardTypes.filter { $0 != .html }
  }

  var clipboardContent: MarkdownClipboardContent? {
    if let selection = selectionCoordinator, selection.selectedText != nil { return selection.clipboardContent }
    guard let textStorage, selectedRange().length > 0 else { return nil }
    let range = NSIntersectionRange(selectedRange(), NSRange(location: 0, length: textStorage.length))
    let text = InlineCodeStyle.unpadded(textStorage.attributedSubstring(from: range))
    return MarkdownClipboardContent(records: [.init(text: text, path: clipboardPath)], plainText: text.string)
  }

  // swiftlint:disable:next no_any
  override func copy(_ sender: Any?) {
    guard let content = clipboardContent else { super.copy(sender); return }
    content.write()
  }

  // swiftlint:disable:next no_any
  override func selectAll(_ sender: Any?) {
    guard let selectionCoordinator else { super.selectAll(sender); return }
    selectionCoordinator.selectAll()
  }

  override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    if item.action == #selector(copy(_:)), selectionCoordinator?.selectedText != nil { return true }
    return super.validateUserInterfaceItem(item)
  }

  override func keyDown(with event: NSEvent) {
    // Copy and Select All keep their shared range. Navigation continues using
    // AppKit's word/line movement, then updates the shared selection anchor.
    let shortcut = event.charactersIgnoringModifiers?.lowercased() ?? ""
    if event.modifierFlags.contains(.command), shortcut == "c" || shortcut == "a" {
      super.keyDown(with: event)
      return
    }
    let native = selectedRange()
    selectionCoordinator?.clear()
    setSelectedRange(native)
    super.keyDown(with: event)
    selectionCoordinator?.adoptNativeSelection(in: self)
  }
}
#endif
