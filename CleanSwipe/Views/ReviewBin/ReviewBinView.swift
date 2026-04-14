//
//  ReviewBinView.swift
//  CleanSwipe
//
//  מסך Review Bin עם גריד של תמונות
//

import SwiftUI
import Photos
import AVKit

struct ReviewBinView: View {
    @EnvironmentObject var stackViewModel: PhotoStackViewModel
    @StateObject private var viewModel = ReviewBinViewModel()

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationView {
            ZStack {
                if stackViewModel.reviewBin.isEmpty {
                    EmptyStateView.emptyBin
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(stackViewModel.reviewBin) { item in
                                ReviewGridItemView(item: item)
                                    .onTapGesture {
                                        viewModel.selectItem(item)
                                    }
                                    .contextMenu {
                                        Button {
                                            stackViewModel.restoreFromBin(item)
                                        } label: {
                                            Label("Restore", systemImage: "arrow.uturn.backward")
                                        }
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Review Bin")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !stackViewModel.reviewBin.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            viewModel.showDeleteConfirmation()
                        } label: {
                            Label("Empty Trash", systemImage: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .alert("Empty Trash", isPresented: $viewModel.isShowingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete \(stackViewModel.reviewBin.count) Items", role: .destructive) {
                    Task {
                        try? await stackViewModel.emptyTrash()
                    }
                }
            } message: {
                Text("This will permanently delete \(stackViewModel.reviewBin.count) items from your library. This action cannot be undone.")
            }
            // Use fullScreenCover so swipe-down dismisses fully instead of
            // leaving a floating mini-card at the bottom of the screen.
            .fullScreenCover(item: $viewModel.selectedItem) { item in
                FullScreenMediaView(
                    item: item,
                    onClose: { viewModel.deselectItem() },
                    onRestore: {
                        stackViewModel.restoreFromBin(item)
                        viewModel.deselectItem()
                    }
                )
            }
        }
    }
}

// MARK: - Full-screen media viewer (image or video)

struct FullScreenMediaView: View {
    let item: PhotoItem
    let onClose: () -> Void
    let onRestore: () -> Void

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if item.isVideo {
                if let player = player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else if isLoading {
                    ProgressView().tint(.white)
                }
            } else {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .ignoresSafeArea()
                } else if isLoading {
                    ProgressView().tint(.white)
                }
            }

            // Toolbar overlay
            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, .white.opacity(0.3))
                    }
                    .padding()

                    Spacer()

                    Button(action: onRestore) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.uturn.backward")
                            Text("Restore")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.white.opacity(0.25)))
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .onAppear { load() }
        .onDisappear { player?.pause() }
    }

    private func load() {
        if item.isVideo {
            let options = PHVideoRequestOptions()
            options.deliveryMode = .automatic
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestPlayerItem(forVideo: item.asset, options: options) { playerItem, _ in
                guard let playerItem = playerItem else {
                    DispatchQueue.main.async { isLoading = false }
                    return
                }
                DispatchQueue.main.async {
                    self.player = AVPlayer(playerItem: playerItem)
                    self.player?.play()
                    self.isLoading = false
                }
            }
        } else {
            PhotoLibraryService.shared.loadImage(
                for: item.asset,
                targetSize: PHImageManagerMaximumSize
            ) { loaded in
                withAnimation { self.image = loaded; self.isLoading = false }
            }
        }
    }
}

// MARK: - AsyncImage Helper (kept for backward compat)

struct AsyncImage: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
            }
        }
        .onAppear { loadFullImage() }
    }

    private func loadFullImage() {
        PhotoLibraryService.shared.loadImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize
        ) { loadedImage in
            withAnimation { self.image = loadedImage }
        }
    }
}

#Preview {
    ReviewBinView()
        .environmentObject(PhotoStackViewModel())
}
