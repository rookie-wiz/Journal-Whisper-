//
//  AboutView.swift
//  Journal-Whisper
//
//  About & Privacy: AI status, the privacy policy, support, and deleting
//  everything.
//

import SwiftUI
import SwiftData

struct AboutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppLock.self) private var appLock

    @State private var isConfirmingDelete = false
    @State private var authFailed = false
    @State private var deleted = false

    var body: some View {
        List {
            Section {
                Text(PrivacyPolicy.summary)
                NavigationLink("Privacy Policy") { PrivacyPolicyView() }
                    .accessibilityIdentifier("privacyPolicyLink")
            } header: {
                Text("Privacy")
            }

            Section {
                Text(aiStatus)
                    .accessibilityIdentifier("aiStatus")
            } header: {
                Text("Apple Intelligence")
            }

            Section {
                NavigationLink {
                    CrisisResourcesView()
                } label: {
                    Label("Get Support", systemImage: "heart")
                }
                Text("Journal Whisper is a private journal, not a medical or crisis service.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Support")
            }

            Section {
                Button("Delete All Journal Data", role: .destructive) { isConfirmingDelete = true }
                    .disabled(appLock.isAuthenticating)
                    .accessibilityIdentifier("deleteAllData")
            } header: {
                Text("Your data")
            } footer: {
                Text(deleted
                     ? "All journal data has been deleted."
                     : "Removes every entry, mood and summary from this iPhone, including Recently Deleted. This can't be undone.")
            }

            Section {
                LabeledContent("Version", value: Self.version)
            }
        }
        .navigationTitle("About & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete all journal data?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) {
                Task { await deleteEverything() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every entry, mood and weekly summary will be removed from this iPhone. This can't be undone.")
        }
        .alert("Authentication Failed", isPresented: $authFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was deleted.")
        }
    }

    private var aiStatus: String {
        switch ReflectionAvailability.current {
        case .available:
            String(localized: "On. Mood suggestions, reflection prompts and weekly summaries are written on this iPhone.")
        case .deviceNotEligible:
            String(localized: "Not supported on this iPhone. Journal Whisper uses its built-in offline features instead.")
        case let other:
            other.note ?? String(localized: "Not available right now. Journal Whisper uses its built-in offline features instead.")
        }
    }

    private func deleteEverything() async {
        guard await appLock.authenticate(reason: "Delete all journal data") else {
            authFailed = true
            return
        }
        try? modelContext.delete(model: WeeklySummary.self)
        try? modelContext.delete(model: JournalEntry.self)
        try? modelContext.save()
        deleted = true
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Last updated \(PrivacyPolicy.lastUpdated)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(PrivacyPolicy.summary)
                    .font(.headline)
                ForEach(PrivacyPolicy.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title).font(.title3.weight(.semibold))
                        ForEach(section.body, id: \.self) { paragraph in
                            Text(paragraph)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("privacyPolicy")
    }
}

#Preview {
    NavigationStack { AboutView() }
        .environment(AppLock())
        .modelContainer(try! ModelContainer.journal(inMemory: true))
}
