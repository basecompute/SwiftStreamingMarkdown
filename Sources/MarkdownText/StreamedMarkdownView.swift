//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI
import Equatable

/// A source of incremental Markdown text for `StreamedMarkdownView`.
///
/// Each value yielded by `text` is a *complete snapshot* of the Markdown
/// source so far (a growing prefix), not an incremental delta. The view
/// re-parses each snapshot and updates the rendered output.
public protocol StreamedMarkdownSource {
  var text: AsyncStream<String> { get }

  /// Called after a snapshot has been parsed and SwiftUI has applied the
  /// rendered document to its native view hierarchy. Sources can use this to
  /// coordinate completion without guessing how long parsing and view
  /// reconciliation took.
  func didRenderSnapshot(_ text: String) async
}

public extension StreamedMarkdownSource {
  func didRenderSnapshot(_ text: String) async {}
}

/// A SwiftUI view that incrementally parses and renders streamed Markdown.
///
/// Provide a `StreamedMarkdownSource` whose `text` async sequence yields
/// progressively larger snapshots of the Markdown source; the view re-parses
/// on each emission and refreshes the rendered output.
@Equatable
public struct StreamedMarkdownView: View {

  private let config: MarkdownRenderConfig
  @StateObject private var controller: StreamedMarkdownController

  /// Create a `StreamedMarkdownView`.
  /// - Parameters:
  ///   - source: The streamed Markdown source. Each emission must be the
  ///     complete Markdown source so far, not an incremental delta.
  ///   - config: Render configuration. Defaults to `.default`.
  ///   - listener: Optional listener that receives render and interaction events.
  public init(
    source: StreamedMarkdownSource,
    config: MarkdownRenderConfig = .default,
    listener: MarkdownListener? = nil
  ) {
    self.config = config
    _controller = StateObject(
      wrappedValue: StreamedMarkdownController(source: source, config: config, listener: listener)
    )
  }

  public var body: some View {
    DocumentView(
      renderableDocument: controller.markdownToRender,
      config: config,
      listener: controller.listener
    )
    .background {
      SnapshotApplicationObserver(revision: controller.renderRevision) { revision in
        controller.didApplySnapshot(revision)
      }
    }
    .task {
      await controller.start()
    }
    .onDisappear {
      Task {
        await controller.end()
      }
    }
  }
}

@MainActor
final class StreamedMarkdownController: ObservableObject {

  @Published var markdownToRender: RenderableDocument = .empty
  @Published private(set) var renderRevision = 0
  let config: MarkdownRenderConfig
  let listener: MarkdownListener?

  private let source: StreamedMarkdownSource
  private let parser = MarkdownParserImpl()
  private var task: Task<Void, Never>?
  private var pendingSnapshots: [Int: String] = [:]

  init(
    source: StreamedMarkdownSource,
    config: MarkdownRenderConfig,
    listener: MarkdownListener? = nil
  ) {
    self.source = source
    self.config = config
    self.listener = listener
  }

  func start() async {
    task?.cancel()
    task = Task { [weak self] in
      guard let self else { return }
      for await text in self.source.text {
        if Task.isCancelled { return }
        let renderable = await self.parser.parse(text: text, config: self.config)
        if Task.isCancelled { return }
        self.renderRevision &+= 1
        self.pendingSnapshots[self.renderRevision] = text
        self.markdownToRender = renderable
      }
    }
  }

  /// Called by a platform view after SwiftUI has applied a published document
  /// to its native view hierarchy. SwiftUI can coalesce revisions, so only the
  /// newest applied revision is acknowledged and older pending values are
  /// discarded rather than reported as rendered.
  func didApplySnapshot(_ revision: Int) {
    guard let text = pendingSnapshots[revision] else { return }
    pendingSnapshots = pendingSnapshots.filter { $0.key > revision }
    Task {
      await source.didRenderSnapshot(text)
    }
  }

  func end() async {
    task?.cancel()
    task = nil
    pendingSnapshots.removeAll()
  }
}

#if canImport(AppKit)
import AppKit

/// An AppKit reconciliation marker. `updateNSView` runs only after SwiftUI has
/// propagated the new revision through the view tree; dispatching once more on
/// the main queue lets sibling representables apply their content first.
private struct SnapshotApplicationObserver: NSViewRepresentable {
  let revision: Int
  let onApply: (Int) -> Void

  func makeNSView(context: Context) -> NSView {
    NSView(frame: .zero)
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    let revision = revision
    DispatchQueue.main.async {
      onApply(revision)
    }
  }
}
#elseif canImport(UIKit)
import UIKit

/// The UIKit equivalent of the SwiftUI reconciliation marker above.
private struct SnapshotApplicationObserver: UIViewRepresentable {
  let revision: Int
  let onApply: (Int) -> Void

  func makeUIView(context: Context) -> UIView {
    UIView(frame: .zero)
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    let revision = revision
    DispatchQueue.main.async {
      onApply(revision)
    }
  }
}
#endif
