import SwiftUI
import MapKit
import Foundation
import CoreLocation
import AlphabetScrollBar
import Combine

// Class for all running trains
class TrainData: ObservableObject {
    @Published var trains: [Train] = []
    private var timer: Timer?
    
    init() {
        startTimer()
    }

    func fetchData() {
        guard let url = URL(string: "https://www3.septa.org/api/TrainView/index.php") else { // Verify Correct URL
            print("Invalid URL")
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url) // Get Data from SEPTA API
                let results = try JSONDecoder().decode([Train].self, from: data) // Decode the data

                // Assign trains directly without sorting
                await MainActor.run { [weak self] in
                    self?.trains = results
                }
            } catch {
                print("Error fetching or decoding data: \(error)")
            }
        }
    }

    // Repeats the fetch function
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 7, repeats: true) { [weak self] _ in
            self?.fetchData()
        }
    }

    deinit {
        timer?.invalidate()  // Cancel the timer when the object is deallocated
    }
}

// New ObservableObject to manage fetching next trains for favorites
class FavoritesNextTrainsManager: ObservableObject {
    @Published var nextTrainsByFavorite: [String: [NextTrain]] = [:]
    @Published var isLoading: [String: Bool] = [:]
    private var cancellable: AnyCancellable?
    private var timer: Timer?

    var viewModel: ViewModel

    init(viewModel: ViewModel) {
        self.viewModel = viewModel
        startTimer()
        Task { @MainActor in
            self.observeFavorites()
        }
    }

    deinit {
        timer?.invalidate()
        cancellable?.cancel()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.refreshAllFavorites()
            }
        }
    }

    @MainActor
    private func observeFavorites() {
        cancellable = viewModel.$favorites.sink { [weak self] _ in
            self?.clearData()
            self?.refreshAllFavorites()
        }
    }

    func clearData() {
        DispatchQueue.main.async {
            self.nextTrainsByFavorite = [:]
            self.isLoading = [:]
        }
    }

    @MainActor private func refreshAllFavorites() {
        for pair in viewModel.favorites {
            fetchNextTrains(for: pair.start, end: pair.end)
        }
    }

    func fetchNextTrains(for start: String, end: String) {
        let key = "\(start)|\(end)"
        if isLoading[key] == true {
            return
        }
        DispatchQueue.main.async {
            self.isLoading[key] = true
        }
        Task {
            do {
                let trains = try await nextToArrive(start: start, end: end, n: 3)
                await MainActor.run {
                    self.nextTrainsByFavorite[key] = trains
                    self.isLoading[key] = false
                }
            } catch {
                await MainActor.run {
                    self.nextTrainsByFavorite[key] = []
                    self.isLoading[key] = false
                }
            }
        }
    }
}

// Main View
struct HomeView: View {
    @State private var isListCollapsed: Bool = false // Track collapse state
    @EnvironmentObject var viewModel: ViewModel // Use EnvironmentObject instead of StateObject
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var locationManager = LocationManager()
    @EnvironmentObject var trainData: TrainData
    @State private var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 39.9526, longitude: -75.1652), span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3))
    @State private var coordinatesData: [[[[Double]]]] = [] // Holds GeoJSON data
    @ObservedObject var schedulesManager = SchedulesManager.shared
    @StateObject private var favoritesNextTrainsManager: FavoritesNextTrainsManager
    
    @State private var selectedTrain: Train? = nil
    @State private var isShowingDetails = false

    init() {
        // Initialize _favoritesNextTrainsManager with a dummy ViewModel; will be replaced in body
        _favoritesNextTrainsManager = StateObject(wrappedValue: FavoritesNextTrainsManager(viewModel: ViewModel()))
    }

    var body: some View {
        NavigationStack {
            VStack {
                ZStack(alignment: .bottomTrailing) {
                    // Map View
                    // Added print statement per instructions and update trains param to trainData.trains
                    TrainMapView(region: $region, trains: trainData.trains, coordinatesData: $coordinatesData, selectedTrain: $selectedTrain, isShowingDetails: $isShowingDetails)
                        .onAppear {
                            loadGeoJSONFile()
                        }
                    // Toggle Button on the top-left corner of the map
                    Button(action: {
                        withAnimation {
                            isListCollapsed.toggle()
                        }
                    }) {
                        Image(systemName: isListCollapsed ? "arrow.right.circle" : "arrow.down.circle")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.7).clipShape(Circle()))
                            .padding([.bottom, .trailing], 20)
                    }
                }

                // Conditionally show FavoritesNextTrainsList based on isListCollapsed state
                if !isListCollapsed {
                    FavoritesNextTrainsList()
                        .transition(.move(edge: .bottom))
                        .environmentObject(favoritesNextTrainsManager)
                }
            }
            .navigationBarTitle("Septacular")
            .preferredColorScheme(.dark)
            .toolbarBackground(Color.red, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        trainData.fetchData()
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: HelpView()) {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .tint(.white)
            .navigationDestination(isPresented: $isShowingDetails) {
                if let train = selectedTrain {
                    TrainDetailsView(train: train)
                }
            }
        }
        .environmentObject(favoritesNextTrainsManager)
        .environmentObject(viewModel)
        .environmentObject(trainData)
        .onAppear {
            schedulesManager.fetchSchedules()
            // Fix favoritesNextTrainsManager's viewModel reference here
            favoritesNextTrainsManager.viewModel = viewModel
        }
    }
    
    func loadGeoJSONFile() {
        if let url = Bundle.main.url(forResource: "septa", withExtension: "geojson") {
            do {
                let data = try Data(contentsOf: url)
                if let loadedCoordinates = convertGeoJSONToCoordinates(data: data) {
                    DispatchQueue.main.async {
                        coordinatesData = loadedCoordinates
                    }
                }
            } catch {
                print("Error loading file: \(error)")
            }
        }
    }
}

