//
//  WidgetSyncService.swift
//  CleanSwipe
//

import Photos
import WidgetKit

class WidgetSyncService {
    static let shared = WidgetSyncService()
    private let defaults = UserDefaults(suiteName: appGroupSuiteName)!

    private init() {}

    /// מעדכן את הווידג'ט עם ה-Asset הבא בתור
    func pushNextAsset(_ item: PhotoItem) {
        let info = WidgetAssetInfo(
            localIdentifier: item.asset.localIdentifier,
            isVideo: item.isVideo,
            creationDate: item.creationDate
        )
        if let data = try? JSONEncoder().encode(info) {
            defaults.set(data, forKey: "widgetCurrentAsset")
        }
        // שמור thumbnail ב-App Group
        PhotoLibraryService.shared.loadImage(
            for: item.asset,
            targetSize: CGSize(width: 400, height: 400)
        ) { image in
            if let image, let jpegData = image.jpegData(compressionQuality: 0.8) {
                self.defaults.set(jpegData, forKey: "widgetThumbnail")
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// שומר את רשימת ה-IDs שכבר טופלו (כדי שהווידג'ט לא יציג אותם)
    func syncProcessedIDs(_ ids: Set<String>) {
        if let data = try? JSONEncoder().encode(Array(ids)) {
            defaults.set(data, forKey: "widgetProcessedIDs")
        }
    }

    /// קורא פעולה שהווידג'ט ביצע (keep/delete)
    func pendingWidgetAction() -> (id: String, action: WidgetAction)? {
        guard
            let id = defaults.string(forKey: "widgetPendingActionID"),
            let actionRaw = defaults.string(forKey: "widgetPendingAction"),
            let action = WidgetAction(rawValue: actionRaw)
        else { return nil }
        return (id, action)
    }

    /// מנקה את הפעולה הממתינה אחרי שהאפליקציה טיפלה בה
    func clearPendingAction() {
        defaults.removeObject(forKey: "widgetPendingActionID")
        defaults.removeObject(forKey: "widgetPendingAction")
    }
}
