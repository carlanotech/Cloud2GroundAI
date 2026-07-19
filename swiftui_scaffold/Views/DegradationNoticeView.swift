//
//  DegradationNoticeView.swift
//  Cloud to Ground AI
//
//  In-flow notice shown on any mode transition that reduces AI
//  capability. Dismissible but not suppressible per L2-GUI-003.
//
//  Implements L2-GUI-003 (degradation disclosure on mode change).
//

import SwiftUI

struct DegradationNotice: Equatable {
    let from: OperatingMode
    let to: OperatingMode
    let source: ModeTransition.Source

    init(from t: ModeTransition) {
        self.from = t.from
        self.to = t.to
        self.source = t.source
    }

    var headline: String {
        switch source {
        case .user:
            return "Switched to \(to.label) mode"
        case .networkDrop:
            return "Internet lost — switched to \(to.label) mode"
        }
    }

    var body: String {
        "\(to.capabilityBlurb) New conversation thread started; the previous thread is still in your history."
    }
}

struct DegradationNoticeView: View {
    let notice: DegradationNotice
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.headline)
                    .font(.system(size: 13, weight: .semibold))
                Text(notice.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .overlay(Divider(), alignment: .bottom)
    }
}
