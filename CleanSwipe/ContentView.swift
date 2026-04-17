//
//  ContentView.swift
//  CleanSwipe
//
//  המסך הראשי עם Tab Bar Navigation
//

import SwiftUI
import Photos

struct ContentView: View {
    @StateObject private var stackViewModel = PhotoStackViewModel()
    @StateObject private var photoService = PhotoLibraryService.shared
    
    @State private var selectedTab = 0
    @State private var showingAuthorizationAlert = false
    
    var body: some View {
        Group {
            if photoService.authorizationStatus == .authorized ||
               photoService.authorizationStatus == .limited {
                mainTabView
            } else {
                authorizationView
            }
        }
        .onAppear {
            checkPhotoLibraryAuthorization()
        }
    }
    
    // MARK: - Main Tab View
    
    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            // Swipe Stack (Main)
            SwipeStackView(selectedTab: $selectedTab)
                .environmentObject(stackViewModel)
                .tabItem {
                    Label("Swipe", systemImage: "rectangle.stack")
                }
                .tag(0)
            
            // Smart Filters
            SmartFiltersView(selectedTab: $selectedTab)
                .environmentObject(stackViewModel)
                .tabItem {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                .tag(1)
            
            // Review Bin
            ReviewBinView()
                .environmentObject(stackViewModel)
                .tabItem {
                    Label("Review", systemImage: "trash")
                }
                .badge(stackViewModel.reviewBin.count)
                .tag(2)
        }
        .accentColor(.blue)
    }
    
    // MARK: - Authorization View
    
    private var authorizationView: some View {
        VStack(spacing: 30) {
            // Icon
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Title
            VStack(spacing: 12) {
                Text("Welcome to SwipeClean")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Fast, gamified photo cleanup")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            // Description
            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "hand.draw", text: "Swipe to delete or keep")
                featureRow(icon: "chart.bar.fill", text: "Track your space savings")
                featureRow(icon: "tray.full", text: "Review before permanent delete")
            }
            .padding(.horizontal, 40)
            
            // Grant Access Button
            Button {
                requestPhotoLibraryAccess()
            } label: {
                Text("Grant Photo Access")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
        }
        .padding()
        .alert("Photo Access Required", isPresented: $showingAuthorizationAlert) {
            Button("Open Settings", role: .none) {
                openSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable photo library access in Settings to use SwipeClean.")
        }
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            Text(text)
                .font(.body)
        }
    }
    
    // MARK: - Authorization
    
    private func checkPhotoLibraryAuthorization() {
        photoService.checkAuthorization()
    }
    
    private func requestPhotoLibraryAccess() {
        Task {
            let authorized = await photoService.requestAuthorization()
            
            if authorized {
                // Load photos
                photoService.fetchAllPhotos()
            } else {
                // Show alert
                showingAuthorizationAlert = true
            }
        }
    }
    
    private func openSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        
        if UIApplication.shared.canOpenURL(settingsUrl) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

#Preview {
    ContentView()
}