// Updated FavoritesNextTrainsList with added trainData environment object and passing trains to FavoriteTrainInfoView
struct FavoritesNextTrainsList: View {
    @EnvironmentObject var viewModel: ViewModel
    @EnvironmentObject var manager: FavoritesNextTrainsManager
    @EnvironmentObject var trainData: TrainData

    var body: some View {
        if viewModel.favorites.isEmpty {
            Text("No favorites added.")
                .padding()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.favorites) { pair in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(pair.start) → \(pair.end)")
                                .font(.headline)
                                .padding(.bottom, 2)
                            if let trains = manager.nextTrainsByFavorite["\(pair.start)|\(pair.end)"], !trains.isEmpty {
                                ForEach(trains.prefix(3), id: \.origTrain) { train in
                                    FavoriteTrainInfoView(nextTrain: train, trains: trainData.trains)
                                        .padding(.vertical, 2)
                                }
                            } else {
                                Text("No upcoming trains found.")
                            }
                        }
                    Divider()
                    }
                }
                .padding()
                .onChange(of: viewModel.favorites) { _ in
                    manager.clearData()
                }
            }
        }
    }
}

// Updated FavoriteTrainInfoView to accept trains and lookup matching Train
struct FavoriteTrainInfoView: View {
    var nextTrain: NextTrain
    var trains: [Train]

    var body: some View {
        // Try to find a matching Train by origTrain
        let matchingTrain = trains.first { $0.trainno == nextTrain.origTrain }
        VStack(alignment: .leading) {
            Text("Train: #\(nextTrain.origTrain ?? "N/A")")
            if let train = matchingTrain {
                Text("Consist: \(getRollingStock(consist: train.consist))")
            }
            Text("Departure: \(checkTime(departTime: nextTrain.origDepartureTime!, estDelay: nextTrain.origDelay!))")
            Text("Arrival: \(checkTime(departTime: nextTrain.origArrivalTime!, estDelay: nextTrain.origDelay!))")
            Text("Delay: \(nextTrain.origDelay ?? "N/A")")
            if nextTrain.isDirect == "false" {
                Text("\nTransfer at \(nextTrain.connection ?? "N/A")\n")
                Text("Connecting Train: #\(nextTrain.termTrain ?? "N/A")")
                Text("Departure: \(checkTime(departTime: nextTrain.termDepartureTime!, estDelay: nextTrain.termDelay!))")
                Text("Arrival: \(checkTime(departTime: nextTrain.termArrivalTime!, estDelay: nextTrain.termDelay!))")
                Text("Delay: \(nextTrain.termDelay ?? "N/A")")
            }
        }
    }
    
    private func checkTime(departTime: String, estDelay: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "h:mma"
        
        if estDelay == "On time" {
            return departTime
        } else {
            guard let date = dateFormatter.date(from: departTime) else {
                print("Invalid time format")
                return ""
            }
            
            let timeLate = estDelay.split(separator: " ").first
            guard let timeLateInt = Int(timeLate!) else { return departTime }
            
            if let newDepartTime = Calendar.current.date(byAdding: .minute, value: timeLateInt, to: date) {
                return "\(departTime) (Now: \(dateFormatter.string(from: newDepartTime)))" // Convert back to string
            } else {
                print("Failed to add minutes")
                return ""
            }
        }
    }
}

