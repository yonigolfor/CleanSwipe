import Foundation
import UserNotifications
import Photos

// MARK: - Notification Manager
class NotificationManager {
    static let shared = NotificationManager()
    
    let notificationCenter = UNUserNotificationCenter.current()
    
    private var userDefaults: UserDefaults {
            UserDefaults.standard
    }
    
    // Notification Categories
    enum NotificationCategory: String {
        case reviewBinReminder = "REVIEW_BIN_REMINDER"
        case mediaBurst = "MEDIA_BURST"
        case storageMilestone = "STORAGE_MILESTONE"
        case weeklyCleanup = "WEEKLY_CLEANUP"
    }
    
    // Action Identifiers
    enum NotificationAction: String {
        case openReviewBin = "OPEN_REVIEW_BIN"
        case startSorting = "START_SORTING"
        case deleteNow = "DELETE_NOW"
        case dismiss = "DISMISS"
    }
    
    private init() {
        setupNotificationCategories()
    }
    
    // MARK: - Setup & Authorization
    
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    private func setupNotificationCategories() {
        // Review Bin Category with Actions
        let openBinAction = UNNotificationAction(
            identifier: NotificationAction.openReviewBin.rawValue,
            title: "נקה עכשיו",
            options: [.foreground]
        )
        
        let deleteNowAction = UNNotificationAction(
            identifier: NotificationAction.deleteNow.rawValue,
            title: "מחק הכל",
            options: [.destructive, .foreground]
        )
        
        let reviewBinCategory = UNNotificationCategory(
            identifier: NotificationCategory.reviewBinReminder.rawValue,
            actions: [openBinAction, deleteNowAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // Media Burst Category with Actions
        let startSortingAction = UNNotificationAction(
            identifier: NotificationAction.startSorting.rawValue,
            title: "בוא נמיין",
            options: [.foreground]
        )
        
        let mediaBurstCategory = UNNotificationCategory(
            identifier: NotificationCategory.mediaBurst.rawValue,
            actions: [startSortingAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Storage Milestone Category
        let storageMilestoneCategory = UNNotificationCategory(
            identifier: NotificationCategory.storageMilestone.rawValue,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        
        // Weekly Cleanup Category
        let weeklyCleanupCategory = UNNotificationCategory(
            identifier: NotificationCategory.weeklyCleanup.rawValue,
            actions: [startSortingAction],
            intentIdentifiers: [],
            options: []
        )
        
        notificationCenter.setNotificationCategories([
            reviewBinCategory,
            mediaBurstCategory,
            storageMilestoneCategory,
            weeklyCleanupCategory
        ])
    }
    
    // MARK: - Trigger 1: Review Bin Reminder (24h after items left in bin)
    
    func scheduleReviewBinReminder(binSize: Int64, itemCount: Int) {
        // Cancel existing reminder
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [NotificationCategory.reviewBinReminder.rawValue]
        )
        
        // Don't schedule if bin is empty
        guard itemCount > 0 else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "העבודה הקשה כמעט הסתיימה! 🏁"
        
        let sizeString = formatFileSize(binSize)
        content.body = "\(sizeString) מחכים ב'סל המחזור'. לחיצה אחת והם נעלמים לנצח. בוא נפנה את המקום הזה."
        
        content.sound = .default
        content.badge = itemCount as NSNumber
        content.categoryIdentifier = NotificationCategory.reviewBinReminder.rawValue
        
        // Add contextual data
        content.userInfo = [
            "binSize": binSize,
            "itemCount": itemCount,
            "triggerType": "reviewBin"
        ]
        
        // Schedule for 24 hours from now
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 24 * 60 * 60, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: NotificationCategory.reviewBinReminder.rawValue,
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error scheduling review bin reminder: \(error)")
            } else {
                print("✅ Review bin reminder scheduled for 24h from now")
            }
        }
        
        // Save timestamp
        userDefaults.set(Date(), forKey: "lastReviewBinReminderScheduled")
    }
    
    // MARK: - Trigger 2: Media Burst Detection (50+ new photos)
    
    func checkForMediaBurst() {
        // Get photos from last 24 hours
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "creationDate > %@",
            oneDayAgo as NSDate
        )
        fetchOptions.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]
        
        let recentPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        let recentVideos = PHAsset.fetchAssets(with: .video, options: fetchOptions)
        
        let totalCount = recentPhotos.count + recentVideos.count
        
        // Check if we already notified about this burst
        let lastBurstCount = userDefaults.integer(forKey: "lastMediaBurstCount")
        let lastBurstDate = userDefaults.object(forKey: "lastMediaBurstDate") as? Date ?? Date.distantPast
        
        // Only notify if:
        // 1. We have 50+ new items
        // 2. We haven't notified about this batch yet (or it was more than 2 days ago)
        guard totalCount >= 50 else { return }
        guard totalCount > lastBurstCount || Date().timeIntervalSince(lastBurstDate) > 2 * 24 * 60 * 60 else {
            return
        }
        
        // Schedule notification for 1 day after detection
        scheduleMediaBurstNotification(photoCount: totalCount, latestAsset: recentPhotos.firstObject)
        
        // Save burst info
        userDefaults.set(totalCount, forKey: "lastMediaBurstCount")
        userDefaults.set(Date(), forKey: "lastMediaBurstDate")
    }
    
    private func scheduleMediaBurstNotification(photoCount: Int, latestAsset: PHAsset?) {
        // Cancel existing burst notification
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [NotificationCategory.mediaBurst.rawValue]
        )
        
