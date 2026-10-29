//
//  N_Back_SwiftUIApp.swift
//  N-Back-SwiftUI
//
//  Created by Jonas Willén on 2023-09-19.
//

import SwiftUI

@main
struct N_Back_SwiftUIApp: App {
    // One ViewModel shared by the home and game screens.
    @StateObject private var viewModel = GameViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}
