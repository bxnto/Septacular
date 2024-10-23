//
//  SeptacularApp.swift
//  Septacular
//
//  Created by Benjamin Ledbetter on 10/22/24.
//

import SwiftUI


// Train struct to map the JSON response from the SEPTA API
// Conforms to Identifiable to work with the Map view's annotationItems parameter



@main
struct SeptacularApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
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

