//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import SwiftUI

/// Shares mouse selection across Markdown views belonging to one response.
/// Non-Markdown controls and collapsed content are not included.
public struct MarkdownSelectionGroup<Content: View>: View {
  private let content: Content
  #if canImport(AppKit)
  @StateObject private var selection = MarkdownSelectionCoordinator()
  #endif

  public init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  public var body: some View {
    #if canImport(AppKit)
    content.environment(\.markdownSelection, selection)
    #else
    content
    #endif
  }
}

extension EnvironmentValues {
  #if canImport(AppKit)
  @Entry var markdownSelection: MarkdownSelectionCoordinator?
  #endif
  @Entry var markdownSelectionSeparator = "\n\n"
}
