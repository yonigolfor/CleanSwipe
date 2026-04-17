import SwiftUI

// Stores user decisions persistently
class PersistenceService {
    static let shared = PersistenceService()
    
    @AppStorage("keptPhotoIDs") private var keptIDsData: Data = Data()
    @AppStorage("lastCleanupDate") private var lastCleanupTimestamp: Double = 0
    @AppStorage("totalSpaceSavedLifetime") private var _totalSpaceSavedLifetime: Double = 0
    @AppStorage("reviewBinIDs") private var reviewBinIDsData: Data = Data()
    @AppStorage("reviewBinSpaceSaved") private var _reviewBinSpaceSaved: Double = 0

    var reviewBinSpaceSaved: Int64 {
        get { Int64(_reviewBinSpaceSaved) }
        set { _reviewBinSpaceSaved = Double(newValue) }
    }
    var reviewBinIDs: [String] {
        get {
            (try? JSONDecoder().decode([String].self, from: reviewBinIDsData)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                reviewBinIDsData = data
            }
        }
    }
    var totalSpaceSavedLifetime: Int64 {
        get { Int64(_totalSpaceSavedLifetime) }
        set { _totalSpaceSavedLifetime = Double(newValue) }
    }
    
    private init() {}
    
    var keptPhotoIDs: Set<String> {
        get {
            guard let ids = try? JSONDecoder().decode(Set<String>.self, from: keptIDsData) else {
                return []
            }
            return ids
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                keptIDsData = data
            }
        }
    }
    
    var lastCleanupDate: Date {
        get { Date(timeIntervalSince1970: lastCleanupTimestamp) }
        set { lastCleanupTimestamp = newValue.timeIntervalSince1970 }
    }
    
    func saveKeptID(_ id: String) {
        var current = keptPhotoIDs
        current.insert(id)
        keptPhotoIDs = current
    }
    
    func removeKeptID(_ id: String) {
        var current = keptPhotoIDs
        current.remove(id)
        keptPhotoIDs = current
    }
    
    // Reset every 30 days
    func shouldResetProgress() -> Bool {
        if lastCleanupTimestamp == 0 { return false }
        return Date().timeIntervalSince(lastCleanupDate) > 30 * 24 * 60 * 60
    }
    
    func resetIfOld() {
        if shouldResetProgress() {
            keptPhotoIDs = []
            lastCleanupDate = Date().timeIntervalSince1970 == 0 ? Date() : Date()
            lastCleanupTimestamp = Date().timeIntervalSince1970
        }
    }
}
