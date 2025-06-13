import SwiftUI
import MapKit
import CoreLocation

// GeoJSON Structures
struct FeatureCollection: Codable {
    var type: String
    var features: [Feature]
}

struct Feature: Codable {
    var type: String
    var properties: Properties
    var geometry: Geometry
}

struct Properties: Codable {
    var agency_name: String?
    var route_id: String?
    var route_short_name: String?
    var route_long_name: String?
    var route_type: Int?
    var route_url: String?
    var route_color: String?
    var route_text_color: String?
}

struct Geometry: Codable {
    var type: String
    var coordinates: [[[Double]]]

    enum CodingKeys: String, CodingKey {
        case type
        case coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)

        if let coords = try? container.decode([[[Double]]].self, forKey: .coordinates) {
            coordinates = coords
        } else if let coords = try? container.decode([[Double]].self, forKey: .coordinates) {
            coordinates = [coords]
        } else {
            coordinates = []
        }
    }
}

func convertGeoJSONToCoordinates(data: Data) -> [[[[Double]]]]? {
    let decoder = JSONDecoder()
    do {
        let featureCollection = try decoder.decode(FeatureCollection.self, from: data)
        let coordinates = featureCollection.features.compactMap { feature in
            feature.geometry.type == "MultiLineString" ? feature.geometry.coordinates : nil
        }
        return coordinates
    } catch {
        print("Error decoding GeoJSON: \(error)")
        return nil
    }
}

// Map View
struct GeoJSONMapView: UIViewRepresentable {
    private let mapManager: MapManager
    @Binding var coordinatesData: [[[[Double]]]]
    var trains: [Train]
    @Binding var selectedTrain: Train?

    init(coordinatesData: Binding<[[[[Double]]]]>, trains: [Train], selectedTrain: Binding<Train?>) {
        self.mapManager = MapManager()
        _coordinatesData = coordinatesData
        self.trains = trains
        _selectedTrain = selectedTrain
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapManager.attachMapView(mapView)
        mapView.delegate = context.coordinator

        let defaultRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.0, longitude: -75.2),
            span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
        )
        mapView.setRegion(defaultRegion, animated: false)
        mapView.showsUserLocation = true

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeOverlays(uiView.overlays)
        uiView.removeAnnotations(uiView.annotations)

        for coordinateGroup in coordinatesData {
            for coordinates in coordinateGroup {
                let polylineCoordinates = coordinates.map {
                    CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
                }
                uiView.addOverlay(MKPolyline(coordinates: polylineCoordinates, count: polylineCoordinates.count))
            }
        }

        for train in trains {
            let annotation = TrainAnnotation(train: train, color: returnTrainColor(consist: train.consist))
            uiView.addAnnotation(annotation)
        }
    }

    func returnTrainColor(consist: String?) -> UIColor {
        let heritageUnits = ["280", "276", "293", "304", "401"]
        guard let consist = consist else { return .black }

        let consistArray = consist.split(separator: ",")

        if consistArray.contains(where: { heritageUnits.contains(String($0)) }) {
            return .orange
        } else if let leadCar = consistArray.first, let leadCarInt = Int(leadCar) {
            return leadCarInt > 900 ? .green : leadCarInt >= 700 ? .red : .blue
        }
        return .black
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: GeoJSONMapView

        init(_ parent: GeoJSONMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = UIColor.init(red: 0.5, green: 0, blue: 1.0, alpha: 1.0)
            renderer.lineWidth = 3.0
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let trainAnnotation = annotation as? TrainAnnotation else { return nil }
            let identifier = "TrainAnnotation"

            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

            if annotationView == nil {
                annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = false
            } else {
                annotationView?.annotation = annotation
                // Remove existing subviews to avoid duplicates
                annotationView?.subviews.forEach { $0.removeFromSuperview() }
            }

            let label = UILabel()
            label.text = trainAnnotation.title
            label.font = UIFont.boldSystemFont(ofSize: 12)
            label.textColor = .white
            label.backgroundColor = trainAnnotation.color
            label.sizeToFit()
            label.layer.cornerRadius = 5
            label.layer.masksToBounds = true
            label.textAlignment = .center

            // Add padding around label
            label.frame = CGRect(x: 0, y: 0, width: label.frame.width + 10, height: label.frame.height + 4)

            annotationView?.addSubview(label)
            annotationView?.frame = label.frame

            return annotationView
        }


        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let trainAnnotation = view.annotation as? TrainAnnotation else { return }
            parent.selectedTrain = trainAnnotation.train
        }
    }
}

class TrainAnnotation: MKPointAnnotation {
    var train: Train
    var color: UIColor

    init(train: Train, color: UIColor) {
        self.train = train
        self.color = color
        super.init()
        self.coordinate = CLLocationCoordinate2D(latitude: Double(train.lat) ?? 0.0, longitude: Double(train.lon) ?? 0.0)
        self.title = train.trainno
    }
}

class MapManager {
    private(set) var mapView: MKMapView?

    func attachMapView(_ mapView: MKMapView) {
        self.mapView = mapView
    }
}
