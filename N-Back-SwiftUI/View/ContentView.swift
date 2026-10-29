//
//  ContentView.swift
//  N-Back-SwiftUI
//
//  Root view. Owns the navigation (STYLE.md: the View decides navigation).
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            HomeView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(GameViewModel())
}
