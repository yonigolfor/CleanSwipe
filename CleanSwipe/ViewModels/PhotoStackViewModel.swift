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
class PhotoStackViewModel: ObservableObject {
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
    private var processedAssetIDs: Set<String> = []

    // MARK: - Services

    private let photoService = PhotoLibraryService.shared
    private let hapticService = HapticService.shared

    // MARK: - Computed Properties

    var topCard: PhotoItem? { photoStack.first }
    var remainingCount: Int { photoStack.count }

    var spaceSavedText: String {
        let megabytes = Double(totalSpaceSaved) / 1_048_576
        if megabytes < 1024 {
            return String(format: "%.1f MB", megabytes)
        } else {
            return String(format: "%.2f GB", megabytes / 1024)
        }
    }

    // MARK: - Initialization

    init() {
        loadPhotos()
    }

    // MARK: - Data Loading

    /// Loads photos for the given filter, always excluding already-processed assets.
    func loadPhotos(filter: FilterCategory = .all) {
        isLoading = true
        currentFilter = filter

        Task {
            // Fetch from library, then strip out anything already acted upon
            let all = photoService.fetchPhotos(for: filter)
            let items = all.filter { !processedAssetIDs.contains($0.id) }

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

    // MARK: - Swipe Actions

    /// Swipe Right — Keep
    func keepPhoto() {
        guard let topCard = photoStack.first else { return }
        processedAssetIDs.insert(topCard.id)
        photoStack.removeFirst()
        hapticService.keep()
        precacheNextImages()
    }

    /// Swipe Left — Delete (moves to Review Bin)
    func deletePhoto() {
        guard let topCard = photoStack.first else { return }
        processedAssetIDs.insert(topCard.id)
        photoStack.removeFirst()
        reviewBin.append(topCard)
        totalSpaceSaved += topCard.fileSize
        hapticService.delete()
        precacheNextImages()
    }

    /// Swipe Up — Star Keeper
    func starPhoto() {
        guard var topCard = photoStack.first else { return }
        processedAssetIDs.insert(topCard.id)
        photoStack.removeFirst()
        topCard.isStarred = true
        hapticService.starKeeper()
        precacheNextImages()
    }

    /// Undo — restores the last deleted photo back to the top of the stack
    func undoLastAction() {
        guard let lastDeleted = reviewBin.last else { return }
        reviewBin.removeLast()
        // Un-process it so it can be swiped again
        processedAssetIDs.remove(lastDeleted.id)
        photoStack.insert(lastDeleted, at: 0)
        totalSpaceSaved -= lastDeleted.fileSize
        hapticService.undo()
    }

    // MARK: - Review Bin Actions

    /// Restore a single item from the bin back to the swipe stack
    func restoreFromBin(_ item: PhotoItem) {
        guard let index = reviewBin.firstIndex(of: item) else { return }
        reviewBin.remove(at: index)
        // Un-process so the item can be swiped again
        processedAssetIDs.remove(item.id)
        totalSpaceSaved -= item.fileSize
        hapticService.selection()
    }

    /// Permanently delete everything in the Review Bin
    func emptyTrash() async throws {
        let assetsToDelete = reviewBin.map { $0.asset }
        hapticService.emptyTrash()
        try await photoService.deleteAssets(assetsToDelete)
        // Permanently-deleted IDs stay in processedAssetIDs — they can never
        // come back from the library anyway.
        await MainActor.run {
            reviewBin.removeAll()
            totalSpaceSaved = 0
        }
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

    private func precacheNextImages() {
        let nextItems = Array(photoStack.prefix(5))
        guard !nextItems.isEmpty else { return }
        photoService.startCaching(
            for: nextItems,
            targetSize: CGSize(width: 400, height: 600)
        )
    }
}
