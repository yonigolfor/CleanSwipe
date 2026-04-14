//
//  PhotoCardView.swift
//  CleanSwipe
//
//  קלף בודד עם תמונה / וידאו מתנגן
//

import SwiftUI
import Photos
import AVKit

struct PhotoCardView: View {
    let item: PhotoItem
    let isTopCard: Bool

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBackground)

            if item.isVideo {
                // ── VIDEO ──────────────────────────────────────────────
                if let player = player {
                    VideoPlayerView(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                } else {
                    // Fallback thumbnail
                    fallbackVideoThumbnail
                }

                // Duration badge (bottom-left)
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: player != nil ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)

                        Text(item.durationString)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)

                        Spacer()
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            } else {
                // ── IMAGE ──────────────────────────────────────────────
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                } else {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                }
            }

            // ── File size badge (top-right) ────────────────────────────
            VStack {
                HStack {
                    Spacer()
                    Text(item.fileSizeString)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .padding()
                }
                Spacer()
            }

            // ── Screenshot / Recording badge (top-left) ────────────────
            if item.isScreenshot || item.isScreenRecording {
                VStack {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: item.isScreenshot ? "camera.viewfinder" : "record.circle")
                                .font(.caption)
                            Text(item.isScreenshot ? "Screenshot" : "Recording")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.blue.opacity(0.8)))
                        .padding()

                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .cardShadow()
        .onAppear {
            if item.isVideo {
                loadVideoPlayer()
            } else {
                loadImage()
            }
        }
        .onDisappear {
            player?.pause()
        }
        .onChange(of: isTopCard) { _, nowTop in
            // Play only when this card is on top, pause when it sinks behind
            if nowTop {
                player?.seek(to: .zero)
                player?.play()
            } else {
                player?.pause()
            }
        }
    }

    // MARK: - Fallback thumbnail for video
    private var fallbackVideoThumbnail: some View {
        Image(systemName: "video.fill")
            .font(.system(size: 60))
            .foregroundColor(.gray)
    }

    // MARK: - Image Loading

    private func loadImage() {
        let targetSize = CGSize(width: 600, height: 800)
        PhotoLibraryService.shared.loadImage(for: item.asset, targetSize: targetSize) { loadedImage in
            withAnimation {
                self.image = loadedImage
                self.isLoading = false
            }
        }
    }

    // MARK: - Video Player Loading

    private func loadVideoPlayer() {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestPlayerItem(forVideo: item.asset, options: options) { playerItem, _ in
            guard let playerItem = playerItem else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            DispatchQueue.main.async {
                let avPlayer = AVPlayer(playerItem: playerItem)
                // Loop the video
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: playerItem,
                    queue: .main
                ) { _ in
                    avPlayer.seek(to: .zero)
                    avPlayer.play()
                }
                self.player = avPlayer
                self.isLoading = false
                // Auto-play if already the top card
                if self.isTopCard {
                    avPlayer.play()
                }
            }
        }
    }
}

// MARK: - UIViewRepresentable wrapper for AVPlayer

struct VideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView(player: player)
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = player
    }
}

class PlayerUIView: UIView {
    var player: AVPlayer? {
        didSet { playerLayer.player = player }
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) { fatalError() }
}

#Preview {
    Text("Photo Card Preview")
        .frame(width: 300, height: 500)
}
