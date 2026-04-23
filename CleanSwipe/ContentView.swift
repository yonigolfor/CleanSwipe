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
    
    var body: some View {
        mainTabView
            .onAppear {
                checkPhotoLibraryAuthorization()
            }
    }
    
    // MARK: - Main Tab View
    
    private var mainTabView: some View {
        VStack(alignment: .center) {
            TabView(selection: $selectedTab) {
                SwipeStackView(selectedTab: $selectedTab)
                    .environmentObject(stackViewModel)
                    .tag(0)
                
                SmartFiltersView(selectedTab: $selectedTab)
                    .environmentObject(stackViewModel)
                    .tag(1)
                
                ReviewBinView()
                    .environmentObject(stackViewModel)
                    .tag(2)
            }
            .ignoresSafeArea()
            .onAppear {
                UITabBar.appearance().isHidden = true
            }
            
            GlassmorphicTabBar(
                selectedTab: $selectedTab,
                reviewBinCount: stackViewModel.reviewBin.count
            )
            .padding(.bottom, 8)
            
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .resumeVideoObserver, object: nil)
                }
            } else {
                NotificationCenter.default.post(name: .stopCurrentVideo, object: nil)
            }
        }
    }

    private func checkPhotoLibraryAuthorization() {
        photoService.checkAuthorization()
    }
}

#Preview {
    ContentView()
}
