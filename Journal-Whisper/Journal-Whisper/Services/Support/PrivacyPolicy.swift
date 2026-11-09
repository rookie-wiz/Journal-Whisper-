//
//  PrivacyPolicy.swift
//  Journal-Whisper
//
//  The privacy policy, shown in the app and exported to PRIVACY.md (a unit
//  test keeps the two identical). Every statement here describes what the
//  code does; change them together.
//

import Foundation

nonisolated enum PrivacyPolicy {
    static let lastUpdated = "9 November 2026"

    /// Replace before publishing the policy.
    static let contact = "[your contact email]"

    struct Section: Identifiable, Sendable {
        let title: String
        let body: [String]
        var id: String { title }
    }

    static let summary = "Your journal stays on your iPhone. Journal Whisper has no accounts, no servers, no ads and no analytics, and it never sends what you write anywhere."

    static let sections: [Section] = [
        Section(title: "What the app stores", body: [
            "Your entries: their titles, text and the dates you wrote and edited them.",
            "Moods: the ones you choose, and the ones the app suggests, with a note of which is which.",
            "Weekly summaries and short one-line notes about entries that the app writes to build them.",
            "The milestone badges you've earned, and whether you've seen the welcome screens.",
            "All of this is kept in the app's private storage on your iPhone. It isn't synced to iCloud or any other service.",
        ]),
        Section(title: "On-device AI", body: [
            "Mood suggestions, reflection prompts and weekly summaries use Apple Intelligence's on-device language model. Your writing is processed on your iPhone and isn't sent to Apple or anyone else.",
            "If Apple Intelligence is off or not available, the app uses its own built-in offline features instead.",
            "Entries that mention self-harm, suicide, abuse or danger are never given to the AI model. The app shows support resources instead.",
        ]),
        Section(title: "Face ID and passcode", body: [
            "The journal is locked with Face ID, Touch ID or your device passcode, handled by iOS. The app only learns whether unlocking succeeded and never receives biometric data.",
            "Your journal is hidden in the app switcher and locks when the app goes to the background.",
        ]),
        Section(title: "Deleting your data", body: [
            "Deleted entries stay in Recently Deleted for 30 days, then are removed permanently. Deleting them sooner requires Face ID or your passcode.",
            "When an entry is deleted or edited, the summary of that week is deleted too, so it never describes something you removed. An entry's one-line note is deleted with the entry.",
            "You can delete all journal data, including badges, at any time from About & Privacy. Deleting the app removes everything it stored on your iPhone.",
        ]),
        Section(title: "Backups", body: [
            "Like other app data, your journal is included in your iPhone's backups (iCloud Backup or a backup on your computer) if you have backups turned on. Those backups are protected by Apple and by your computer's own security.",
        ]),
        Section(title: "What the app never does", body: [
            "It makes no network requests, contains no third-party code for analytics, advertising or tracking, and doesn't sell or share any data.",
            "Diagnostic messages the app writes to the device log record only the kind of problem (for example, \"timeout\"), never anything you wrote.",
        ]),
        Section(title: "Links you choose to open", body: [
            "On the Get Support screen, tapping a helpline number, text option or website opens Phone, Messages or Safari. Nothing is opened unless you tap it.",
        ]),
        Section(title: "Not a medical or crisis service", body: [
            "Journal Whisper is a private journal. It doesn't give medical advice, can't contact anyone for you, and doesn't monitor what you write. If you're in danger, contact your local emergency number.",
        ]),
        Section(title: "Changes and contact", body: [
            "If this policy changes, the new version will be in the app with a new date.",
            "Questions: \(contact)",
        ]),
    ]

    /// The policy as Markdown, for PRIVACY.md.
    static var markdown: String {
        var lines = [
            "# Journal Whisper Privacy Policy",
            "",
            "_Last updated: \(lastUpdated)_",
            "",
            summary,
        ]
        for section in sections {
            lines += ["", "## \(section.title)", ""]
            lines += section.body.map { "- \($0)" }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
