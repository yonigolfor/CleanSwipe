//
//  GlassmorphicTabBar.swift
//  CleanSwipe
//

import SwiftUI

struct GlassmorphicTabBar: View {
    @Binding var selectedTab: Int
    let reviewBinCount: Int

    @GestureState private var dragOffset: CGFloat = 0
    @State private var bubbleX: CGFloat = 0

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private let tabs: [(icon: String, label: String)] = [
        ("rectangle.stack", "Swipe"),
        ("line.3.horizontal.decrease.circle", "Filters"),
        ("trash", "Review")
    ]

    var body: some View {
        GeometryReader { geo in
            let tabWidth = (geo.size.width) / CGFloat(tabs.count)
            let activeBubbleX = tabWidth * CGFloat(selectedTab) + tabWidth / 2

            ZStack(alignment: .leading) {
                // Capsule background
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 10)
                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)

                // Drag bubble
                if dragOffset != 0 {
                    Circle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .position(
                            x: min(max(activeBubbleX + dragOffset, tabWidth / 2), geo.size.width - tabWidth / 2),
                            y: geo.size.height / 2
                        )
                        .animation(.interactiveSpring(), value: dragOffset)
                }

                // Tab buttons
                HStack(spacing: 0) {
                    ForEach(0..<tabs.count, id: \.self) { index in
                        tabButton(index: index)
                    }
                }
            }
            .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .updating($dragOffset) { value, state, _ in
                    state = value.translation.width
                }
                .onEnded { value in
                    let threshold: CGFloat = 40
                    if value.translation.width < -threshold {
                        let next = min(selectedTab + 1, tabs.count - 1)
                        guard next != selectedTab else { return }
                        haptic.impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            selectedTab = next
                        }
                    } else if value.translation.width > threshold {
                        let prev = max(selectedTab - 1, 0)
                        guard prev != selectedTab else { return }
                        haptic.impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            selectedTab = prev
                        }
                    }
                }
        )
        }
        .frame(height: 60)
        .padding(.horizontal, 40)
        .onAppear { haptic.prepare() }
    }

    @ViewBuilder
    private func tabButton(index: Int) -> some View {
        let isSelected = selectedTab == index
        let tab = tabs[index]

        Button {
            guard selectedTab != index else { return }
            haptic.impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                selectedTab = index
            }
        } label: {
            ZStack {
                if isSelected {
                    AngularGradient(
                        colors: [.cyan, .purple, .pink, Color(red: 1, green: 0.8, blue: 0.2), .cyan],
                        center: .center
                    )
                    .blur(radius: 10)
                    .opacity(0.3)
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                }

                VStack(spacing: 4) {
                    ZStack {
                        Image(systemName: isSelected ? tab.icon + ".fill" : tab.icon)
                            .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? .primary : .secondary)
                            .scaleEffect(isSelected ? 1.15 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)

                        if index == 2 && reviewBinCount > 0 {
                            Text("\(min(reviewBinCount, 99))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(3)
                                .background(Circle().fill(Color.red))
                                .offset(x: 10, y: -10)
                        }
                    }

                    Text(tab.label)
                        .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
        }
        .buttonStyle(.plain)
    }
}