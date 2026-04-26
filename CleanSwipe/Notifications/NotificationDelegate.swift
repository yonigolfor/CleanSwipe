import Foundation
import UserNotifications
import SwiftUI

// MARK: - Notification Delegate
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    
    // Closure to handle deep links
    var onNotificationTapped: ((String, [AnyHashable: Any]) -> Void)?
    
    private override init() {
        super.init()
    }
    
    // MARK: - Handle Notification When App is in Foreground
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // MARK: - Handle Notification Response (User Tapped)
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier
        
        print("📬 Notification action: \(actionIdentifier)")
        print("📦 User info: \(userInfo)")
        
        // Handle different actions
        switch actionIdentifier {
        case NotificationManager.NotificationAction.openReviewBin.rawValue:
            handleOpenReviewBin()
            
        case NotificationManager.NotificationAction.deleteNow.rawValue:
            handleDeleteNow(userInfo: userInfo)
            
        case NotificationManager.NotificationAction.startSorting.rawValue:
            handleStartSorting()
            
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification itself (not an action button)
            handleDefaultAction(userInfo: userInfo)
            
        default:
            break
        }
        
        // Call completion handler
        completionHandler()
    }
    
    // MARK: - Action Handlers
    
    private func handleOpenReviewBin() {
        print("🗑️ Opening Review Bin...")
        onNotificationTapped?("reviewBin", [:])
    }
    
    private func handleDeleteNow(userInfo: [AnyHashable: Any]) {
        print("🗑️ Delete Now triggered")
        
        // Navigate to review bin and trigger delete all
        onNotificationTapped?("reviewBin", ["autoDelete": true])
    }
    
    private func handleStartSorting() {
        print("📸 Start Sorting triggered")
        onNotificationTapped?("sorting", [:])
    }
    
    private func handleDefaultAction(userInfo: [AnyHashable: Any]) {
        // Determine action based on trigger type
        if let triggerType = userInfo["triggerType"] as? String {
            switch triggerType {
            case "reviewBin":
                handleOpenReviewBin()
                
            case "mediaBurst":
                handleStartSorting()
                
            case "milestone":
                // Show statistics screen
                onNotificationTapped?("statistics", userInfo)
                
            case "weeklyCleanup":
                handleStartSorting()
                
            default:
                // Open main screen
                onNotificationTapped?("main", [:])
            }
        }
    }
}

// MARK: - App Delegate Setup Helper
extension NotificationDelegate {
    func setupInApp() {
        UNUserNotificationCenter.current().delegate = self
        
        // Set up deep link handler
        onNotificationTapped = { destination, params in
            // Post notification for app to handle
            NotificationCenter.default.post(
                name: NSNotification.Name("DeepLinkReceived"),
                object: nil,
                userInfo: ["destination": destination, "params": params]
            )
        }
    }
}
