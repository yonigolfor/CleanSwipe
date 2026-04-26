import Foundation
import Photos
import BackgroundTasks

// MARK: - Notification Scheduler Service
class NotificationScheduler {
    static let shared = NotificationScheduler()
    
    private let notificationManager = NotificationManager.shared
    
    private var userDefaults: UserDefaults {
            UserDefaults.standard
        }
    
    // Background task identifier
    static let backgroundTaskIdentifier = "com.cleanswipe.notification.check"

    private init() {}
    
    // MARK: - Main Scheduler Entry Point
    
    /// Call this when app becomes active or after user performs actions
    func evaluateAndScheduleNotifications() {
        print("📋 Evaluating notification triggers...")
        
        // Check all triggers
        checkReviewBinStatus()
        checkMediaBurstStatus()
        checkStorageMilestone()
        scheduleWeeklyCleanup()
    }
    
    // MARK: - Review Bin Trigger
    
    private func checkReviewBinStatus() {
        // Get review bin items from UserDefaults
        guard let binData = userDefaults.data(forKey: "reviewBinItems"),
              let binItems = try? JSONDecoder().decode([ProcessedAsset].self, from: binData) else {
            print("No items in review bin")
            return
        }
        
        let deletedItems = binItems.filter { $0.action == .deleted }
        
        guard !deletedItems.isEmpty else {
            print("Review bin is empty, cancelling reminder")
            notificationManager.cancelReviewBinReminder()
            return
        }
        
        // Calculate total size
        var totalSize: Int64 = 0
        
        let fetchOptions = PHFetchOptions()
        let identifiers = deletedItems.map { $0.assetId }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: fetchOptions)
        
        assets.enumerateObjects { asset, _, _ in
            // Estimate size (rough calculation)
            let resources = PHAssetResource.assetResources(for: asset)
            for resource in resources {
                if let size = resource.value(forKey: "fileSize") as? Int64 {
                    totalSize += size
                }
            }
        }
        
        // Check if we've already scheduled a reminder recently
        if let lastScheduled = userDefaults.object(forKey: "lastReviewBinReminderScheduled") as? Date {
            let hoursSinceScheduled = Date().timeIntervalSince(lastScheduled) / 3600
            
            // Don't spam - only reschedule if it's been more than 12 hours
            guard hoursSinceScheduled > 12 else {
                print("Review bin reminder already scheduled recently")
                return
            }
        }
        
        print("📌 Scheduling review bin reminder: \(deletedItems.count) items, \(formatBytes(totalSize))")
        notificationManager.scheduleReviewBinReminder(binSize: totalSize, itemCount: deletedItems.count)
    }
    
    // MARK: - Media Burst Trigger
    
    private func checkMediaBurstStatus() {
        // Request photo library authorization first
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        guard status == .authorized || status == .limited else {
            print("No photo library access for burst detection")
            return
        }
        
        print("🔍 Checking for media burst...")
        notificationManager.checkForMediaBurst()
    }
    
    // MARK: - Storage Milestone Trigger
    
    private func checkStorageMilestone() {
        // Calculate total saved from processed assets
        guard let processedData = userDefaults.data(forKey: "processedAssets"),
              let processedAssets = try? JSONDecoder().decode([ProcessedAsset].self, from: processedData) else {
            print("No processed assets found")
            return
        }
        
        let deletedAssets = processedAssets.filter { $0.action == .deleted }
        
        var totalSaved: Int64 = 0
        
        let fetchOptions = PHFetchOptions()
        let identifiers = deletedAssets.map { $0.assetId }
        
        // Fetch in batches to avoid memory issues
        let batchSize = 100
        for i in stride(from: 0, to: identifiers.count, by: batchSize) {
            let end = min(i + batchSize, identifiers.count)
            let batchIdentifiers = Array(identifiers[i..<end])
            
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: batchIdentifiers, options: fetchOptions)
            
            assets.enumerateObjects { asset, _, _ in
                let resources = PHAssetResource.assetResources(for: asset)
                for resource in resources {
                    if let size = resource.value(forKey: "fileSize") as? Int64 {
                        totalSaved += size
                    }
                }
            }
        }
        
        print("💾 Total saved: \(formatBytes(totalSaved))")
        notificationManager.checkStorageMilestone(totalSaved: totalSaved)
    }
    
    // MARK: - Weekly Cleanup Trigger
    
    private func scheduleWeeklyCleanup() {
        // Calculate this week's savings
        let calendar = Calendar.current
        let now = Date()
        
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else {
            return
        }
        
        // Get processed assets from this week
        guard let processedData = userDefaults.data(forKey: "processedAssets"),
              let processedAssets = try? JSONDecoder().decode([ProcessedAsset].self, from: processedData) else {
            // Schedule anyway with zero savings
            notificationManager.scheduleWeeklyCleanup(weeklySaved: 0)
            return
        }
        
        let weeklyDeleted = processedAssets.filter {
            $0.action == .deleted && $0.timestamp >= weekStart
        }
        
        var weeklySaved: Int64 = 0
        
        if !weeklyDeleted.isEmpty {
            let identifiers = weeklyDeleted.map { $0.assetId }
            let fetchOptions = PHFetchOptions()
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: fetchOptions)
            
            assets.enumerateObjects { asset, _, _ in
                let resources = PHAssetResource.assetResources(for: asset)
                for resource in resources {
                    if let size = resource.value(forKey: "fileSize") as? Int64 {
                        weeklySaved += size
                    }
                }
            }
        }
        
        print("📅 Weekly saved: \(formatBytes(weeklySaved))")
        notificationManager.scheduleWeeklyCleanup(weeklySaved: weeklySaved)
    }
    
    // MARK: - Background Task Registration
    
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundTask(task: task as! BGAppRefreshTask)
        }
        
        print("✅ Background task registered")
    }
    
    func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        
        // Schedule for next day
        request.earliestBeginDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Background task scheduled")
        } catch {
            print("❌ Could not schedule background task: \(error)")
        }
    }
    
    private func handleBackgroundTask(task: BGAppRefreshTask) {
        // Schedule next background task
        scheduleBackgroundTask()
        
        // Set expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        // Evaluate notifications
        evaluateAndScheduleNotifications()
        
        // Mark task as completed
        task.setTaskCompleted(success: true)
    }
    
    // MARK: - Helpers
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Extension for NotificationManager
extension NotificationManager {
    func cancelReviewBinReminder() {
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [NotificationCategory.reviewBinReminder.rawValue]
        )
    }
}

// MARK: - ProcessedAsset Model (should match your existing model)
struct ProcessedAsset: Codable {
    let assetId: String
    let action: MediaAction
    let timestamp: Date
}

enum MediaAction: String, Codable {
    case saved
    case deleted
}
