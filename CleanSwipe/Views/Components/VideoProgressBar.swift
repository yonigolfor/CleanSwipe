//
//  VideoProgressBar.swift
//  CleanSwipe
//

import SwiftUI
import AVKit

struct VideoProgressBar: View {
    let player: AVPlayer
    let duration: TimeInterval

    @State private var progress: Double = 0
    @State private var isDragging = false
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 4) {
            // Scrubber
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: isDragging ? 6 : 4)

                    // Fill
                    Capsule()
                        .fill(Color.white)
                        .frame(width: geo.size.width * progress, height: isDragging ? 6 : 4)

                    // Thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: isDragging ? 16 : 10, height: isDragging ? 16 : 10)
                        .offset(x: geo.size.width * progress - (isDragging ? 8 : 5))
                        .shadow(radius: 2)
                }
                .animation(.easeInOut(duration: 0.15), value: isDragging)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            timer?.invalidate()
                            let newProgress = min(max(value.location.x / geo.size.width, 0), 1)
                            progress = newProgress
                            let seekTime = CMTime(
                                seconds: newProgress * duration,
                                preferredTimescale: 600
                            )
                            player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
                        }
                        .onEnded { _ in
                            isDragging = false
                            startTimer()
                        }
                )
            }
            .frame(height: 20)

            // Time labels
            HStack {
                Text(formatTime(progress * duration))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(formatTime(duration))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            guard !isDragging else { return }
            let current = player.currentTime().seconds
            guard duration > 0, !current.isNaN else { return }
            progress = min(max(current / duration, 0), 1)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
