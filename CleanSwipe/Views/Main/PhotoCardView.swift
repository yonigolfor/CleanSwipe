//
//  PhotoCardView.swift
//  CleanSwipe
//
//  קלף בודד עם תמונה / וידאו מתנגן
//

import SwiftUI
import Photos
import AVKit

extension Notification.Name {
    static let stopCurrentVideo = Notification.Name("stopCurrentVideo")
}

struct PhotoCardView: View {
    let item: PhotoItem
    let isTopCard: Bool
    static var globalMute = false

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var player: AVPlayer?
    @State private var isMuted = false

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBackground)

            if item.isVideo {
                // ── VIDEO ──────────────────────────────────────────────
                if let player = player {
                    let isPortrait = item.asset.pixelHeight >= item.asset.pixelWidth
                    GeometryReader { geo in
                        ZStack {
                            if !isPortrait {
                                // Blurred background — only for landscape
                                VideoPlayerView(player: player, gravity: .resizeAspectFill)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .blur(radius: 25)
                                    .scaleEffect(1.1)
                                    .clipped()
                            }

                            VideoPlayerView(player: player, gravity: isPortrait ? .resizeAspectFill : .resizeAspect)
    .frame(width: geo.size.width, height: geo.size.height)
    .clipped()
    .onTapGesture {
        isMuted.toggle()
PhotoCardView.globalMute = isMuted
player.isMuted = isMuted
    }

if item.isVideo {
    VStack {
        HStack {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.caption)
                .foregroundColor(.white)
                .padding(6)
                .background(Circle().fill(.black.opacity(0.6)))
                .padding(8)
            Spacer()
        }
        Spacer()
    }
}
                        }
                    }
                } else if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                } else {
                    // Fallback thumbnail
                    fallbackVideoThumbnail
                }

                // Bottom bar: progress + duration
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        if let player = player {
                            VideoProgressBar(player: player, duration: item.duration)
                                .padding(.horizontal, 16)
                        }
                        HStack {
                            Image(systemName: "video.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                            Text(item.durationString)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            } else {
                // ── IMAGE ──────────────────────────────────────────────
                if let image = image {
                    let isPortrait = item.asset.pixelHeight >= item.asset.pixelWidth
                    GeometryReader { geo in
                        ZStack {
                            if !isPortrait {
                                // Blurred background — only for landscape
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .blur(radius: 25)
                                    .scaleEffect(1.1)
                                    .clipped()
                            }

                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: isPortrait ? .fill : .fit)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        }
                    }

                } else if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                } else {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                }
            }

            // ── File size + Favorite badge (top-right) ─────────────────
VStack {
    HStack {
        Spacer()
        HStack(spacing: 6) {
            if item.asset.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundColor(.pink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
            }
            Text(item.fileSizeString)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.6)))
        }
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
        isMuted = PhotoCardView.globalMute
        loadVideoPlayer()
    } else {
        loadImage()
    }
}
        .onDisappear {
            stopPlayer()
        }
        .onChange(of: isTopCard) { _, nowTop in
            if nowTop {
                player?.seek(to: .zero)
                player?.play()
            } else {
                stopPlayer()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopCurrentVideo)) { _ in
            stopPlayer()
        }
    }

    // MARK: - Stop Player
    private func stopPlayer() {
        player?.pause()
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
                ) { [weak avPlayer] _ in
                    guard let avPlayer, avPlayer.currentItem != nil else { return }
                    avPlayer.seek(to: .zero)
                    avPlayer.play()
                }
                self.player = avPlayer
                self.isLoading = false
                // Auto-play if already the top card
               avPlayer.isMuted = PhotoCardView.globalMute
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
    var gravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView(player: player, gravity: gravity)
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

    init(player: AVPlayer, gravity: AVLayerVideoGravity = .resizeAspect) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = gravity
    }

    required init?(coder: NSCoder) { fatalError() }
}

//#Preview {
//    Text("Photo Card Preview")
//        .frame(width: 300, height: 500)
//    PhotoCardView(item: PhotoItem(asset: PHAsset()), isTopCard: true)
//}
