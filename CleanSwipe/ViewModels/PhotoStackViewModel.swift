//
//  PhotoStackViewModel.swift
//  CleanSwipe
//
//  ViewModel עבור מסך ה-Swipe הראשי
//

import SwiftUI
import Photos
import Combine

@MainActor
class PhotoStackViewModel: NSObject, ObservableObject, @preconcurrency PHPhotoLibraryChangeObserver {
    // MARK: - Published Properties

    @Published var photoStack: [PhotoItem] = []
    @Published var reviewBin: [PhotoItem] = []
    @Published var currentFilter: FilterCategory = .all
    @Published var totalSpaceSaved: Int64 = 0
    @Published var isLoading = false

    // MARK: - Private State

    /// IDs of every asset the user has already acted on (keep / delete / star).
    /// Persists across tab switches and filter changes within one app session.
    /// Cleared only when emptyTrash() is called for permanently-deleted items
    /// (their IDs can never come back anyway), or when the user explicitly
    /// undoes an action via restoreFromBin.
    private(set) var processedAssetIDs: Set<String> = []
    private var lastAction: (item: PhotoItem, action: SwipeAction)?

    // MARK: - Services

    private let photoService = PhotoLibraryService.shared
    private let hapticService = HapticService.shared
    private let persistence = PersistenceService.shared

    // MARK: - Computed Properties

    var topCard: PhotoItem? { photoStack.first }
    var remainingCount: Int { photoStack.count }

    var spaceSavedText: String {
        formatBytes(totalSpaceSaved)
    }

    var lifetimeSpaceSavedText: String {
        formatBytes(persistence.totalSpaceSavedLifetime)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let megabytes = Double(bytes) / 1_048_576
        if megabytes < 1024 {
            return String(format: "%.1f MB", megabytes)
        } else {
            return String(format: "%.2f GB", megabytes / 1024)
        }
    }

    // MARK: - Initialization

