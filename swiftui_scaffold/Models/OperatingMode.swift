//
//  OperatingMode.swift
//  Cloud to Ground AI
//
//  The three operating modes. Each carries display metadata (label, color,
//  symbol) used by the GUI indicator chips.
//
//  Implements the core data type behind:
//    L2-MOD-001 (Ground mode capability),
//    L2-MOD-002 (atomic, user-visible mode transitions),
//    L2-GUI-002 (mode indicator).
//

import SwiftUI

enum OperatingMode: String, CaseIterable, Identifiable, Codable {
    case cloud
    case hybrid
    case ground

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cloud:  return "Cloud"
        case .hybrid: return "Hybrid"
        case .ground: return "Ground"
        }
    }

    /// Capability rank — higher is more capable. Used to decide whether a
    /// transition is a downgrade (and thus requires a user notice per L2-GUI-003).
    var capabilityRank: Int {
        switch self {
        case .cloud:  return 3
        case .hybrid: return 2
        case .ground: return 1
        }
    }

    var indicatorColor: Color {
        switch self {
        case .cloud:  return .blue
        case .hybrid: return .purple
        case .ground: return .green
        }
    }

    var sfSymbol: String {
        switch self {
        case .cloud:  return "cloud.fill"
        case .hybrid: return "cloud.bolt.fill"
        case .ground: return "leaf.fill"
        }
    }

    /// One-line user-facing description of what this mode means and what
    /// trade-offs it carries. Surfaced in the degradation notice and on
    /// the mode toggle's hover help.
    var capabilityBlurb: String {
        switch self {
        case .cloud:
            return "Full Claude. Highest capability. Uses internet and cloud tokens."
        case .hybrid:
            return "Claude orchestrates, local AI handles mechanical work. Reduces cloud tokens but requires internet."
        case .ground:
            return "Local AI only. Works offline and off-mains. Best for short questions and code tasks; capability is lower than Cloud."
        }
    }
}
