import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        
        // Setup notification delegate
        NotificationDelegate.shared.setupInApp()
        
        // Request notification authorization
        NotificationManager.shared.requestAuthorization { granted in
            if granted {
                print("✅ Notification authorization granted")
                
                // Register background tasks
                NotificationScheduler.shared.registerBackgroundTasks()
                
                // Evaluate and schedule initial notifications
                NotificationScheduler.shared.evaluateAndScheduleNotifications()
                
                // Schedule background task
                NotificationScheduler.shared.scheduleBackgroundTask()
            } else {
                print("❌ Notification authorization denied")
            }
        }
        
        return true
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Re-evaluate notifications when app becomes active
        NotificationScheduler.shared.evaluateAndScheduleNotifications()
        
        // Clear badge
        UIApplication.shared.applicationIconBadgeNumber = 0
        
        // Debug: Show pending notifications
        #if DEBUG
        NotificationManager.shared.getPendingNotifications { requests in
            print("📬 Pending notifications: \(requests.count)")
            for request in requests {
                print("  - \(request.content.title)")
            }
        }
        #endif
    }
}
