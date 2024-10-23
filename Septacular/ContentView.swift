import SwiftUI
import MapKit

struct Train: Codable, Identifiable {
    let lat: String
    let lon: String
    let trainno: String
    let dest: String?
    let service: String?
    let currentstop: String?
    let nextstop: String?
    let line: String?
    let consist: String?
    let late: Int?
    let TRACK: String?
    let TRACK_CHANGE: String?
    
    // Use Trainno as the unique identifier
    var id: String {
        return trainno
    }
}

struct ContentView: View {
    @Environment(\.colorScheme) var colorScheme
    
    // State to track the region of the map and the fetched trains
    @State private var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 39.9526, longitude: -75.1652), span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
    @State var trains: [Train] = [] // State to store the list of trains
    
    var body: some View {
        NavigationView {
            VStack {
                Map(coordinateRegion: $region, annotationItems: trains) { train in
                    // Create a point annotation for each train
                    MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: Double(train.lat) ?? 0.0, longitude: Double(train.lon) ?? 0.0)) {
                        VStack {
                            Image(systemName: "train.side.front.car")
                                .foregroundColor(getRollingStock(consist: train.consist))
                                .font(.title)
                            
                            Text(train.trainno)
                                .padding(3)
                                .foregroundColor(colorScheme == .dark ? .white : .black) // Black text in light mode, white text in dark mode
                                .background(colorScheme == .dark ? Color.black : Color.white) // White background in light mode, black background in dark mode
                                .cornerRadius(8)
                        }
                    }
                }
                
                List(trains, id: \.trainno) { train in
                    VStack(alignment: .leading) {
                        Text("\(train.line ?? "Unknown Line") Line: #\(train.trainno)")
                            .font(.headline)
                        Text("Next Stop: \(train.nextstop ?? "Unknown Next Stop")\nDestination: \(train.dest ?? "Unknown Destination")")
                            .font(.subheadline)
                    }
                }
                .onAppear {
                    self.fetchData() // Fetch train data when the map appears
                }
                
                // Button to refresh data manually
                Button(action: {
                    self.fetchData()
                }) {
                    Text("Refresh Train Data")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .navigationBarTitle("Septacular")
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
                let result = try decoder.decode([Train].self, from: data)
                DispatchQueue.main.async {
                    self.trains = result // Update the trains state with the fetched data
                }
            } catch {
                print("JSON decoding failed: \(error.localizedDescription)")
            }
        }.resume()
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
