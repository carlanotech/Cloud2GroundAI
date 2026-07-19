//
//  ModeToggle.swift
//  Cloud to Ground AI
//
//  Bottom-of-window mode switcher. Three segments. Implements the
//  user-control side of L2-MOD-002 (manual mode change is the user's
//  primary lever).
//

import SwiftUI

struct ModeToggle: View {
    @EnvironmentObject var modeManager: ModeManager

    var body: some View {
        HStack {
            Spacer()
            Picker("Mode", selection: Binding(
                get: { modeManager.currentMode },
                set: { modeManager.userSelect($0) }
            )) {
                ForEach(OperatingMode.allCases) { mode in
                    HStack(spacing: 4) {
                        Image(systemName: mode.sfSymbol)
                        Text(mode.label)
                    }
                    .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
            Spacer()
        }
    }
}

#Preview {
    ModeToggle().environmentObject(ModeManager()).padding()
}
