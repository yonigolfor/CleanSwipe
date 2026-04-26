//
//  CleanSwipeApp.swift
//  CleanSwipe
//
//  Created by Yoni Golfor on 15/04/2026.
//

import SwiftUI

@main
struct CleanSwipeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var deepLinkRouter = DeepLinkRouter()
    
    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .environmentObject(deepLinkRouter)
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeepLinkReceived"))) { notification in
                    if let userInfo = notification.userInfo,
                       let destination = userInfo["destination"] as? String,
                       let params = userInfo["params"] as? [AnyHashable: Any] {
                        deepLinkRouter.handleDeepLink(destination: destination, params: params)
                    }
                }
        }
    }
}
