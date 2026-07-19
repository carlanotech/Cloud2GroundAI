//
//  OnboardingView.swift
//  Cloud to Ground AI
//
//  First-run onboarding modal. Introduces the three modes, the network
//  status display, and the Ground-mode capability limits before the
//  user's first conversation.
//
//  Implements L2-GUI-005 (first-run onboarding flow).
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Welcome to Cloud to Ground AI",
            symbol: "leaf.circle.fill",
            color: .green,
            body: "An AI assistant that works whether you have internet or not. Three modes: Cloud, Hybrid, and Ground."
        ),
        OnboardingPage(
            title: "Three modes",
            symbol: "rectangle.3.group.fill",
            color: .blue,
            body: "Cloud — full Claude. Hybrid — Claude orchestrates and routes mechanical work to a local model to save cloud cost. Ground — local model only, works offline and off-mains."
        ),
        OnboardingPage(
            title: "We are honest about trade-offs",
            symbol: "checkmark.shield.fill",
            color: .purple,
            body: "Every response shows which AI produced it. When the app switches to a lower-capability mode you'll always see a notice. You will never be silently downgraded."
        ),
        OnboardingPage(
            title: "Ground mode — what to expect",
            symbol: "leaf.fill",
            color: .green,
            body: "The local model is good at short questions and code tasks. It is not as capable as Claude. When you're in Ground mode, treat it like a competent junior assistant — useful but worth double-checking on complex work."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    OnboardingPageView(page: pages[i]).tag(i)
                }
            }
            .tabViewStyle(.automatic)
            .frame(width: 480, height: 360)

            HStack {
                Button("Skip") { isPresented = false }
                Spacer()
                ForEach(pages.indices, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
                Spacer()
                if page < pages.count - 1 {
                    Button("Next") { withAnimation { page += 1 } }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Get started") { isPresented = false }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
    }
}

private struct OnboardingPage {
    let title: String
    let symbol: String
    let color: Color
    let body: String
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: page.symbol)
                .font(.system(size: 64))
                .foregroundStyle(page.color)
            Text(page.title)
                .font(.title2.bold())
            Text(page.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(24)
    }
}

// Settings view placeholder so C2GApp's `Settings` scene compiles
struct SettingsView: View {
    @EnvironmentObject var modeManager: ModeManager
    var body: some View {
        Form {
            Section("Behavior") {
                Text("Current mode: \(modeManager.currentMode.label)")
            }
            Section("About") {
                Text("Cloud to Ground AI — research preview")
                Text("Carlano Technology Solutions LLC")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 400, height: 240)
    }
}
