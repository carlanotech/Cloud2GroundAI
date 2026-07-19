//
//  ModeIndicator.swift
//  Cloud to Ground AI
//
//  Persistent visual indicator of the current operating mode. Always
//  visible whenever a conversation is on screen (L2-GUI-002).
//
//  Per the L2: color + label, not color alone (accessibility).
//

import SwiftUI

struct ModeIndicator: View {
    @EnvironmentObject var modeManager: ModeManager

    var body: some View {
        let mode = modeManager.currentMode
        HStack(spacing: 6) {
            Image(systemName: mode.sfSymbol)
                .font(.system(size: 12, weight: .semibold))
            Text(mode.label)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(mode.indicatorColor, in: Capsule())
        .accessibilityLabel("Operating mode: \(mode.label)")
        .help(mode.capabilityBlurb)
    }
}

#Preview {
    HStack {
        ForEach(OperatingMode.allCases) { mode in
            let mm = ModeManager()
            ModeIndicator()
                .environmentObject({ mm.userSelect(mode); return mm }())
        }
    }
    .padding()
}
