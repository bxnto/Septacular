//
//  Train.swift
//  Septacular
//
//  Created by Benjamin Ledbetter on 10/24/24.
//
import Foundation
import AlphabetScrollBar

//
struct Train: Codable, Identifiable, Equatable {
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
    
    // Equatable conformance
    static func ==(lhs: Train, rhs: Train) -> Bool {
        return lhs.lat == rhs.lat &&
               lhs.lon == rhs.lon &&
               lhs.trainno == rhs.trainno &&
               lhs.dest == rhs.dest &&
               lhs.service == rhs.service &&
               lhs.currentstop == rhs.currentstop &&
               lhs.nextstop == rhs.nextstop &&
               lhs.line == rhs.line &&
               lhs.consist == rhs.consist &&
               lhs.late == rhs.late &&
               lhs.TRACK == rhs.TRACK &&
               lhs.TRACK_CHANGE == rhs.TRACK_CHANGE
    }
}

enum NetworkError: Error {
    case invalidURL
    case noData
    case decodingError
}

struct NextTrain: Decodable, Identifiable, Equatable {
    var id = UUID()
    let origTrain: String?
    let origLine: String?
    let origDepartureTime: String?
    let origArrivalTime: String?
    let origDelay: String?
    let termTrain: String?
    let termLine: String?
    let termDepartureTime: String?
    let termArrivalTime: String?
    let connection: String?
    let termDelay: String?
    let isDirect: String

    // Coding keys to map the JSON keys with snake_case to the camelCase in Swift
    enum CodingKeys: String, CodingKey {
        case origTrain = "orig_train"
        case origLine = "orig_line"
        case origDepartureTime = "orig_departure_time"
        case origArrivalTime = "orig_arrival_time"
        case origDelay = "orig_delay"
        case termTrain = "term_train"
        case termLine = "term_line"
        case termDepartureTime = "term_depart_time"
        case termArrivalTime = "term_arrival_time"
        case connection = "Connection"
        case termDelay = "term_delay"
        case isDirect = "isdirect"
    }
    
    // Equatable conformance
    static func ==(lhs: NextTrain, rhs: NextTrain) -> Bool {
        return lhs.origTrain == rhs.origTrain &&
               lhs.origLine == rhs.origLine &&
               lhs.origDepartureTime == rhs.origDepartureTime &&
               lhs.origArrivalTime == rhs.origArrivalTime &&
               lhs.origDelay == rhs.origDelay &&
               lhs.termTrain == rhs.termTrain &&
               lhs.termLine == rhs.termLine &&
               lhs.termDepartureTime == rhs.termDepartureTime &&
               lhs.termArrivalTime == rhs.termArrivalTime &&
               lhs.connection == rhs.connection &&
               lhs.termDelay == rhs.termDelay &&
               lhs.isDirect == rhs.isDirect
    }
}

struct ScheduleData: Decodable {
    var schedules: [String: [String: [String: [TrainSchedule]]]]
}

struct TrainSchedule: Decodable {
    var train: String
    var stops: [Stop] // Define stops as an ordered array of `Stop`

    struct Stop: Decodable {
        var stop: String // stop name
        var time: String // stop time
    }
}

struct StopList: Decodable {
    let stops: [String] // Array of stops
    
    // Optional initializer to handle cases where stops are missing or malformed
    init(stops: [String]) {
        self.stops = stops
    }
}

struct AlertResponse: Codable {
    let current: [String]?
    let advisory: [Advisory]
}

struct Advisory: Codable, Identifiable {
    var id: String { title } // Use title as a unique identifier
    let title: String
    let datesAffected: String
    let description: String

    enum CodingKeys: String, CodingKey {
        case title
        case datesAffected = "dates_affected"
        case description
    }
}

struct Stop: Alphabetizable {
    var id: String { self.name }
    let name: String
}

