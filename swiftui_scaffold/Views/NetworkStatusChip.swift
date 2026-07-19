//
//  NetworkStatusChip.swift
//  Cloud to Ground AI
//
//  Persistent network connectivity indicator, distinct from mode chip.
//  Implements L2-GUI-004 — the user can be online in Ground mode (by
//  choice) or offline with Hybrid selected (broken until network back),
//  so both facts need to be visible independently.
//

import SwiftUI

struct NetworkStatusChip: View {
    @EnvironmentObject var networkMonitor: NetworkMonitor

    var body: some View {
        let status = networkMonitor.status
        HStack(spacing: 6) {
            Image(systemName: status.sfSymbol)
                .font(.system(size: 11, weight: .medium))
            Text(status.label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.12), in: Capsule())
        .overlay(
            Capsule().stroke(status.color.opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityLabel("Internet: \(status.label)")
    }
}

#Preview {
    HStack {
        NetworkStatusChip().environmentObject(NetworkMonitor())
    }
    .padding()
}
