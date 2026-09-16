//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import XCTest
@testable import SwiftStreamingMarkdown

/// Pins the contract between the preprocessor and the bundled typesetter
/// fork: constructs the preprocessor deliberately leaves alone must
/// typeset cleanly, with no placeholders.
final class LatexCoverageTests: XCTestCase {

  func testNativeSyntaxesTypesetWithoutRewrites() {
    let sources = [
      "\\angle CB'B = 90",
      "f''(x) + f'(x)^2",
      "\\text{Newton's second law}: F = ma",
      "\\dfrac{\\partial f}{\\partial x} + \\tfrac{1}{2}",
      "\\overrightarrow{AB} + \\overrightarrow{BC}",
      "p \\implies q",
      "A + B \\rightleftharpoons C",
      "\\varphi(x) = f(x) - \\big(f(a) + f'(a)(x-a)\\big)",
    ]
    for source in sources {
      XCTAssertNil(LatexCoverage.rejectedForm(of: source), source)
    }
  }

  func testUnknownCommandIsReportedAsPlaceholder() {
    let rejected = LatexCoverage.rejectedForm(of: "a \\notacommand b")
    XCTAssertNotNil(rejected)
    XCTAssertTrue(rejected?.hasPrefix("[1 placeholder(s)]") == true, rejected ?? "nil")
  }
}
