//
//  SmartFiltersView.swift
//  CleanSwipe
//
//  מסך Smart Filters - "Easy Targets"
//

import SwiftUI

struct SmartFiltersView: View {
    @EnvironmentObject var stackViewModel: PhotoStackViewModel
    @Binding var selectedTab: Int

    
    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(FilterCategory.allCases) { category in
                        filterRow(for: category)
                    }
                } header: {
                                    Text(String(localized: "filters.section_header"))
                                } footer: {
                                    Text(String(localized: "filters.section_footer"))
                                }
            }
            .navigationTitle(String(localized: "filters.title"))
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                if stackViewModel.categoryCounts.isEmpty {
                    stackViewModel.refreshCategoryCounts()
                }
            }
            .refreshable {
                stackViewModel.refreshCategoryCounts()
            }
        }
    }
    
    // MARK: - Filter Row
    
    private func filterRow(for category: FilterCategory) -> some View {
        let count = stackViewModel.categoryCounts[category] ?? 0
        let isEmpty = stackViewModel.categoryCounts[category] != nil && count == 0

        return Button {
            guard !isEmpty else { return }
            stackViewModel.loadPhotos(filter: category)
            selectedTab = 0
        } label: {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(category.color.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: category.icon)
                        .font(.title3)
                        .foregroundColor(category.color)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(category.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Count badge
                // For largeVideos: show shimmer during Phase 2 scan,
                // then animate to the accurate count when ready.
                if category == .largeVideos && stackViewModel.isCountingLargeVideos {
                    // Large videos: shimmer while Phase 2 accurate scan runs
                    ShimmerView()
                } else if category == .blurryPhotos || category == .burstPhotos {
                    // These categories require deep analysis — never show a
                    // potentially misleading count. Show a scan indicator instead.
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption2)
                        Text(String(localized: "filters.requires_scan"))
                            .font(.caption)
                    }
                    .foregroundColor(category.color.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(category.color.opacity(0.15)))
                } else if let count = stackViewModel.categoryCounts[category] {
                    if count > 0 {
                        Text("\(count)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(category.color))
                            .contentTransition(.numericText())
                    } else {
                        Text(String(localized: "filters.empty"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                }

                // Chevron — hidden when empty
                if (stackViewModel.categoryCounts[category] ?? 0) > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
            .opacity((stackViewModel.categoryCounts[category] == 0 && stackViewModel.categoryCounts[category] != nil) ? 0.4 : 1.0)
        }
    }
    

}

/// A horizontal shimmer animation used as a placeholder while
/// expensive counts are being calculated in the background.
struct ShimmerView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.secondary.opacity(0.2),
                            Color.secondary.opacity(0.5),
                            Color.secondary.opacity(0.2)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .offset(x: geo.size.width * phase)
                .animation(
                    .linear(duration: 1.2).repeatForever(autoreverses: false),
                    value: phase
                )
                .onAppear { phase = 1 }
        }
        .frame(width: 48, height: 16)
        .clipShape(Capsule())
    }
}

#Preview {
    SmartFiltersView(selectedTab: .constant(1))
        .environmentObject(PhotoStackViewModel())
}
