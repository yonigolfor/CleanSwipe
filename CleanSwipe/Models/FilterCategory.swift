//
//  FilterCategory.swift
//  CleanSwipe
//
//  קטגוריות "Easy Targets" לסינון מהיר
//

import SwiftUI

enum FilterCategory: String, CaseIterable, Identifiable {
    case screenshots = "Screenshots"
    case screenRecordings = "Screen Recordings"
    case largeVideos = "Large Videos"
    case blurryPhotos = "Blurry Photos"
    case all = "All Photos"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .screenshots: return "camera.viewfinder"
        case .screenRecordings: return "record.circle"
        case .largeVideos: return "film"
        case .blurryPhotos: return "eye.slash"
        case .all: return "photo.stack"
        }
    }
    
    var color: Color {
        switch self {
        case .screenshots: return .blue
        case .screenRecordings: return .purple
        case .largeVideos: return .orange
        case .blurryPhotos: return .red
        case .all: return .gray
        }
    }
    
    var description: String {
        switch self {
        case .screenshots: return "Usually the first to go"
        case .screenRecordings: return "High-weight items"
        case .largeVideos: return "Sorted by file size"
        case .blurryPhotos: return "Low-focus images"
        case .all: return "Everything in your library"
        }
    }
}
