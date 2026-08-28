//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI

struct ThematicBreakView: View {

  @Environment(\.markdownConfig) var config: MarkdownRenderConfig

  var body: some View {
    // Divider ignores foregroundColor on macOS/iOS, which left the rule
    // at the faint system default regardless of configuration. Paint the
    // configured color explicitly, at a visible weight.
    Rectangle()
      .fill(config.thematicBreakColor)
      .frame(height: 2)
      .frame(maxWidth: .infinity)
      .padding([.top, .bottom], 9)
      .transition(.opacity)
  }
}
