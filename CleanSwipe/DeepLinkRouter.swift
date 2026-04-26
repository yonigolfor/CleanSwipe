//
//  DeepLinkRouter.swift
//  CleanSwipe
//
//  Created by Yoni Golfor on 26/04/2026.
//

import Foundation
import SwiftUI

// MARK: - Deep Link Router (for SwiftUI navigation)
class DeepLinkRouter: ObservableObject {
    @Published var selectedTab: Int = 0
    @Published var shouldShowMilestoneAlert: Bool = false
    @Published var milestoneMessage: String = ""
    
    func handleDeepLink(destination: String, params: [AnyHashable: Any]) {
        DispatchQueue.main.async {
            switch destination {
            case "reviewBin":
                // Navigate to Review Bin tab
                self.selectedTab = 2
                
                // If auto-delete is requested, show alert
                if let autoDelete = params["autoDelete"] as? Bool, autoDelete {
                    print("⚠️ Auto-delete triggered from notification - navigate to Review Bin")
                }
                
            case "statistics", "milestone":
                // Show milestone celebration, then navigate to main
                if let totalSaved = params["totalSaved"] as? Int64 {
                    let savedString = ByteCountFormatter.string(fromByteCount: totalSaved, countStyle: .file)
                    self.milestoneMessage = "🏆 וואו! חסכת כבר \(savedString)!\nאתה אלוף הניקיון!"
                    self.shouldShowMilestoneAlert = true
                }
                self.selectedTab = 0 // Navigate to main after showing alert
                
            case "sorting", "main":
                // Navigate to main swipe tab
                self.selectedTab = 0
                
            default:
                self.selectedTab = 0
            }
        }
    }
}