    override init() {
        super.init()
        persistence.resetIfOld()
        self.processedAssetIDs = persistence.keptPhotoIDs
        loadPhotos()
        restoreBinFromDisk()
        PHPhotoLibrary.shared().register(self)
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.photoService.fetchAllPhotos() // מרענן את fetchResult
            let existingIDs = Set(self.photoStack.map { $0.id })
            let all = self.photoService.fetchPhotos(for: self.currentFilter)
            let newItems = all.filter {
                !self.processedAssetIDs.contains($0.id) && !existingIDs.contains($0.id)
            }
            guard !newItems.isEmpty else { return }
            self.photoStack.append(contentsOf: newItems)
        }
    }
    
    private func restoreBinFromDisk() {
        let savedIDs = persistence.reviewBinIDs
        guard !savedIDs.isEmpty else { return }
        let all = photoService.fetchAllAssetsMap()
        let items = savedIDs.compactMap { id -> PhotoItem? in
            guard let asset = all[id] else { return nil }
            return PhotoItem(asset: asset)
        }
        self.reviewBin = items
        self.totalSpaceSaved = persistence.reviewBinSpaceSaved
        items.forEach { processedAssetIDs.insert($0.id) }
    }

    // MARK: - Data Loading

    /// Loads photos for the given filter, always excluding already-processed assets.
    func loadPhotos(filter: FilterCategory = .all) {
        isLoading = true
        currentFilter = filter

        Task {
            // Fetch from library, then strip out anything already acted upon
            let all = photoService.fetchPhotos(for: filter)
            var items = all.filter { !processedAssetIDs.contains($0.id) }
            if filter == .burstPhotos {
                items = await BurstAnalyzer.shared.analyze(items)
            } else if filter == .blurryPhotos {
                items = await filterBlurry(items)
            }
            print("📸 total fetched: \(all.count), after filter: \(items.count), processedIDs: \(processedAssetIDs.count)")

            await MainActor.run {
                self.photoStack = items
                self.isLoading = false

                if !items.isEmpty {
                    photoService.startCaching(
                        for: Array(items.prefix(10)),
                        targetSize: CGSize(width: 400, height: 600)
                    )
                }
            }
        }
    }

    /// Called on SwipeStackView.onAppear — re-fetches from library but keeps
    /// the processed-IDs set intact so swiped photos never reappear.
    func refreshPhotos() {
        photoService.fetchAllPhotos()
        loadPhotos(filter: currentFilter)
    }

    func count(for category: FilterCategory) -> Int {
        photoService.count(for: category, excluding: processedAssetIDs)
    }

    // MARK: - Swipe Actions

    /// Swipe Right — Keep
    func keepPhoto() {
        guard let topCard = photoStack.first else { return }
        processedAssetIDs.insert(topCard.id)
        persistence.saveKeptID(topCard.id)
        self.lastAction = (topCard, .keep)
        photoStack.removeFirst()
        hapticService.keep()
        precacheNextImages()
    }

    /// Swipe Left — Delete (moves to Review Bin)
    func deletePhoto() {
        guard let topCard = photoStack.first else { return }
        processedAssetIDs.insert(topCard.id)
        self.lastAction = (topCard, .delete)
        photoStack.removeFirst()
        reviewBin.append(topCard)
        totalSpaceSaved += topCard.fileSize
        hapticService.delete()
        precacheNextImages()
        saveBinToDisk()
    }

    /// Swipe Up — Star Keeper
    func starPhoto() {
        guard var topCard = photoStack.first else { return }
        processedAssetIDs.insert(topCard.id)
        self.lastAction = (topCard, .starKeeper)
        photoStack.removeFirst()
        topCard.isStarred = true
        hapticService.starKeeper()
        precacheNextImages()
        Task {
            try? await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetChangeRequest(for: topCard.asset)
                    request.isFavorite = true
                }
            }
    }

    /// Undo — restores the last deleted photo back to the top of the stack
    func undoLastAction() {
        guard let last = lastAction else { return }
        lastAction = nil
        let item = last.item

        processedAssetIDs.remove(item.id)
        persistence.removeKeptID(item.id)
        photoStack.insert(item, at: 0)

        if last.action == .delete {
            reviewBin.removeAll { $0.id == item.id }
            totalSpaceSaved -= item.fileSize
            saveBinToDisk()
        }

        hapticService.undo()
    }

    // MARK: - Review Bin Actions

    /// Restore a single item from the bin back to the swipe stack
    func restoreFromBin(_ item: PhotoItem) {
        guard let index = reviewBin.firstIndex(of: item) else { return }
        reviewBin.remove(at: index)
        // Un-process so the item can be swiped again
        processedAssetIDs.remove(item.id)
        // Ensure it's not in persistent kept IDs either (though it shouldn't be if it was in the bin)
        persistence.removeKeptID(item.id)
        totalSpaceSaved -= item.fileSize
        hapticService.selection()
        saveBinToDisk()
    }

    /// Permanently delete everything in the Review Bin
    func emptyTrash() async throws {
        let assetsToDelete = reviewBin.map { $0.asset }
        let currentSaved = totalSpaceSaved
        
        hapticService.emptyTrash()
        try await photoService.deleteAssets(assetsToDelete)
        
        // Permanently-deleted IDs stay in processedAssetIDs — they can never
        // come back from the library anyway.
        await MainActor.run {
            persistence.totalSpaceSavedLifetime += currentSaved
            reviewBin.removeAll()
            totalSpaceSaved = 0
            saveBinToDisk()
        }
    }
    
    /// Resets all "Kept" decisions to start over
    func resetProgress() {
        persistence.keptPhotoIDs = []
        processedAssetIDs = []
        loadPhotos(filter: currentFilter)
    }

    // MARK: - Dispatch Helper

    func performAction(_ action: SwipeAction) {
        switch action {
        case .keep:       keepPhoto()
        case .delete:     deletePhoto()
        case .starKeeper: starPhoto()
        case .undo:       undoLastAction()
        }
    }

    // MARK: - Private Helpers

    private func filterBlurry(_ items: [PhotoItem]) async -> [PhotoItem] {
        await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                var result: [PhotoItem] = []
                let group = DispatchGroup()
                let lock = NSLock()

                for item in items {
                    guard !item.isVideo else { continue }
                    group.enter()
                    PhotoLibraryService.shared.loadImage(
                        for: item.asset,
                        targetSize: CGSize(width: 200, height: 200)
                    ) { image in
                        defer { group.leave() }
                        guard let image else { return }
                        if BlurDetector.shared.isBlurry(image) {
                            lock.lock()
                            result.append(item)
                            lock.unlock()
                        }
                    }
                }

                group.notify(queue: .main) {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private func saveBinToDisk() {
        persistence.reviewBinIDs = reviewBin.map { $0.id }
        persistence.reviewBinSpaceSaved = totalSpaceSaved
    }
    private func precacheNextImages() {
        let nextItems = Array(photoStack.prefix(5))
        guard !nextItems.isEmpty else { return }
        photoService.startCaching(
            for: nextItems,
            targetSize: CGSize(width: 400, height: 600)
        )
    }
}
