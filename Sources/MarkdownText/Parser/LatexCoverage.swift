//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import iosMath

/// Diagnostic surface for hosts: runs a raw display-math source through
/// the same preprocessing the renderer uses and reports whether the
/// typesetter can parse the result. Lets integration harnesses measure
/// LaTeX coverage without reaching into internal types.
public enum LatexCoverage {
  /// nil when the formula typesets; otherwise the processed source the
  /// typesetter rejected.
  public static func rejectedForm(of raw: String) -> String? {
    let processed = LaTexPreProcessorImpl()
      .process(input: "$$\n" + raw + "\n$$",
               matchingRules: MarkdownParseOption.LatexMatching.allCases)
    let latex = processed
      .replacingOccurrences(of: "```blockmath", with: "")
      .replacingOccurrences(of: "```", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let builder = MTMathListBuilder(string: latex)
    let list = builder.build()
    if list != nil, builder.error == nil {
      if builder.numberOfUnknownCommands > 0 {
        return "[\(builder.numberOfUnknownCommands) placeholder(s)] \(latex)"
      }
      return nil
    }
    let reason = builder.error?.localizedDescription ?? "no output"
    return "[\(reason)] \(latex)"
  }
}