        let content = UNMutableNotificationContent()
        content.title = "איזה יום פוטוגני! 📸"
        content.body = "צילמת \(photoCount) תמונות חדשות. בוא נבחר את ה-Top 10 וננקה את השאר לפני שהן נערמות."
        
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.mediaBurst.rawValue
        
        content.userInfo = [
            "photoCount": photoCount,
            "triggerType": "mediaBurst"
        ]
        
        // Try to attach thumbnail of latest photo
        if let latestAsset = latestAsset {
            attachThumbnail(to: content, asset: latestAsset) { updatedContent in
                self.scheduleNotification(
                    identifier: NotificationCategory.mediaBurst.rawValue,
                    content: updatedContent,
                    afterSeconds: 6 * 60 * 60 // 6 hours after detection
                )
            }
        } else {
            scheduleNotification(
                identifier: NotificationCategory.mediaBurst.rawValue,
                content: content,
                afterSeconds: 6 * 60 * 60
            )
        }
    }
    
    // MARK: - Trigger 3: Storage Milestone (Achievements)
    
    func checkStorageMilestone(totalSaved: Int64) {
        let milestones: [Int64] = [
            1_000_000_000,      // 1 GB
            5_000_000_000,      // 5 GB
            10_000_000_000,     // 10 GB
            50_000_000_000,     // 50 GB
            100_000_000_000     // 100 GB
        ]
        
        // Get last celebrated milestone
        let lastMilestone = userDefaults.object(forKey: "lastCelebratedMilestone") as? Int64 ?? 0
        
        // Find the next milestone we've crossed
        for milestone in milestones {
            if totalSaved >= milestone && lastMilestone < milestone {
                scheduleMilestoneNotification(milestone: milestone, totalSaved: totalSaved)
                userDefaults.set(milestone, forKey: "lastCelebratedMilestone")
                break
            }
        }
    }
    
    private func scheduleMilestoneNotification(milestone: Int64, totalSaved: Int64) {
        let content = UNMutableNotificationContent()
        content.title = "הישג חדש! 🏆"
        
        let savedString = formatFileSize(totalSaved)
        content.body = "וואו! חסכת כבר \(savedString). אתה אלוף הניקיון!"
        
        content.sound = UNNotificationSound(named: UNNotificationSoundName("achievement.wav"))
        content.categoryIdentifier = NotificationCategory.storageMilestone.rawValue
        
        content.userInfo = [
            "milestone": milestone,
            "totalSaved": totalSaved,
            "triggerType": "milestone"
        ]
        
        // Schedule immediately
        scheduleNotification(
            identifier: "milestone_\(milestone)",
            content: content,
            afterSeconds: 1
        )
    }
    
    // MARK: - Trigger 4: Weekly Cleanup (Sunday Morning)
    
    func scheduleWeeklyCleanup(weeklySaved: Int64) {
        // Cancel existing weekly notification
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [NotificationCategory.weeklyCleanup.rawValue]
        )
        
        let content = UNMutableNotificationContent()
        content.title = "הטלפון שלך מרגיש קל יותר!🌿"
        
        if weeklySaved > 0 {
            let savedString = formatFileSize(weeklySaved)
            content.body = "השבוע פינית \(savedString)!"
        } else {
            content.body = "כנס עכשיו ותמשיך במומנטום"
        }
        
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.weeklyCleanup.rawValue
        
        content.userInfo = [
            "weeklySaved": weeklySaved,
            "triggerType": "weeklyCleanup"
        ]
        
        // Schedule for next Sunday at 9 AM
        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // Sunday
        dateComponents.hour = 21
        dateComponents.minute = 33
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: NotificationCategory.weeklyCleanup.rawValue,
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error scheduling weekly cleanup: \(error)")
            } else {
                print("✅ Weekly cleanup scheduled for Sundays at 9 AM")
            }
        }
    }
    
    // MARK: - Helper: Attach Thumbnail to Notification
    
    private func attachThumbnail(to content: UNMutableNotificationContent, asset: PHAsset, completion: @escaping (UNMutableNotificationContent) -> Void) {
        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        let targetSize = CGSize(width: 300, height: 300)
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            guard let image = image else {
                completion(content)
                return
            }
            
            // Save image to temp directory
            let tempDirectory = FileManager.default.temporaryDirectory
            let fileName = UUID().uuidString + ".jpg"
            let fileURL = tempDirectory.appendingPathComponent(fileName)
            
            if let data = image.jpegData(compressionQuality: 0.8) {
                do {
                    try data.write(to: fileURL)
                    
                    // Create attachment
                    if let attachment = try? UNNotificationAttachment(
                        identifier: "thumbnail",
                        url: fileURL,
                        options: nil
                    ) {
                        content.attachments = [attachment]
                    }
                } catch {
                    print("Error saving thumbnail: \(error)")
                }
            }
            
            completion(content)
        }
    }
    
    // MARK: - Helper: Schedule Notification
    
    private func scheduleNotification(identifier: String, content: UNMutableNotificationContent, afterSeconds: TimeInterval) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: afterSeconds, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error scheduling notification '\(identifier)': \(error)")
            } else {
                print("✅ Notification '\(identifier)' scheduled for \(afterSeconds)s from now")
            }
        }
    }
    
    // MARK: - Helper: Format File Size
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Cancel All Notifications
    
    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
        print("🗑️ All notifications cancelled")
    }
    
    // MARK: - Get Pending Notifications (for debugging)
    
    func getPendingNotifications(completion: @escaping ([UNNotificationRequest]) -> Void) {
        notificationCenter.getPendingNotificationRequests { requests in
            completion(requests)
        }
    }
}