struct HelpView: View {
    var body: some View {
        VStack(alignment:.center) {
            Text("Welcome to Septacular!")
                .font(.title)
                .padding(.top)
            
            Text("Here are some things to note:")
                .font(.title3)
                .padding([.leading, .bottom])
            
            List {
                Text("A blue train indicates a Silverliner IV type train.")
                Text("A red train indicates a Silverliner V type train.")
                Text("An orange train indicates a Silverliner IV heritage unit.")
                Text("A green train indicates a Push-Pull set (aka a Bomber train).")
                Text("Tap on a train on the map for more information.")
                Text("Add frequent station pairs to the home page through the \"Next to Arrive\" tab")
                Text("All data is updated every 5 to 10 seconds.")
            }
            .listStyle(PlainListStyle())
        }
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.red, for: .navigationBar)
    }
}

// Map
struct TrainMapView: View {
    @Binding var region: MKCoordinateRegion
    var trains: [Train]
    @Environment(\.colorScheme) var colorScheme
    @Binding var coordinatesData: [[[[Double]]]] // Add this binding for the GeoJSON data
    @Binding var selectedTrain: Train?
    @Binding var isShowingDetails: Bool

    var body: some View {
        ZStack {
            GeoJSONMapView(coordinatesData: $coordinatesData, trains: trains, selectedTrain: $selectedTrain)
                .cornerRadius(10)
                .shadow(radius: 5)
                .padding()
        }
        .onChange(of: selectedTrain) { newValue in
            isShowingDetails = newValue != nil
            print("Selected train changed to: \(newValue?.trainno ?? "nil")")
        }
        .onChange(of: isShowingDetails) { newValue in
            if !newValue {
                selectedTrain = nil
            }
        }
    }
}

// List of running trains
struct TrainListView: View {
    var trains: [Train]
    
    var body: some View {
            List(trains, id: \.trainno) { train in
                NavigationLink(destination: TrainDetailsView(train: train)) {
                    VStack(alignment: .leading) {
                        Text("\(train.line ?? "Unknown Line") Line: #\(train.trainno)")
                            .font(.headline)
                        Text("Next Stop: \(train.nextstop ?? "Unknown Next Stop")\nDestination: \(train.dest ?? "Unknown Destination")")
                            .font(.subheadline)
                    }
                }
            }
        }
    }

// Details on a running train
struct TrainDetailsView: View {
    let train: Train
    
    var body: some View {
            List {
                Text("Line: \(train.line ?? "")")
                Text("Next Stop: \(train.nextstop ?? "Unknown")")
                Text("Destination: \(train.dest ?? "Unknown")")
                Text("Status: \(returnLateAsString(train.late ?? 0))")
                Text("Train Type: \(getRollingStock(consist: train.consist))")
            }
            .navigationBarTitle("Train: #\(train.trainno)")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDisabled(true)
            .preferredColorScheme(.dark)
            .toolbarBackground(Color.red, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        
    private func returnLateAsString(_ late: Int) -> String {
        if late == 0 {
            return "On Time"
        } else {
            return "\(late) minutes late"
        }
    }
}

class SchedulesManager: ObservableObject {
    static let shared = SchedulesManager()

    @Published var schedules: [String: [String: [String: [TrainSchedule]]]] = [:]
    @Published var isLoading: Bool = true

    private init() {} // Private initializer to enforce singleton

    func fetchSchedules() {
        isLoading = true

        // Attempt to load cached data first
        if let cachedData = loadCachedSchedules() {
            decodeAndUpdateSchedules(from: cachedData)
        }

        // Fetch from network
        guard let url = URL(string: "https://benjiled.pythonanywhere.com/schedules") else { return }
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("Network error: \(error?.localizedDescription ?? "Unknown error")")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }

            // Save new data to cache
            self.saveSchedulesToCache(data)
            self.decodeAndUpdateSchedules(from: data)
        }.resume()
    }

    private func saveSchedulesToCache(_ data: Data) {
        let fileURL = getSchedulesCacheFileURL()
        do {
            try data.write(to: fileURL)
        } catch {
            print("Failed to cache schedules data: \(error.localizedDescription)")
        }
    }

    private func loadCachedSchedules() -> Data? {
        let fileURL = getSchedulesCacheFileURL()
        return try? Data(contentsOf: fileURL)
    }

