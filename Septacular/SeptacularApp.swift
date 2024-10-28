//
//  SeptacularApp.swift
//  Septacular
//
//  Created by Benjamin Ledbetter on 10/22/24.
//

import SwiftUI

@main
struct SeptacularApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                HomeView()
                    .tabItem {
                        Label("Map", systemImage: "map")
                    }
                NextTrainView()
                    .tabItem {
                        Label("Next Train", systemImage: "arrow.2.circlepath")
                    }
            }
        }
    }
}

