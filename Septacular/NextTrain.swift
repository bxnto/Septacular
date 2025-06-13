//
//  NextTrain.swift
//  Septacular
//
//  Created by Benjamin Ledbetter on 10/23/24.
//

import Foundation
import SwiftUI

struct StationPair: Hashable, Identifiable {
    var start: String
    var end: String

    var id: String { "\(start)-\(end)" } // Unique ID based on start and end
}


@MainActor class ViewModel: ObservableObject {
    @Published var start = "---"
    @Published var end = "---"
    @Published var stops: [Stop] = []
    @Published var favorites: [StationPair] = []

    @Published var nextTrains: [NextTrain] = []
    
    init() {
        loadFavorites()
    }
    
    func getStops() {
        guard let url = URL(string: "https://benjiled.pythonanywhere.com/stops") else { return }
        
        // Attempt to load cached data first
        if let cachedData = loadCachedStops() {
            print("Loaded stops from cache")
            decodeAndUpdateStops(from: cachedData)
        }
        
        print("Fetching stops from network")
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("Network error: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            Task { @MainActor in
                self.saveStopsToCache(data)
                self.decodeAndUpdateStops(from: data)
            }
        }.resume()
    }
    
    // Function to save fetched stops data to cache
    func saveStopsToCache(_ data: Data) {
        let fileURL = getCacheFileURL()
        do {
            try data.write(to: fileURL)
            print("Stops data cached successfully")
        } catch {
            print("Failed to cache stops data: \(error.localizedDescription)")
        }
    }

    // Function to load cached stops data
    func loadCachedStops() -> Data? {
        let fileURL = getCacheFileURL()
        return try? Data(contentsOf: fileURL)
    }

    // Function to get the cache file URL in the app's Documents directory
    func getCacheFileURL() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("cachedStops.json")
    }

    // Decode and update stops on the main thread
    func decodeAndUpdateStops(from data: Data) {
        do {
            let stopList = try JSONDecoder().decode(StopList.self, from: data)
            DispatchQueue.main.async {
                self.stops = stopList.stops.map { Stop(name: $0) } // Convert strings to Stop objects
            }
        } catch {
            print("Decoding error: \(error.localizedDescription)")
        }
    }


    
    func fetchNextTrains() async {
        do {
            let trains = try await nextToArrive(start: start, end: end, n: 10)
            DispatchQueue.main.async { [weak self] in
                self?.nextTrains = trains
            }
        } catch {
            print("Failed to fetch trains: \(error)")
        }
    }
    
    func loadFavorites() {
        if let savedFavorites = UserDefaults.standard.array(forKey: "favoriteStationPairs") as? [[String]] {
            favorites = savedFavorites.map { StationPair(start: $0[0], end: $0[1]) }
        }
    }

    func addFavorite() {
        let pair = StationPair(start: start, end: end)
        if !favorites.contains(where: { $0 == pair }) {
            favorites.append(pair)
            saveFavorites()
        }
    }
            
    func removeFavorite() {
        favorites.removeAll { $0 == StationPair(start: start, end: end) }
        saveFavorites()
    }

    private func saveFavorites() {
        let favoritesToSave = favorites.map { [$0.start, $0.end] }
        UserDefaults.standard.set(favoritesToSave, forKey: "favoriteStationPairs")
    }

    func isFavorite() -> Bool {
        favorites.contains(where: { $0 == StationPair(start: start, end: end) })
    }

}

