//
//  ArogyaM_iOS_v1App.swift
//  ArogyaM-iOS-v1
//
//  Created by Kethan Dosapati on 4/7/26.
//

import SwiftUI

@main
struct ArogyaM_iOS_v1App: App {
    @StateObject private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .preferredColorScheme(.light)
                .tint(Theme.teal)
        }
    }
}
