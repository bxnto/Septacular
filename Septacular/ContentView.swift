import SwiftUI
import MapKit
import Foundation
import CoreLocation

struct HomeView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var locationManager = LocationManager()
    
    // State to track the region of the map and the fetched trains
    @State private var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 39.9526, longitude: -75.1652), span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3))
    @State var trains: [Train] = [] // State to store the list of trains
    
    var body: some View {
        NavigationStack {
            VStack {
                Map(coordinateRegion: $region, showsUserLocation: true, annotationItems: trains) { train in
                    // Create a point annotation for each train
                    MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: Double(train.lat) ?? 0.0, longitude: Double(train.lon) ?? 0.0)) {
                        NavigationLink(destination: TrainDetailsView(train: train)){
                            VStack {
                                Image(systemName: "train.side.front.car")
                                    .foregroundColor(getRollingStock(consist: train.consist))
                                    .font(.title)
                                    .frame(maxHeight: 40)
                                
                                Text(train.trainno)
                                    .padding(2)
                                    .foregroundColor(colorScheme == .dark ? .white : .black) // Black text in light mode, white text in dark mode
                                    .background(colorScheme == .dark ? Color.black : Color.white) // White background in light mode, black background in dark mode
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                .cornerRadius(10)
                .shadow(radius: 5)
                .padding()
                .padding(.bottom, -10)
                
                List(trains, id: \.trainno) { train in
                    NavigationLink(destination: TrainDetailsView(train: train)){
                        VStack(alignment: .leading) {
                            Text("\(train.line ?? "Unknown Line") Line: #\(train.trainno)")
                                .font(.headline)
                            Text("Next Stop: \(train.nextstop ?? "Unknown Next Stop")\nDestination: \(train.dest ?? "Unknown Destination")")
                                .font(.subheadline)
                        }
                    }
                }
                .onAppear {
                    self.fetchData() // Fetch train data when the map appears
                }
            }
            .navigationBarTitle("Septacular")
            .preferredColorScheme(.dark)
            .toolbarBackground(Color.red, for:.navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        self.fetchData()
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .tint(.white)
        }
    }
    
    // Function to fetch train data from SEPTA API
    func fetchData() {
        guard let url = URL(string: "https://www3.septa.org/api/TrainView/index.php") else {
            print("Invalid URL")
            return
        }

        URLSession.shared.dataTask(with: url) { (data, response, error) in
            if let error = error {
                print("Error fetching data: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("Error: No data")
                return
            }
            
            do {
                let decoder = JSONDecoder()
                let results = try decoder.decode([Train].self, from: data)

                // Check if current location is available
                if locationManager.isCurrentLocationAvailable(), let location = locationManager.location {
                    var trainDistances: [(train: Train, distance: CLLocationDistance)] = []
                    print("Current Location: \(location.coordinate)")
                    for train in results {
                        // Ensure the latitude and longitude are valid Double values
                        if let trainLat = Double(train.lat), let trainLon = Double(train.lon) {
                            let trainLocation = CLLocation(latitude: trainLat, longitude: trainLon)
                            let distance = location.distance(from: trainLocation)
                            trainDistances.append((train: train, distance: distance))
                        } else {
                            print("Invalid train coordinates for train: \(train.trainno)")
                        }
                    }
                    
                    // Sort the trains by distance
                    trainDistances.sort { $0.distance < $1.distance }

                    // Assign sorted trains back to self.trains
                    DispatchQueue.main.async {
                        self.trains = trainDistances.map { $0.train }
                    }

                    // Print sorted distances for verification
                    for trainDistance in trainDistances {
                        print("Train at \(trainDistance.train.lat), \(trainDistance.train.lon): \(trainDistance.distance) meters")
                    }
                } else {
                    // Handle the case when the current location is not available
                    DispatchQueue.main.async {
                        self.trains = results
                        print("Current location is unavailable. Displaying all trains without distance sorting.")
                    }
                }
            } catch {
                print("JSON decoding failed: \(error.localizedDescription)")
            }
        }.resume()
        
        // Schedule the next fetch
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            fetchData()
        }
    }

}

struct TrainDetailsView: View {
    let train: Train
    
    var body: some View {
            VStack {
                Text("Train \(train.trainno)")
                    .font(.title)
                    .padding()
                Text("Destination: \(train.dest ?? "")")
                    .padding()
                Text("Line: \(train.line ?? "")")
                    .padding()
                Spacer()
            }
        }
    }

struct NextTrainView: View {
    @StateObject var viewModel = ViewModel()

    var body: some View {
        NavigationStack {
            VStack {
                List {
                    Section(header: Text("Select Stations")) {
                        // Starting Station Picker
                        Picker("Starting Station", selection: $viewModel.start) {
                            ForEach(viewModel.stops, id: \.self) { stop in
                                Text(stop)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: viewModel.start) { newValue in
                            Task {
                                await viewModel.fetchNextTrains()
                            }
                        }
                        
                        // Destination Station Picker
                        Picker("Destination", selection: $viewModel.end) {
                            ForEach(viewModel.stops, id: \.self) { stop in
                                Text(stop)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: viewModel.end) { newValue in
                            Task {
                                await viewModel.fetchNextTrains()
                            }
                        }
                    }

                    // Train List
                    Section(header: Text("Next Trains")) {
                        if viewModel.nextTrains.isEmpty {
                            Text("No Trains Found")
                        }
                        else {
                            ForEach(viewModel.nextTrains) { train in
                                VStack(alignment: .leading) {
                                    Text("Train: \(train.origTrain ?? "N/A")")
                                    Text("Departure: \(train.origDepartureTime ?? "N/A")")
                                    Text("Arrival: \(train.origArrivalTime ?? "N/A")")
                                    Text("Delay: \(train.origDelay ?? "N/A")")
                                    
                                    if train.isDirect == "false" {
                                        Text("\nConnect at \(train.connection ?? "N/A")\n")
                                        Text("Train: \(train.termTrain ?? "N/A")")
                                        Text("Departure: \(train.termDepartureTime ?? "N/A")")
                                        Text("Arrival: \(train.termArrivalTime ?? "N/A")")
                                        Text("Delay: \(train.termDelay ?? "N/A")")
                                    }
                                }
                            }
                    }
                    }
                }
                .navigationTitle("Next to Arrive")
                .navigationBarTitleDisplayMode(.inline)
                .preferredColorScheme(.dark)
                .toolbarBackground(Color.blue, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Task {
                                await viewModel.fetchNextTrains()
                            }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                }
                .tint(.white)
            }
        }
    }
}



// Updated getRollingStock to handle optional consist properly and restructured conditions
func getRollingStock(consist: String?) -> Color {
    guard let consist = consist else {
        return .black
    }
    
    let consistArray = consist.split(separator: ",")
    
    if let leadCarString = consistArray.first,
       let leadCar = Int(leadCarString) {
        if leadCar > 900 {
            return .green
        } else if leadCar > 700 {
            return .red
        } else {
            return .blue
        }
    }
    return .black
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

