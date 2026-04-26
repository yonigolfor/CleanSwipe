//
//  PhotoStackViewModel.swift
//  CleanSwipe
//
//  ViewModel עבור מסך ה-Swipe הראשי
//

import SwiftUI
import Photos
import Combine

// Extension to save processed assets for notifications
extension PhotoStackViewModel {
    private func saveProcessedAsset(assetId: String, action: MediaAction) {
        var processed = getProcessedAssets()
        let record = ProcessedAsset(
            assetId: assetId,
            action: action,
            timestamp: Date()
        )
        processed.append(record)
        
        if let encoded = try? JSONEncoder().encode(processed) {
            UserDefaults.standard.set(encoded, forKey: "processedAssets")
        }
    }
    
    private func getProcessedAssets() -> [ProcessedAsset] {
        guard let data = UserDefaults.standard.data(forKey: "processedAssets"),
              let decoded = try? JSONDecoder().decode([ProcessedAsset].self, from: data) else {
            return []
        }
        return decoded
    }
}

@MainActor
class PhotoStackViewModel: NSObject, ObservableObject, @preconcurrency PHPhotoLibraryChangeObserver {
    // MARK: - Published Properties

    @Published var photoStack: [PhotoItem] = []
    @Published var reviewBin: [PhotoItem] = []
    @Published var currentFilter: FilterCategory = .all
    @Published var totalSpaceSaved: Int64 = 0
    @Published var isLoading = false
    @Published var categoryCounts: [FilterCategory: Int] = [:]
    /// True while the expensive Phase 2 large video scan is running.
    @Published var isCountingLargeVideos = false



    // MARK: - Private State

    /// IDs of every asset the user has already acted on (keep / delete / star).
    /// Persists across tab switches and filter changes within one app session.
    /// Cleared only when emptyTrash() is called for permanently-deleted items
    /// (their IDs can never come back anyway), or when the user explicitly
    /// undoes an action via restoreFromBin.
    private(set) var processedAssetIDs: Set<String> = []
    private var lastAction: (item: PhotoItem, action: SwipeAction)?

    // MARK: - Pagination State

    /// The index in the PHFetchResult where the next page load will resume.
    /// Reset to 0 whenever the filter changes or the library is refreshed.
    private var fetchCursor: Int = 0

    /// True while a background page-fetch is in flight — prevents concurrent fetches.
    private var isFetchingNextPage = false

    /// Number of PhotoItems to materialize in the initial load.
    private let initialPageSize = 50

    /// Number of PhotoItems to add per subsequent page.
    private let nextPageSize = 30

