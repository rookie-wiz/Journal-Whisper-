//
//  CrisisResourcesView.swift
//  Journal-Whisper
//
//  Where to get help right now. Opened from the support card (shown when an
//  entry mentions self-harm, suicide, abuse or danger) and from the journal
//  menu. Calm, direct, and nothing between the user and a phone number.
//

import SwiftUI

struct CrisisResourcesView: View {
    /// Region whose helplines are shown first; starts from the device's region.
    @State private var region: String? = Locale.current.region?.identifier

    private var current: RegionResources? { CrisisResources.resources(for: region) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("You're not alone", systemImage: "heart.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.pink)
                    Text("If you're thinking about suicide, might hurt yourself, or don't feel safe, please reach out now. Talking to someone can help.")
                        .font(.body)
                }
                .padding(.vertical, 4)
            }

            Section("In immediate danger") {
                if let current {
                    if let url = CrisisResources.callURL(current.emergency.dial) {
                        Link(destination: url) {
                            Label("Call emergency services (\(current.emergency.display))", systemImage: "phone.fill")
                                .font(.headline)
                                .foregroundStyle(.red)
                        }
                        .accessibilityIdentifier("callEmergency")
                    }
                } else {
                    Text("Call your local emergency number.")
                        .font(.headline)
                }
            }

            if let current {
                Section {
                    ForEach(current.helplines) { helpline in
                        HelplineRow(helpline: helpline)
                    }
                } header: {
                    Text("Talk to someone · \(current.name)")
                }
            }

            Section {
                Link(destination: CrisisResources.directory) {
                    Label("Find a helpline in another country", systemImage: "globe")
                }
                .accessibilityIdentifier("findAHelpline")
                Menu {
                    ForEach(CrisisResources.regions) { resources in
                        Button(resources.name) { region = resources.region }
                    }
                } label: {
                    Label(current == nil ? "Choose a country" : "Show another country", systemImage: "list.bullet")
                }
                .accessibilityIdentifier("chooseRegion")
            } header: {
                Text(current == nil ? "Find help near you" : "Somewhere else?")
            } footer: {
                Text("Journal Whisper can't contact anyone for you and never sends what you write anywhere. Helplines checked \(CrisisResources.lastChecked).")
            }
        }
        .navigationTitle("Get Support")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("crisisResources")
    }
}

private struct HelplineRow: View {
    let helpline: Helpline

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(helpline.name).font(.headline)
            Text(helpline.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if let call = helpline.call, let url = CrisisResources.callURL(call.dial) {
                    Link(destination: url) {
                        // White, or the icon takes the link tint and vanishes on the blue fill.
                        Label("Call \(call.display)", systemImage: "phone.fill")
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("call-\(call.dial)")
                }
                if let text = helpline.text, let url = CrisisResources.textURL(text.dial) {
                    Link(destination: url) {
                        Label("Text", systemImage: "message.fill")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Text \(text.display)")
                }
                if let website = helpline.website {
                    Link(destination: website) {
                        Label("Website", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack { CrisisResourcesView() }
}
