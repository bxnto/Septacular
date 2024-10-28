//
//  NextTrain.swift
//  Septacular
//
//  Created by Benjamin Ledbetter on 10/23/24.
//

import Foundation

class ViewModel: ObservableObject {
    @Published var start = "---"
    @Published var end = "---"
    
    @Published var stops = [
        "---","9th Street Lansdale", "30th Street Station", "49th St", "Airport Terminal A", "Airport Terminal B",
        "Airport Terminal C-D", "Airport Terminal E-F", "Allegheny",
        "Ambler", "Ardmore", "Ardsley", "Bala", "Berwyn",
        "Bethayres", "Bridesburg", "Bristol", "Bryn Mawr", "Carpenter",
        "Chalfont", "Chelten Avenue", "Cheltenham", "Chester TC","Chestnut Hill East",
        "Chestnut Hill West", "Churchmans Crossing", "Claymont",
        "Clifton-Aldan", "Colmar", "Conshohocken", "Cornwells Heights",
        "Crum Lynne", "Cynwyd", "Darby", "Daylesford",
        "Delaware Valley College", "Devon", "Downingtown", "Doylestown",
        "East Falls", "Eastwick Station", "Eddington", "Eddystone","Elkins Park",
        "Elm Street", "Elywn Station", "Ewing", "Exton",
        "Fern Rock TC", "Fernwood", "Folcroft", "Forest Hills",
        "Ft Washington", "Fox Chase", "Fortuna", "Germantown",
        "Gladstone", "Glenolden", "Glenside", "Gravers", "Gwynedd Valley",
        "Hatboro", "Haverford", "Highland Ave",
        "Highland", "Holmesburg Jct", "Ivy Ridge", "Jenkintown-Wyncote",
        "Jefferson Station", "Langhorne", "Lansdale", "Lansdowne",
        "Lawndale", "Levittown", "Link Belt",
        "Main St", "Malvern", "Marcus Hook", "Manayunk",
        "Media", "Melrose Park", "Merion", "Miquon",
        "Morton", "Mt. Airy", "Narberth", "Neshaminy Falls",
        "Norristown Elm Street", "Norwood", "North Broad", "North Hills",
        "North Philadelphia", "Oreland", "Overbrook", "Paoli",
        "Penllyn", "Pennbrook", "Philadelphia International Airport",
        "Philmont", "Pitman", "Primos", "Prospect Park",
        "Queen Lane", "Radnor", "Ridley Park", "Rosemont",
        "Roslyn", "Rydal", "Secane", "Sedgwick",
        "Sharon Hill", "Somerton", "Spring Mill", "St. Davids",
        "St. Martins", "Suburban Station", "Swarthmore", "Tacony",
        "Temple U", "Thorndale", "Torresdale", "Trenton",
        "Trevose", "Tulpehocken", "Penn Medicine Station", "Villanova",
        "Wallingford", "Warminster", "Wayne", "West Trenton",
        "Wilmington", "Willow Grove", "Wissahickon", "Woodbourne",
        "Wyndmoor", "Wynnefield Avenue", "Wynnewood", "Yardley"
    ]
    
    @Published var nextTrains: [NextTrain] = []

    func fetchNextTrains() async {
        do {
            let trains = try await nextToArrive(start: start, end: end, n: 5)
            DispatchQueue.main.async {
                self.nextTrains = trains
            }
        } catch {
            print("Failed to fetch trains: \(error)")
        }
    }
}
