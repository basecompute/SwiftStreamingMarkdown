//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

@testable import SwiftStreamingMarkdown
import XCTest

final class TableLayoutTests: XCTestCase {
  func testNarrowColumnsExpandToViewportWidth() {
    let widths = TableLayout.expandedColumnWidths(
      [104, 200],
      maximumWidths: [320, 320],
      minimumTotalWidth: 640
    )

    XCTAssertEqual(widths, [320, 320])
  }

  func testWideTableKeepsItsScrollableWidth() {
    let widths = TableLayout.expandedColumnWidths(
      [200, 200, 200, 200],
      maximumWidths: [200, 200, 200, 200],
      minimumTotalWidth: 640
    )

    XCTAssertEqual(widths.reduce(0, +), 800)
  }

  func testCappedColumnGivesRemainingSpaceToOtherColumns() {
    let widths = TableLayout.expandedColumnWidths(
      [80, 100, 150],
      maximumWidths: [100, 250, 250],
      minimumTotalWidth: 500
    )

    XCTAssertEqual(widths[0], 100)
    XCTAssertEqual(widths.reduce(0, +), 500, accuracy: 0.001)
  }
}
