//
//  Train.swift
//  Septacular
//
//  Created by Benjamin Ledbetter on 10/24/24.
//
import Foundation

//
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

enum NetworkError: Error {
    case invalidURL
    case noData
    case decodingError
}

struct NextTrain: Decodable, Identifiable {
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
}
