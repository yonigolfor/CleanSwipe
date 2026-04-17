//
//  PhotoLibraryService.swift
//  CleanSwipe
//
//  ניהול גישה לגלריית התמונות
//

import Photos
import UIKit

/// שירות לגישה ל-Photo Library
class PhotoLibraryService: ObservableObject {
    static let shared = PhotoLibraryService()
    
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var allPhotos: [PhotoItem] = []
    
    private let imageManager = PHCachingImageManager()
    private var fetchResult: PHFetchResult<PHAsset>?
    
    private init() {
        checkAuthorization()
    }
    
    // MARK: - Authorization
    
    func checkAuthorization() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
    
    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            self.authorizationStatus = status
        }
        return status == .authorized || status == .limited
    }
    
    // MARK: - Fetch Photos
    
    /// טעינת כל התמונות מהגלריה
    func fetchAllPhotos() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        fetchResult = PHAsset.fetchAssets(with: options)
        
        guard let fetchResult = fetchResult else { return }
        
        var items: [PhotoItem] = []
        fetchResult.enumerateObjects { asset, _, _ in
            items.append(PhotoItem(asset: asset))
        }
        
        self.allPhotos = items
    }
    
    /// סינון לפי קטגוריה
    func fetchPhotos(for category: FilterCategory) -> [PhotoItem] {
        guard let fetchResult = fetchResult else { return [] }
        
        var items: [PhotoItem] = []
        
        fetchResult.enumerateObjects { asset, _, _ in
            let item = PhotoItem(asset: asset)
            
            switch category {
            case .all:
                items.append(item)
                
            case .screenshots:
                if item.isScreenshot {
                    items.append(item)
                }
                
            case .screenRecordings:
                if item.isScreenRecording {
                    items.append(item)
                }
                
            case .largeVideos:
                if item.isVideo && item.fileSize > 50_000_000 { // > 50MB
                    items.append(item)
                }
                
            case .blurryPhotos:
                // TODO: יש להוסיף בדיקת blur עם Vision Framework
                // כרגע נחזיר תמונות רגילות
                if !item.isVideo && !item.isScreenshot {
                    items.append(item)
                }
            }
        }
        
        // מיון לפי גודל קובץ (הגדולים ראשונים)
        if category == .largeVideos {
            items.sort { $0.fileSize > $1.fileSize }
        }
        
        return items
    }
    
    // MARK: - Image Loading
    
    /// טעינת תמונה עבור asset
    func loadImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }
    
    /// Start caching עבור assets
    func startCaching(for items: [PhotoItem], targetSize: CGSize) {
        let assets = items.map { $0.asset }
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }
    
    /// Stop caching
    func stopCaching(for items: [PhotoItem]) {
        let assets = items.map { $0.asset }
        imageManager.stopCachingImages(
            for: assets,
            targetSize: .zero,
            contentMode: .aspectFill,
            options: nil
        )
    }
    
    // MARK: - Deletion
    
    /// מחיקת assets
    func deleteAssets(_ assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }
    
    /// ספירת פריטים לפי קטגוריה
    func count(for category: FilterCategory) -> Int {
        guard let fetchResult = fetchResult else { return 0 }
        
        var count = 0
        
        fetchResult.enumerateObjects { asset, _, stop in
            let item = PhotoItem(asset: asset)
            
            switch category {
            case .all:
                count += 1
                
            case .screenshots:
                if item.isScreenshot { count += 1 }
                
            case .screenRecordings:
                if item.isScreenRecording { count += 1 }
                
            case .largeVideos:
                if item.isVideo && item.fileSize > 50_000_000 { count += 1 }
                
            case .blurryPhotos:
                if !item.isVideo && !item.isScreenshot { count += 1 }
            }
        }
        
        return count
    }
    func fetchAllAssetsMap() -> [String: PHAsset] {
        let result = PHAsset.fetchAssets(with: nil)
        var map: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in
            map[asset.localIdentifier] = asset
        }
        return map
    }
}
