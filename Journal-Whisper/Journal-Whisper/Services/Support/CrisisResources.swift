//
//  CrisisResources.swift
//  Journal-Whisper
//
//  Crisis helplines shown on the support screen.
//
//  Every number here was checked against an official or primary source on
//  9 November 2026. Re-check before each release: a wrong number on a crisis
//  screen is worse than none. Only add a number or website you've verified.
//
//  Sources:
//  - India, Tele-MANAS 14416 / 1-800-891-4416: Ministry of Health and Family
//    Welfare (pib.gov.in), free, 24/7, many languages.
//  - US, 988 Suicide & Crisis Lifeline (call or text): SAMHSA, 988lifeline.org.
//  - Canada, 9-8-8 Suicide Crisis Helpline (call or text): canada.ca, 988.ca.
//  - UK & Ireland, Samaritans 116 123 (calls only; text retired 2020): samaritans.org.
//  - Australia, Lifeline 13 11 14, text 0477 13 11 14: lifeline.org.au.
//  - Elsewhere: Find A Helpline (findahelpline.com), a verified directory by ThroughLine.
//

import Foundation

nonisolated struct Helpline: Identifiable, Sendable, Equatable {
    let name: String
    /// Who it's for and when, in a few words.
    let detail: String
    /// Digits to dial, and how to show them.
    let call: (dial: String, display: String)?
    /// Digits to text, and how to show them. Only where texting is supported.
    let text: (dial: String, display: String)?
    let website: URL?

    var id: String { name }

    static func == (a: Helpline, b: Helpline) -> Bool { a.name == b.name }
}

nonisolated struct RegionResources: Identifiable, Sendable {
    /// ISO 3166 region code.
    let region: String
    let emergency: (dial: String, display: String)
    let helplines: [Helpline]

    var id: String { region }

    var name: String {
        Locale.current.localizedString(forRegionCode: region) ?? region
    }
}

nonisolated enum CrisisResources {
    static let lastChecked = "9 November 2026"

    /// Directory of verified helplines in 130+ countries.
    static let directory = URL(string: "https://findahelpline.com")!

    static let regions: [RegionResources] = [
        RegionResources(region: "IN", emergency: ("112", "112"), helplines: [
            Helpline(name: "Tele-MANAS",
                     detail: String(localized: "Government mental health helpline. Free, 24/7, in many Indian languages."),
                     call: ("14416", "14416"), text: nil, website: nil),
            Helpline(name: "Tele-MANAS (toll-free)",
                     detail: String(localized: "The same service on its full toll-free number."),
                     call: ("18008914416", "1-800-891-4416"), text: nil, website: nil),
        ]),
        RegionResources(region: "US", emergency: ("911", "911"), helplines: [
            Helpline(name: "988 Suicide & Crisis Lifeline",
                     detail: String(localized: "Call or text. Free, confidential, 24/7."),
                     call: ("988", "988"), text: ("988", "988"),
                     website: URL(string: "https://988lifeline.org")),
        ]),
        RegionResources(region: "CA", emergency: ("911", "911"), helplines: [
            Helpline(name: "9-8-8 Suicide Crisis Helpline",
                     detail: String(localized: "Call or text, in English or French. 24/7."),
                     call: ("988", "9-8-8"), text: ("988", "9-8-8"),
                     website: URL(string: "https://988.ca")),
        ]),
        RegionResources(region: "GB", emergency: ("999", "999"), helplines: [
            Helpline(name: "Samaritans",
                     detail: String(localized: "Free from any phone, 24/7."),
                     call: ("116123", "116 123"), text: nil,
                     website: URL(string: "https://www.samaritans.org")),
        ]),
        RegionResources(region: "IE", emergency: ("112", "112"), helplines: [
            Helpline(name: "Samaritans",
                     detail: String(localized: "Free from any phone, 24/7."),
                     call: ("116123", "116 123"), text: nil,
                     website: URL(string: "https://www.samaritans.org")),
        ]),
        RegionResources(region: "AU", emergency: ("000", "000"), helplines: [
            Helpline(name: "Lifeline",
                     detail: String(localized: "Crisis support by phone or text, 24/7."),
                     call: ("131114", "13 11 14"), text: ("0477131114", "0477 13 11 14"),
                     website: URL(string: "https://www.lifeline.org.au")),
        ]),
    ]

    /// Resources for a region, or nil where we haven't verified any (show the directory instead).
    static func resources(for region: String?) -> RegionResources? {
        guard let region = region?.uppercased() else { return nil }
        return regions.first { $0.region == region }
    }

    static func callURL(_ digits: String) -> URL? { URL(string: "tel:\(digits)") }
    static func textURL(_ digits: String) -> URL? { URL(string: "sms:\(digits)") }
}
