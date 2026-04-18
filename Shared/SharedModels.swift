//
//  SharedModels.swift
//  Shared between CleanSwipe & SwipeWidget
//

import Foundation

/// suiteName חייב להיות זהה בשני ה-Targets
let appGroupSuiteName = "group.com.yonigolfor.cleanswipe"

struct WidgetAssetInfo: Codable {
    let localIdentifier: String
    let isVideo: Bool
    let creationDate: Date?
}

enum WidgetAction: String {
    case keep = "keep"
    case delete = "delete"
}
