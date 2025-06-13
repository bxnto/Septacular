//
//  SeptacularApp.swift
//  Septacular
//
//  Created by Benjamin Ledbetter on 10/22/24.
//

import SwiftUI

@main
struct SeptacularApp: App {
    @StateObject private var trainData = TrainData()
    @StateObject private var viewModel = ViewModel()
    @State var schedules: [String: [String: [String: [TrainSchedule]]]] = [:]

    
    var body: some Scene {
        WindowGroup {
            TabView {
                HomeView()
                    .environmentObject(trainData)
                    .environmentObject(viewModel)
                    .tabItem {
                        Label("Map", systemImage: "map")
                    }
                NextTrainView()
                    .tabItem {
                        Label("Next to Arrive", systemImage: "train.side.front.car")
                    }
                    .environmentObject(trainData)
                    .environmentObject(viewModel)
                
                ScheduleView()
                    .tabItem {
                        Label("Schedules and Alerts", systemImage: "calendar")
                    }
                    .environmentObject(viewModel)
            }
            
        }
    }
}

