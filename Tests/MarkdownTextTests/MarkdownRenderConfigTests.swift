//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

@testable import SwiftStreamingMarkdown
import XCTest

final class MarkdownRenderConfigTests: XCTestCase {

  func testTextAnimationTimingPreservesExistingDefaults() {
    let config = MarkdownRenderConfig.default

    XCTAssertEqual(config.textAnimationDuration, 0.5)
    XCTAssertEqual(config.textAnimationStaggerDuration, 0.1)
  }

  func testTextAnimationTimingCanBeCustomized() {
    let config = MarkdownRenderConfig(
      shouldAnimateText: true,
      textAnimationDuration: 0.2,
      textAnimationStaggerDuration: 0.04
    )

    XCTAssertTrue(config.shouldAnimateText)
    XCTAssertEqual(config.textAnimationDuration, 0.2)
    XCTAssertEqual(config.textAnimationStaggerDuration, 0.04)
  }

  func testBuildersPreserveTextAnimationTiming() {
    let config = MarkdownRenderConfig(
      textAnimationDuration: 0.2,
      textAnimationStaggerDuration: 0.04
    )

    let updatedConfig = config.withBlockSpacing(value: 12)

    XCTAssertEqual(updatedConfig.textAnimationDuration, 0.2)
    XCTAssertEqual(updatedConfig.textAnimationStaggerDuration, 0.04)
  }
}
