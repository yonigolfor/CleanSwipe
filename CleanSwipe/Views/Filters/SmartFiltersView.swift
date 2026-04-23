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
    @State private var categoryCounts: [FilterCategory: Int] = [:]
    
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
                loadCounts()
            }
            .refreshable {
                loadCounts()
            }
        }
    }
    
    // MARK: - Filter Row
    
    private func filterRow(for category: FilterCategory) -> some View {
        Button {
            stackViewModel.loadPhotos(filter: category)
            // Navigate to the Swipe tab
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
                if let count = categoryCounts[category], count > 0 {
                    Text("\(count)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(category.color)
                        )
                }
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Data Loading
    
    private func loadCounts() {
        Task.detached(priority: .userInitiated) {
            let service = PhotoLibraryService.shared
            let processed = await MainActor.run { stackViewModel.processedAssetIDs }
            let counts: [FilterCategory: Int] = Dictionary(
                uniqueKeysWithValues: FilterCategory.allCases.map { ($0, service.count(for: $0, excluding: processed)) }
            )
            await MainActor.run {
                categoryCounts = counts
            }
        }
    }
}

#Preview {
    SmartFiltersView(selectedTab: .constant(1))
        .environmentObject(PhotoStackViewModel())
}
