//
//  SwipeWidget.swift
//  SwipeWidget
//

import WidgetKit
import SwiftUI
import Photos
import AppIntents

// MARK: - Entry

struct SwipeWidgetEntry: TimelineEntry {
    let date: Date
    let assetInfo: WidgetAssetInfo?
    let thumbnail: UIImage?
    let confirmation: ConfirmationState

    enum ConfirmationState {
        case none, saved, deleted
    }
}

// MARK: - AppIntents

struct KeepAssetIntent: AppIntent {
    static var title: LocalizedStringResource = "Keep"

    @Parameter(title: "Asset ID") var assetID: String

    init() { self.assetID = "" }
    init(assetID: String) { self.assetID = assetID }

    func perform() async throws -> some IntentResult {
        print("✅ KeepAssetIntent fired: \(assetID)")
        let defaults = UserDefaults(suiteName: appGroupSuiteName)!
        defaults.set(assetID, forKey: "widgetPendingActionID")
        defaults.set(WidgetAction.keep.rawValue, forKey: "widgetPendingAction")
        try await Task.sleep(for: .seconds(1.5))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct DeleteAssetIntent: AppIntent {
    static var title: LocalizedStringResource = "Delete"

    @Parameter(title: "Asset ID") var assetID: String

    init() { self.assetID = "" }
    init(assetID: String) { self.assetID = assetID }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: appGroupSuiteName)!
        defaults.set(assetID, forKey: "widgetPendingActionID")
        defaults.set(WidgetAction.delete.rawValue, forKey: "widgetPendingAction")
        try await Task.sleep(for: .seconds(1.5))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Provider

struct SwipeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SwipeWidgetEntry {
        SwipeWidgetEntry(date: .now, assetInfo: nil, thumbnail: nil, confirmation: .none)
    }

    func getSnapshot(in context: Context, completion: @escaping (SwipeWidgetEntry) -> Void) {
        let entry = fetchEntry(confirmation: .none)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SwipeWidgetEntry>) -> Void) {
        let entry = fetchEntry(confirmation: .none)
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }

    private func fetchEntry(confirmation: SwipeWidgetEntry.ConfirmationState) -> SwipeWidgetEntry {
        let defaults = UserDefaults(suiteName: appGroupSuiteName)!
        guard
            let data = defaults.data(forKey: "widgetCurrentAsset"),
            let info = try? JSONDecoder().decode(WidgetAssetInfo.self, from: data)
        else {
            return SwipeWidgetEntry(date: .now, assetInfo: nil, thumbnail: nil, confirmation: confirmation)
        }

        let thumbnail: UIImage?
        if let data = defaults.data(forKey: "widgetThumbnail") {
            thumbnail = UIImage(data: data)
        } else {
            thumbnail = nil
        }
        return SwipeWidgetEntry(date: .now, assetInfo: info, thumbnail: thumbnail, confirmation: confirmation)
    }

}

// MARK: - Entry View

struct SwipeWidgetEntryView: View {
    let entry: SwipeWidgetEntry

    var body: some View {
        ZStack {
            // תמונה
            if let thumbnail = entry.thumbnail {
                GeometryReader { geo in
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                .zIndex(0)
                .allowsHitTesting(false)
            } else {
                Rectangle()
                    .fill(Color(UIColor.secondarySystemBackground))
                    .overlay {
                        Image(systemName: "photo.stack")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                    }
            }

            // Confirmation Overlay
            if entry.confirmation != .none {
                confirmationOverlay
            }

            // כפתורים + video indicator
            if entry.confirmation == .none, let info = entry.assetInfo {
                let _ = print("🔍 assetInfo ID: \(info.localIdentifier)")

                // Video indicator
                if info.isVideo {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "video.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Circle().fill(.black.opacity(0.5)))
                                .padding(8)
                        }
                        Spacer()
                    }
                }

                VStack {
                    Spacer()
                    HStack(spacing: 20) {
                        Button(intent: DeleteAssetIntent(assetID: info.localIdentifier)) {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 52, height: 52)
                                .overlay {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.red)
                                }
                        }
                        .buttonStyle(.plain)

                        Button(intent: KeepAssetIntent(assetID: info.localIdentifier)) {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 52, height: 52)
                                .overlay {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.green)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 12)
                }
                .zIndex(2)
            }
        }
        .containerBackground(.black, for: .widget)
    }

    @ViewBuilder
    private var confirmationOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            VStack(spacing: 8) {
                Image(systemName: entry.confirmation == .saved ? "checkmark.circle.fill" : "trash.fill")
                    .font(.system(size: 36))
                    .foregroundColor(entry.confirmation == .saved ? .green : .red)

                Text(entry.confirmation == .saved ? "Saved!" : "Deleted!")
                    .font(.system(size: 18, weight: .semibold))
                    .kerning(0.5)
                    .foregroundColor(.primary)
            }
        }
    }
}

// MARK: - Widget
@main
struct SwipeWidgetBundle: Widget {
    let kind: String = "SwipeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SwipeWidgetProvider()) { entry in
            SwipeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("SwipeClean")
        .description("Clean your gallery from the home screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