    /// When the stack drops to this many items, prefetch the next page.
    private let lowWatermark = 12

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
        // Load cached large video count immediately so Filters screen
        // shows last known value without any scanning on launch.
        loadCachedLargeVideoCount()
        // NOTE: refreshCategoryCounts() is NOT called here.
        // It is triggered lazily by SmartFiltersView.onAppear via .task.
    }

    /// Loads the cached large video count from PersistenceService.
    /// Shows instantly on launch — no scanning needed.
    private func loadCachedLargeVideoCount() {
        let cached = persistence.cachedLargeVideoCount
        guard cached >= 0 else { return }
        categoryCounts[.largeVideos] = cached
    }

    /// Saves the accurate large video count to PersistenceService.
    private func saveLargeVideoCountToCache(_ count: Int) {
        persistence.cachedLargeVideoCount = count
        persistence.largeVideoSyncDate = Date()
    }

    func refreshCategoryCounts() {
        Task.detached(priority: .userInitiated) {
            let service = PhotoLibraryService.shared
            let persistence = await self.persistence

            // Ensure fetchResult is populated
            if service.fetchResult == nil {
                service.fetchAllPhotos()
            }

            let processed = await self.processedAssetIDs

            // ── Phase 1: Instant fast counts for all categories ───────────
            var fastCounts: [FilterCategory: Int] = Dictionary(
                uniqueKeysWithValues: FilterCategory.allCases.map {
                    ($0, service.countFast(for: $0, excluding: processed))
                }
            )

            // Use cached large video count immediately if available.
            // This means 0ms wait on every launch after the first scan.
            let cachedCount = persistence.cachedLargeVideoCount
            let hasCachedCount = cachedCount >= 0

            if hasCachedCount {
                fastCounts[.largeVideos] = cachedCount
            }

            await MainActor.run {
                withAnimation { self.categoryCounts = fastCounts }
                // Show shimmer only if no cache exists (first ever launch)
                self.isCountingLargeVideos = !hasCachedCount
            }

            // ── Phase 2: Incremental scan ─────────────────────────────────
            // If library hasn't changed since last sync — skip entirely.
            // PHPhotoLibraryChangeObserver already invalidated the cache
            // if anything changed, so checking cachedCount >= 0 is enough.
            guard !hasCachedCount else {
                // Cache is valid — run a quick incremental check in background
                // to account for any new or deleted large videos since last sync.
                await self.runIncrementalScan(
                    service: service,
                    processed: processed,
                    lastSyncDate: persistence.largeVideoSyncDate,
                    cachedCount: cachedCount
                )
                return
            }

            // No cache — run full scan
            let fullCount = await Task.detached(priority: .background) {
                service.count(for: .largeVideos, excluding: processed)
            }.value

            await self.saveLargeVideoCountToCache(fullCount)

            await MainActor.run {
                withAnimation(.spring(response: 0.4)) {
                    self.categoryCounts[.largeVideos] = fullCount
                    self.isCountingLargeVideos = false
                }
            }
        }
    }

    /// Incremental scan: only checks assets created or modified since lastSyncDate.
    /// Also accounts for deletions by comparing total video count to cached value.
    /// Runs at background priority so it never affects UI responsiveness.
    private func runIncrementalScan(
        service: PhotoLibraryService,
        processed: Set<String>,
        lastSyncDate: Date?,
        cachedCount: Int
    ) async {
        let updatedCount = await Task.detached(priority: .background) {

            // ── Count deletions ───────────────────────────────────────────
            // If total video count dropped since last sync, some large videos
            // may have been deleted. We must recount from scratch in that case.
            let allVideosOptions = PHFetchOptions()
            allVideosOptions.predicate = NSPredicate(
                format: "mediaType == %d", PHAssetMediaType.video.rawValue
            )
            let currentTotalVideos = PHAsset.fetchAssets(with: allVideosOptions).count

            // Fetch total from last sync stored in persistence
            let lastTotalVideos = UserDefaults.standard.integer(forKey: "lastTotalVideoCount")

            if currentTotalVideos < lastTotalVideos {
                // Videos were deleted — full recount needed
                UserDefaults.standard.set(currentTotalVideos, forKey: "lastTotalVideoCount")
                return service.count(for: .largeVideos, excluding: processed)
            }

            // ── Count new additions since last sync ───────────────────────
            guard let syncDate = lastSyncDate else {
                return service.count(for: .largeVideos, excluding: processed)
            }

            let newVideoOptions = PHFetchOptions()
            newVideoOptions.predicate = NSPredicate(
                format: "mediaType == %d AND creationDate > %@",
                PHAssetMediaType.video.rawValue,
                syncDate as NSDate
            )
            let newVideos = PHAsset.fetchAssets(with: newVideoOptions)

            // Count how many of the new videos are large (>50MB)
            var newLargeCount = 0
            newVideos.enumerateObjects { asset, _, stop in
                guard !processed.contains(asset.localIdentifier) else { return }
                let resources = PHAssetResource.assetResources(for: asset)
                let size = resources.first.flatMap {
                    $0.value(forKey: "fileSize") as? Int64
                } ?? 0
                if size > 50_000_000 { newLargeCount += 1 }
                if cachedCount + newLargeCount >= 100 { stop.pointee = true }
            }

            UserDefaults.standard.set(currentTotalVideos, forKey: "lastTotalVideoCount")
            return min(cachedCount + newLargeCount, 100)
        }.value

        // Only update UI if count actually changed — avoids unnecessary redraws
        guard updatedCount != cachedCount else { return }

        await saveLargeVideoCountToCache(updatedCount)

        await MainActor.run {
            // Counter animation — number rolls from old value to new value
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                self.categoryCounts[.largeVideos] = updatedCount
            }
        }
    }

    // MARK: - PHPhotoLibraryChangeObserver

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            // Library changed — invalidate large video cache so
            // incremental scan runs on next filter screen visit.
            self.persistence.cachedLargeVideoCount = -1
            self.persistence.largeVideoSyncDate = nil

            guard let oldResult = self.photoService.fetchResult else {
                // No prior fetch — do a full initial load.
                self.photoService.fetchAllPhotos()
                self.resetAndLoad(filter: self.currentFilter)
                return
            }

            // Refresh the fetch result (no enumeration — O(1) index update).
            let newResult = self.photoService.fetchAllPhotos()

            guard let details = changeInstance.changeDetails(for: oldResult) else { return }

            // Only act on insertions.
            guard details.hasIncrementalChanges,
                  let insertedIndexes = details.insertedIndexes,
                  !insertedIndexes.isEmpty else { return }

            // Newly inserted assets arrive at the top (newest-first sort).
            // Collect only those not already seen.
            let existingIDs = Set(self.photoStack.map { $0.id })
            var newItems: [PhotoItem] = []

            insertedIndexes.forEach { idx in
                let asset = newResult.object(at: idx)
                guard !self.processedAssetIDs.contains(asset.localIdentifier),
                      !existingIDs.contains(asset.localIdentifier) else { return }
                newItems.append(PhotoItem(asset: asset))
            }

            guard !newItems.isEmpty else { return }
            self.photoStack.insert(contentsOf: newItems, at: 0)
        }
    }

    // MARK: - Bin Restoration

    private func restoreBinFromDisk() {
        let savedIDs = persistence.reviewBinIDs
        guard !savedIDs.isEmpty else { return }
        // Targeted fetch — only the IDs we actually need, not the full library.
        let assetMap = photoService.fetchAssets(forIDs: savedIDs)
        let items = savedIDs.compactMap { id -> PhotoItem? in
            guard let asset = assetMap[id] else { return nil }
            return PhotoItem(asset: asset)
        }
        self.reviewBin = items
        self.totalSpaceSaved = persistence.reviewBinSpaceSaved
        items.forEach { processedAssetIDs.insert($0.id) }
    }

    // MARK: - Data Loading

    /// Loads photos for the given filter, always excluding already-processed assets.
    /// Only the first `initialPageSize` items are materialised up front; more are
    /// fetched lazily as the user swipes (see `loadNextPageIfNeeded`).
    func loadPhotos(filter: FilterCategory = .all) {
        resetAndLoad(filter: filter)
    }

    /// Resets the cursor and kicks off an initial page fetch for `filter`.
    private func resetAndLoad(filter: FilterCategory) {
        isLoading = true
        currentFilter = filter
        fetchCursor = 0
        isFetchingNextPage = false

        Task {
            // Ensure we have an up-to-date fetch result (no-op if already fresh).
            if photoService.fetchResult == nil {
                photoService.fetchAllPhotos()
            }

            let pageSize: Int
            switch filter {
            case .burstPhotos:  pageSize = 500  // BurstAnalyzer needs a pool
            case .blurryPhotos: pageSize = 200  // Enough to find blurry images
            default:            pageSize = initialPageSize
            }

            let (rawItems, nextIdx) = photoService.fetchPageOfAssets(
                for: filter,
                startIndex: 0,
                pageSize: pageSize,
                excluding: processedAssetIDs
            )

            self.fetchCursor = nextIdx ?? photoService.totalAssetCount

            // For blurry and burst — skip the standard initial load entirely.
            // scanUntilFull handles everything: it scans continuously until
            // it finds results, never showing an empty stack mid-scan.
            if filter == .blurryPhotos || filter == .burstPhotos {
                await MainActor.run {
                    self.photoStack = []
                    self.isLoading = true  // Keep loading indicator visible
                }
                await scanUntilFull(filter: filter, targetCount: 15, batchSize: 300)
                await MainActor.run { self.isLoading = false }
                if self.categoryCounts.isEmpty {
                    self.refreshCategoryCounts()
                }
                return
            }

            let items = rawItems

            print("📸 initial page: \(items.count) items, cursor: \(self.fetchCursor)/\(self.photoService.totalAssetCount)")

            await MainActor.run {
                self.photoStack = items
                self.isLoading = false

                if !items.isEmpty {
                    photoService.startCaching(
                        for: Array(items.prefix(10)),
                        targetSize: CGSize(width: 400, height: 600)
                    )
                    let firstAssets = Array(items.prefix(5)).map { $0.asset }
                    Task { await VideoPlayerPool.shared.warmUp(for: firstAssets) }
                }

                if self.categoryCounts.isEmpty {
                    self.refreshCategoryCounts()
                }
            }
        }
    }

    /// Appends the next page of assets to `photoStack` when the stack is running low.
    /// No-op for filters that need up-front analysis (burst / blurry) since their
    /// pool is already bounded by the initial large page.
    private func loadNextPageIfNeeded() {
        guard !isFetchingNextPage,
              photoStack.count <= lowWatermark,
              fetchCursor < photoService.totalAssetCount else { return }

        // For analysis-heavy filters, use the refill mechanism
        // which scans continuously until the buffer is full.
        if currentFilter == .blurryPhotos || currentFilter == .burstPhotos {
            Task { await scanUntilFull(filter: currentFilter) }
            return
        }

        isFetchingNextPage = true

        Task {
            let (rawItems, nextIdx) = photoService.fetchPageOfAssets(
                for: currentFilter,
                startIndex: fetchCursor,
                pageSize: nextPageSize,
                excluding: processedAssetIDs
            )

            let newFetchCursor = nextIdx ?? photoService.totalAssetCount

            print("📸 next page: \(rawItems.count) items, cursor: \(newFetchCursor)/\(self.photoService.totalAssetCount)")

            await MainActor.run {
                if !rawItems.isEmpty {
                    self.photoStack.append(contentsOf: rawItems)
                    photoService.startCaching(
                        for: rawItems,
                        targetSize: CGSize(width: 400, height: 600)
                    )
                }
                self.fetchCursor = newFetchCursor
                self.isFetchingNextPage = false
            }
        }
    }

    /// Called on SwipeStackView.onAppear — re-fetches from library but keeps
    /// the processed-IDs set intact so swiped photos never reappear.
    func refreshPhotos() {
        photoService.fetchAllPhotos()
        loadPhotos(filter: currentFilter)
    }

    /// Pauses all pooled video players. Call when the user leaves the Swipe tab.
    func pauseVideoPool() {
        Task { await VideoPlayerPool.shared.pauseAll() }
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
            
            // Save to processed assets for notifications
            saveProcessedAsset(assetId: topCard.id, action: .saved)
            
            loadNextPageIfNeeded()
            
            // Schedule notifications after keep action
            NotificationScheduler.shared.evaluateAndScheduleNotifications()
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
            
            // Save to processed assets for notifications
            saveProcessedAsset(assetId: topCard.id, action: .deleted)
            
            loadNextPageIfNeeded()
            
            // Schedule notifications after delete action
            NotificationScheduler.shared.evaluateAndScheduleNotifications()
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
        loadNextPageIfNeeded()
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
            processedAssetIDs.remove(item.id)
            persistence.removeKeptID(item.id)
            totalSpaceSaved -= item.fileSize
            hapticService.selection()
            saveBinToDisk()
            
            // Re-evaluate notifications after restoration
            NotificationScheduler.shared.evaluateAndScheduleNotifications()
        }

    /// Permanently delete everything in the Review Bin
        func emptyTrash() async throws {
            let assetsToDelete = reviewBin.map { $0.asset }
            let currentSaved = totalSpaceSaved

            // Drain the video pool BEFORE deleting assets — AVPlayerItems hold
            // strong references to PHAssets and will crash if accessed after deletion.
            VideoPlayerPool.shared.drainAll()
            hapticService.emptyTrash()
            try await photoService.deleteAssets(assetsToDelete)

            // Permanently-deleted IDs stay in processedAssetIDs — they can never
            // come back from the library anyway.
            await MainActor.run {
                persistence.totalSpaceSavedLifetime += currentSaved
                reviewBin.removeAll()
                totalSpaceSaved = 0
                saveBinToDisk()
                
                // Check for milestones after emptying trash
                NotificationScheduler.shared.evaluateAndScheduleNotifications()
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

    /// Scans items for blur and returns only blurry ones.
    /// Processes images concurrently for maximum speed.
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

    /// Continuously scans the library until it finds at least `targetCount`
    /// items matching the filter, or exhausts the entire library.
    /// This powers the "refill mechanism" — the user never sees an empty
    /// stack while there are still unscanned assets in the library.
    /// Continuously scans the library and streams results to the UI
    /// one asset at a time as they are found — no waiting for full batches.
    /// The user sees the first card appear immediately after it is found.
    private func scanUntilFull(
        filter: FilterCategory,
        targetCount: Int = 15,
        batchSize: Int = 100
    ) async {
        guard filter == .blurryPhotos || filter == .burstPhotos else { return }

        while photoStack.count < targetCount,
              fetchCursor < photoService.totalAssetCount {

            let cursor = fetchCursor
            let processed = processedAssetIDs

            let (rawItems, nextIdx) = photoService.fetchPageOfAssets(
                for: filter,
                startIndex: cursor,
                pageSize: batchSize,
                excluding: processed
            )

            let newCursor = nextIdx ?? photoService.totalAssetCount
            await MainActor.run { self.fetchCursor = newCursor }

            if filter == .blurryPhotos {
                // Stream: push each blurry image to UI as soon as it is found.
                // User sees cards appear one by one instead of waiting for batch.
                for item in rawItems {
                    guard !item.isVideo else { continue }
                    let result = await withCheckedContinuation { (cont: CheckedContinuation<PhotoItem?, Never>) in
                        PhotoLibraryService.shared.loadImage(
                            for: item.asset,
                            targetSize: CGSize(width: 200, height: 200)
                        ) { image in
                            guard let image else { cont.resume(returning: nil); return }
                            let isBlurry = BlurDetector.shared.isBlurry(image)
                            cont.resume(returning: isBlurry ? item : nil)
                        }
                    }
                    if let found = result {
                        await MainActor.run {
                            self.photoStack.append(found)
                            self.photoService.startCaching(
                                for: [found],
                                targetSize: CGSize(width: 400, height: 600)
                            )
                            // Hide loading indicator as soon as first result arrives
                            if self.isLoading { self.isLoading = false }
                        }
                    }
                }
            } else if filter == .burstPhotos {
                // Burst needs grouping — analyze full batch then stream results
                let analyzed = await BurstAnalyzer.shared.analyze(rawItems)
                if !analyzed.isEmpty {
                    await MainActor.run {
                        self.photoStack.append(contentsOf: analyzed)
                        self.photoService.startCaching(
                            for: analyzed,
                            targetSize: CGSize(width: 400, height: 600)
                        )
                        if self.isLoading { self.isLoading = false }
                    }
                }
            }

            if nextIdx == nil { break }
        }

        // Ensure loading indicator is hidden even if nothing was found
        await MainActor.run { self.isLoading = false }
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
        // Warm up the video player pool with the next upcoming video assets.
        // VideoPlayerPool filters to videos only, so passing all items is safe.
        let nextAssets = nextItems.map { $0.asset }
        Task { await VideoPlayerPool.shared.warmUp(for: nextAssets) }
    }
}
