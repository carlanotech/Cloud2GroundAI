//
//  NetworkStatus.swift
//  Cloud to Ground AI
//
//  Network connectivity state, distinct from operating mode. The user can
//  be online while in Ground mode (by choice) or offline while having last
//  selected Hybrid (in which case Hybrid is broken until network returns).
//  Both facts need to be visible independently per L2-GUI-004.
//
//  Implements the data side of L2-NET-001 (connectivity detection).
//

import SwiftUI

enum NetworkStatus: String, Codable, Equatable {
    case online
    case offline
    case unknown

    var label: String {
        switch self {
        case .online:  return "Online"
        case .offline: return "Offline"
        case .unknown: return "—"
        }
    }

    var color: Color {
        switch self {
        case .online:  return .green
        case .offline: return .orange
        case .unknown: return .secondary
        }
    }

    var sfSymbol: String {
        switch self {
        case .online:  return "wifi"
        case .offline: return "wifi.slash"
        case .unknown: return "wifi.exclamationmark"
        }
    }
}