    private func getSchedulesCacheFileURL() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("cachedSchedules.json")
    }

    private func decodeAndUpdateSchedules(from data: Data) {
        do {
            let scheduleData = try JSONDecoder().decode(ScheduleData.self, from: data)
            DispatchQueue.main.async {
                self.schedules = scheduleData.schedules
                self.isLoading = false
            }
        } catch {
            print("Decoding error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
    }
}

// Schedules Tab
struct ScheduleView: View {
    @ObservedObject private var schedulesManager = SchedulesManager.shared

    var body: some View {
        VStack {
            if schedulesManager.isLoading {
                ProgressView("Loading schedules...")
            } else {
                LinesView()
            }
        }
    }
}

struct LinesView: View {
    var body: some View {
        NavigationStack {
            List {
                // Combined Schedules section with "ccp" and "gln"
                Section(header: Text("Combined Schedules")) {
                    ForEach(SchedulesManager.shared.schedules.keys.sorted(), id: \.self) { lineCode in
                        if lineCode == "ccp" || lineCode == "gln" {
                            NavigationLink(destination: DaysView(whichLine: lineCode)) {
                                Text(returnLineName(lineName: lineCode))
                            }
                        }
                    }
                }
                
                // Regular lines section
                Section(header: Text("Lines")) {
                    ForEach(SchedulesManager.shared.schedules.keys.sorted(), id: \.self) { lineCode in
                        if lineCode != "ccp" && lineCode != "gln" {
                            NavigationLink(destination: DaysView(whichLine: lineCode)) {
                                Text(returnLineName(lineName: lineCode))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Lines")
        }
    }
}


// List of next trains + schedules and alerts for the line of the first train.
struct NextTrainsSection: View {
    var nextTrains: [NextTrain]
    var matches: [(Train, NextTrain)]
    
    var body: some View {
        Section(header: Text("Next Trains (Live)")) {
            if nextTrains.isEmpty {
                Text("No Trains Found")
            } else {
                let lineName = nextTrains.first?.origLine ?? ""
                let lineCode = returnScheduleType(lineName: lineName)

                NavigationLink(destination: DaysView(whichLine: lineCode)) {
                    Text("\(lineName) Line Schedules and Alerts")
                        .font(.headline)
                        .foregroundColor(.blue)
                }

                ForEach(nextTrains) { nextTrain in
                    if let match = matches.first(where: { $0.1.origTrain == nextTrain.origTrain }) {
                        TrainInfoView(train: match.0, nextTrain: nextTrain)
                    } else {
                        TrainInfoView(train: nil, nextTrain: nextTrain)
                    }
                }
            }
        }
    }
}


// Displays the days options for a specific line
struct DaysView: View {
    let whichLine: String
    @State private var alerts: [Advisory] = []
    @State private var currentMessages: [String]?
    
    var body: some View {
        let scheduleForAGivenDay = SchedulesManager.shared.schedules[whichLine] ?? [:] // Use singleton

        List {
            Section(header: Text("Schedules").bold()) {
                ForEach(scheduleForAGivenDay.keys.sorted(), id: \.self) { day in
                    if let daysSelected = scheduleForAGivenDay[day] {
                        NavigationLink(destination: ScheduleListView(day: day, whichLine: whichLine, schedulesForDays: daysSelected)) {
                            Text(returnDays(day: day))
                        }
                    }
                }
            }
            
            if let currentMessages = currentMessages {
                if !currentMessages.isEmpty {
                    Section(header: Text("Current Advisory").bold()) {
                        ForEach(currentMessages, id: \.self) { currentMessage in
                            Text(currentMessage)
                                .foregroundColor(.red)
                                .bold()
                        }
                        
                    }
                }
            }
            
            if !alerts.isEmpty {
                Section(header: Text("Service Advisories").bold()) {
                    ForEach(alerts, id: \.title) { alert in
                        VStack(alignment: .leading) {
                            Text(alert.title)
                                .font(.headline)
                            Text(alert.datesAffected)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            // Check if description is a valid URL
                            if let url = URL(string: alert.description), UIApplication.shared.canOpenURL(url) {
                                // If it's a valid URL, make it a clickable link
                                Link(alert.description, destination: url)
                                    .font(.body)
                                    .foregroundColor(.blue)
                                    .padding(.vertical, 4)
                            } else {
                                // Otherwise, just display the description as text
                                Text(alert.description)
                                    .font(.body)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(returnLineName(lineName: whichLine))
        .onAppear {
            fetchAlerts(for: whichLine)
        }
    }
    
    private func fetchAlerts(for line: String) {
        guard let url = URL(string: "https://benjiled.pythonanywhere.com/alerts/\(line)") else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else { return }
            do {
                let alertResponse = try JSONDecoder().decode(AlertResponse.self, from: data)
                DispatchQueue.main.async {
                    self.currentMessages = alertResponse.current
                    self.alerts = alertResponse.advisory
                }
            } catch {
                print("Failed to decode alerts:", error)
            }
        }.resume()
    }
}

struct ScheduleListView: View {
    let day: String
    let whichLine: String
    let schedulesForDays: [String: [TrainSchedule]]
    
    var body: some View {
        ScrollView(.vertical) {
            if whichLine == "ccp" {
                Text("Towards 30th Street and Penn Medicine")
                    .padding()
                    .font(.title3)
                    .fontWeight(.bold)
            } else if whichLine == "air" {
                Text("To Center City and Glenside")
                    .padding()
                    .font(.title3)
                    .fontWeight(.bold)
            } else {
                Text("To Center City")
                    .padding()
                    .font(.title3)
                    .fontWeight(.bold)
            }
            HStack {
                // Display stops vertically
                VStack {
                    Text("Stops")
                        .font(.headline)
                        .fontWeight(.bold)
                    ForEach(Array(schedulesForDays["inbound"]?.first?.stops.enumerated() ?? [].enumerated()), id: \.element.stop) { index, stop in
                        Text(stop.stop)
                            .font(.subheadline)
                            .fixedSize(horizontal: true, vertical: false) // Prevent wrapping
                            .padding(4)
                            .background(index % 2 == 0 ? Color.gray.opacity(0.2) : Color.clear)
                            .cornerRadius(4)
                    }
                }

                // Horizontal scroll for the times
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(schedulesForDays["inbound"] ?? [], id: \.train) { schedule in
                            VStack {
                                Text("#\(cleanTrainNumber(numberAndDestination: schedule.train))")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                ForEach(Array(schedule.stops.enumerated()), id: \.element.stop) { index, stop in
                                    Text(stop.time)
                                        .font(.subheadline)
                                        .frame(width: 80, alignment: .center)
                                        .padding(4)
                                        .background(index % 2 == 0 ? Color.gray.opacity(0.2) : Color.clear)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                }
            }
            .padding()

            if whichLine == "ccp" {
                Text("Towards Temple University")
                    .padding()
                    .font(.title3)
                    .fontWeight(.bold)
            } else if whichLine == "air" {
                Text("To Airport")
                    .padding()
                    .font(.title3)
                    .fontWeight(.bold)
            } else {
                Text("From Center City")
                    .padding()
                    .font(.title3)
                    .fontWeight(.bold)
            }
            HStack {
                // Display stops vertically
                VStack {
                    Text("Stops")
                        .fontWeight(.bold)
                        .font(.headline)
                    ForEach(Array(schedulesForDays["outbound"]?.first?.stops.enumerated() ?? [].enumerated()), id: \.element.stop) { index, stop in
                        Text(stop.stop)
                            .fixedSize(horizontal: true, vertical: false)
                            .font(.subheadline)
                            .padding(4)
                            .background(index % 2 == 0 ? Color.gray.opacity(0.2) : Color.clear)
                            .cornerRadius(4)
                    }
                }

                // Horizontal scroll for the times
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(schedulesForDays["outbound"] ?? [], id: \.train) { schedule in
                            VStack {
                                Text("#\(cleanTrainNumber(numberAndDestination: schedule.train))")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                ForEach(Array(schedule.stops.enumerated()), id: \.element.stop) { index, stop in
                                    Text(stop.time)
                                        .font(.subheadline)
                                        .frame(width: 80, alignment: .center)
                                        .padding(4)
                                        .background(index % 2 == 0 ? Color.gray.opacity(0.2) : Color.clear)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                }
            }.padding()
        }
        .navigationTitle("\(returnLineName(lineName: whichLine)) Line: \(returnDays(day: day))")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func cleanTrainNumber(numberAndDestination: String) -> String {
        let trainNumber = numberAndDestination.split(separator: " - ").first!
        return String(trainNumber)
    }
}


func returnLineName(lineName: String) -> String {
    if lineName == "air" {
        return ("Airport")
    } else if lineName == "ccp" {
        return("Center City Stations")
    } else if lineName == "che" {
        return("Chestnut Hill East")
    } else if lineName == "chw" {
        return("Chestnut Hill West")
    } else if lineName == "cyn" {
        return("Cynwyd")
    } else if lineName == "fox" {
        return("Fox Chase")
    } else if lineName == "gln" {
        return("Glenside Combined")
    } else if lineName == "lan" {
        return("Lansdale/Doylestown")
    } else if lineName == "med" {
        return("Media/Wawa")
    } else if lineName == "nor" {
        return("Manayunk/Norristown")
    } else if lineName == "pao" {
        return("Paoli/Thorndale")
    } else if lineName == "tre" {
        return("Trenton")
    } else if lineName == "war" {
        return("Warminster")
    } else if lineName == "wil" {
        return("Wilmington/Newark")
    } else if lineName == "wtr" {
        return("West Trenton")
    } else {
        return ("Not a valid line")
    }
}

func returnDays(day: String) -> String {
    if day == "mon-fri"{
        return("Weekdays")
    } else if day == "sat" {
        return("Saturday")
    } else if day == "sun" {
        return("Sunday")
    } else {
        return("Not a valid day")
    }
}

struct NextTrainView: View {
    @EnvironmentObject var viewModel: ViewModel
    @EnvironmentObject var trainData: TrainData
    @StateObject private var locationManager = LocationManager()
    @State private var matches: [(Train, NextTrain)] = [] // Cache matches
    @State private var lastTrainData: [Train] = [] // Track last train data
    @State private var lastNextTrains: [NextTrain] = [] // Track last nextTrain data

    // Timer that fires every 20 seconds
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack {
                NextTrainListView(matches: $matches)
                    .onAppear {
                        fetchDataAndUpdateMatches()
                    }
                    .onChange(of: viewModel.start) { _ in
                        fetchDataAndUpdateMatches() // Fetch new data when `start` changes
                    }
                    .onChange(of: viewModel.end) { _ in
                        fetchDataAndUpdateMatches() // Fetch new data when `end` changes
                    }
                    .onReceive(refreshTimer) { _ in
                        fetchDataAndUpdateMatches()
                    }
                    .navigationTitle("Next to Arrive")
                    .navigationBarTitleDisplayMode(.inline)
                    .preferredColorScheme(.dark)
                    .toolbarBackground(Color.blue, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            RefreshButton {
                                fetchDataAndUpdateMatches()
                            }
                        }
                    }
                    .tint(.white)
            }
        }
    }

    private func fetchDataAndUpdateMatches() {
        Task {
            await viewModel.fetchNextTrains()
            trainData.fetchData()
            updateMatchesIfNeeded()
        }
    }

    private func updateMatchesIfNeeded() {
        if trainData.trains != lastTrainData || viewModel.nextTrains != lastNextTrains {
            lastTrainData = trainData.trains
            lastNextTrains = viewModel.nextTrains
            matches = doesTrainMatchNextTrain(trains: trainData.trains, nextTrains: viewModel.nextTrains)
        } else {
        }
    }
}


struct NextTrainListView: View {
    @EnvironmentObject var viewModel: ViewModel
    @EnvironmentObject var trainData: TrainData
    @Binding var matches: [(Train, NextTrain)]
    @State private var showFavoritesMenu = false // Controls menu visibility

    var body: some View {
        ZStack(alignment: .leading) {
            // Main Content
            List {
                StationSelectionSection()

                NextTrainsSection(nextTrains: viewModel.nextTrains, matches: matches)
            }
            .onAppear {
                viewModel.getStops() // Call getStops() when the view appears
            }

            // Overlay Menu for Favorite Station Pairs
            if showFavoritesMenu {
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        // Close menu if tap outside
                        withAnimation {
                            showFavoritesMenu = false
                        }
                    }

                FavoritesMenu {
                    // This closure is called when a favorite is selected
                    withAnimation {
                        showFavoritesMenu = false
                    }
                }
                .transition(.move(edge: .leading)) // Slide in from the left
                .animation(.easeInOut, value: showFavoritesMenu)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    withAnimation {
                        showFavoritesMenu.toggle() // Toggle menu visibility
                    }
                }) {
                    Image(systemName: "star")
                        .foregroundColor(.yellow)
                }
            }
        }
    }
}

struct FavoritesMenu: View {
    @EnvironmentObject var viewModel: ViewModel
    var onSelection: () -> Void // Closure called after a favorite is selected

    var body: some View {
        VStack(alignment: .leading) {
            Text("Favorite Station Pairs")
                .font(.headline)
                .padding(.top, 20)
                .padding(.leading, 20)
            
            ForEach(viewModel.favorites) { pair in
                Button(action: {
                    viewModel.start = pair.start
                    viewModel.end = pair.end
                    onSelection() // Hide the menu after selection
                }) {
                    HStack {
                        Text("\(pair.start) to \(pair.end)")
                            .padding()
                        Spacer()
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }

            Spacer()
        }
        .frame(width: 250)
        .background(Color.black)
        .cornerRadius(10)
        .shadow(radius: 5)
        .padding(.top, 44) // Adjust for navigation bar if necessary
        .padding(.bottom, 20)
    }
}

// Make sure the AlphabetStationPicker struct has the correct access level
struct StationSelectionSection: View {
    @EnvironmentObject var viewModel: ViewModel

    // Computed property to check if both `start` and `end` are set
    private var canShowFavoriteButton: Bool {
        viewModel.start != "---" && viewModel.end != "---"
    }

    private func flipStops() {
        let placeholder = viewModel.start
        viewModel.start = viewModel.end
        viewModel.end = placeholder
    }

    var body: some View {
        Section(header: Text("Select Stations")) {
            // Create NavigationLink for Start Station
            NavigationLink(destination: AlphabetStationPicker(stops: viewModel.stops, selection: $viewModel.start)) {
                HStack {
                    Text("Starting Station")
                    Spacer()
                    Text(viewModel.start)
                        .foregroundColor(viewModel.start == "---" ? .gray : .white)
                }
            }

            NavigationLink(destination: AlphabetStationPicker(stops: viewModel.stops, selection: $viewModel.end)) {
                HStack {
                    Text("Destination")
                    Spacer()
                    Text(viewModel.end)
                        .foregroundColor(viewModel.end == "---" ? .gray : .white)
                }
            }


            // Flip Stops Button
            Button {
                flipStops()
            } label: {
                Image(systemName: "arrow.up.and.down.circle")
            }
        }
        
        // Only show the favorite button if both start and end are valid
        if canShowFavoriteButton {
            Button(action: {
                if viewModel.isFavorite() {
                    viewModel.removeFavorite()
                } else {
                    viewModel.addFavorite()
                }
            }) {
                HStack {
                    Image(systemName: viewModel.isFavorite() ? "star.fill" : "star")
                        .foregroundColor(viewModel.isFavorite() ? .yellow : .gray)
                    Text(viewModel.isFavorite() ? "Unfavorite" : "Favorite")
                }
            }
        }
    }
}

struct AlphabetStationPicker: View {
    let stops: [Stop] // Array of stops
    @Binding var selection: String
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        
        NavigationView {
            AlphabetScrollView(
                collectionDisplayMode: .asList,
                collection: stops,
                sectionHeaderFont: .caption2.bold(),
                sectionHeaderForegroundColor: .secondary,
                resultAnchor: .top
            ) { stop in
                Button(action: {
                    selection = stop.name
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text(stop.name)
                        .foregroundStyle(.white)
                }
            }
            .navigationTitle("Select a Station")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

func returnScheduleType(lineName: String) -> String {
    let lineMapping: [String: String] = [
        "Airport": "air",
        "Chestnut Hill East": "che",
        "Chestnut Hill West": "chw",
        "Cynwyd": "cyn",
        "Fox Chase": "fox",
        "Lansdale/Doylestown": "lan",
        "Media/Wawa": "med",
        "Manayunk/Norristown": "nor",
        "Paoli/Thorndale": "pao",
        "Trenton": "tre",
        "Warminster": "war",
        "Wilmington/Newark": "wil",
        "West Trenton": "wtr"
    ]
    
    return lineMapping[lineName] ?? "Invalid line name"
}


struct TrainInfoView: View {
    var train: Train?
    var nextTrain: NextTrain

    var body: some View {
        if train == nil {
            VStack(alignment: .leading) {
                Text("Train: #\(nextTrain.origTrain ?? "N/A")")
                    .fontWeight(.heavy)
                Text("Departure: \(checkTime(departTime: nextTrain.origDepartureTime!, estDelay: nextTrain.origDelay!))")
                Text("Arrival: \(checkTime(departTime: nextTrain.origArrivalTime!, estDelay: nextTrain.origDelay!))")
                Text("Delay: \(nextTrain.origDelay ?? "N/A")")
                
                if nextTrain.isDirect == "false" {
                    Text("\nTransfer at \(nextTrain.connection ?? "N/A")\n")
                    Text("Connecting Train: #\(nextTrain.termTrain ?? "N/A")")
                    Text("Departure: \(checkTime(departTime: nextTrain.termDepartureTime!, estDelay: nextTrain.termDelay!))")
                    Text("Arrival: \(checkTime(departTime: nextTrain.termArrivalTime!, estDelay: nextTrain.termDelay!))")
                    Text("Delay: \(nextTrain.termDelay ?? "N/A")")
                }
            }
        } else {
            VStack(alignment: .leading) {
                Text("Train: #\(nextTrain.origTrain ?? "N/A")")
                    .fontWeight(.heavy)
                Text("Consist: \(getRollingStock(consist: train?.consist))")
                Text("Departure: \(checkTime(departTime: nextTrain.origDepartureTime!, estDelay: nextTrain.origDelay!))")
                Text("Arrival: \(checkTime(departTime: nextTrain.origArrivalTime!, estDelay: nextTrain.origDelay!))")
                Text("Delay: \(nextTrain.origDelay ?? "N/A")")
                
                if nextTrain.isDirect == "false" {
                    Text("\nTransfer at \(nextTrain.connection ?? "N/A")\n")
                    Text("Connecting Train: #\(nextTrain.termTrain ?? "N/A")")
                    Text("Departure: \(checkTime(departTime: nextTrain.termDepartureTime!, estDelay: nextTrain.termDelay!))")
                    Text("Arrival: \(checkTime(departTime: nextTrain.termArrivalTime!, estDelay: nextTrain.termDelay!))")
                    Text("Delay: \(nextTrain.termDelay ?? "N/A")")
                }
            }
        }
    }
        
    private func checkTime(departTime: String, estDelay: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "h:mma"
        
        if estDelay == "On time" {
            return departTime
        } else {
            guard let date = dateFormatter.date(from: departTime) else {
                print("Invalid time format")
                return ""
            }
            
            let timeLate = estDelay.split(separator: " ").first
            guard let timeLateInt = Int(timeLate!) else { return departTime }
            
            if let newDepartTime = Calendar.current.date(byAdding: .minute, value: timeLateInt, to: date) {
                return "\(departTime) (Now: \(dateFormatter.string(from: newDepartTime)))" // Convert back to string
            } else {
                print("Failed to add minutes")
                return ""
            }
        }
    }
}


struct RefreshButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
    }
}


func doesTrainMatchNextTrain(trains: [Train], nextTrains: [NextTrain]) -> [(Train, NextTrain)] {
    var matches: [(Train, NextTrain)] = []
    var matchedOrigTrains = Set<String>()

    for nextTrain in nextTrains {
        if matchedOrigTrains.contains(nextTrain.origTrain ?? "") {
            continue
        }

        var foundMatch = false
        for train in trains {
            if train.trainno == nextTrain.origTrain {
                matches.append((train, nextTrain))
                matchedOrigTrains.insert(nextTrain.origTrain ?? "")
                foundMatch = true
                break
            }
        }
        if foundMatch {
            matchedOrigTrains.insert(nextTrain.origTrain ?? "")
        }
    }
    return matches
}



// Updated getRollingStock to handle optional consist properly and restructured conditions
func getRollingStock(consist: String?) -> String {
    guard let consist = consist else {
        return "Unknown"
    }

    let consistArray = consist.split(separator: ",")
    let rawLength = consistArray.count
    let leadCarString = consistArray.first ?? "0"
    guard let leadCar = Int(leadCarString) else { return "Unknown" }

    let (type, length): (String, Int)
    if leadCar > 900 {
        type = "Push-Pull"
        length = max(rawLength - 1, 0)
    } else if leadCar > 700 {
        type = "Silverliner V"
        length = rawLength
    } else if leadCar > 0 {
        type = "Silverliner IV"
        length = rawLength
    } else {
        type = "Unknown"
        length = rawLength
    }

    return "\(length) Car \(type)"
}

func nextToArrive(start: String, end: String, n: Int) async throws -> [NextTrain] {
    let encodedStart = start.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
    let encodedEnd = end.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
    var url: URL
    
    if encodedStart != encodedEnd && encodedStart != "---" && encodedEnd != "---" {
        guard let validURL = URL(string: "https://www3.septa.org/api/NextToArrive/index.php?req1=\(encodedStart)&req2=\(encodedEnd)&req3=\(n)") else {
            throw NetworkError.invalidURL
        }
        url = validURL
    } else {
        return []
    }
    
    let (data, _) = try await URLSession.shared.data(from: url)

    guard !data.isEmpty else {
        throw NetworkError.noData
    }

    do {
        let decoder = JSONDecoder()
        return try decoder.decode([NextTrain].self, from: data)
    } catch {
        print("Failed to decode: \(error)")
        throw NetworkError.decodingError
    }
}

