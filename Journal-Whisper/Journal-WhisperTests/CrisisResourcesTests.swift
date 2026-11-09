//
//  CrisisResourcesTests.swift
//  Journal-WhisperTests
//
//  Pins the verified crisis numbers, so an accidental edit fails loudly.
//  If a number genuinely changes, re-verify it at the source, then update
//  both CrisisResources.swift (with its lastChecked date) and this test.
//

import Foundation
import Testing
@testable import Journal_Whisper

struct CrisisResourcesTests {

    private func calls(_ region: String) -> [String] {
        CrisisResources.resources(for: region)?.helplines.compactMap(\.call?.dial) ?? []
    }

    @Test func verifiedNumbers() {
        #expect(calls("IN") == ["14416", "18008914416"])
        #expect(calls("US") == ["988"])
        #expect(calls("CA") == ["988"])
        #expect(calls("GB") == ["116123"])
        #expect(calls("IE") == ["116123"])
        #expect(calls("AU") == ["131114"])
    }

    @Test func emergencyNumbers() {
        let expected = ["IN": "112", "US": "911", "CA": "911", "GB": "999", "IE": "112", "AU": "000"]
        for (region, number) in expected {
            #expect(CrisisResources.resources(for: region)?.emergency.dial == number, "\(region)")
        }
    }

    @Test func textingOnlyWhereSupported() {
        // Samaritans retired texting in 2020; Tele-MANAS is calls only.
        for region in ["GB", "IE", "IN"] {
            #expect(CrisisResources.resources(for: region)?.helplines.allSatisfy { $0.text == nil } == true, "\(region)")
        }
        #expect(CrisisResources.resources(for: "US")?.helplines.first?.text?.dial == "988")
        #expect(CrisisResources.resources(for: "AU")?.helplines.first?.text?.dial == "0477131114")
    }

    @Test func everyRegionIsUsable() {
        for resources in CrisisResources.regions {
            #expect(!resources.helplines.isEmpty, "\(resources.region)")
            #expect(CrisisResources.callURL(resources.emergency.dial) != nil)
            for helpline in resources.helplines {
                #expect(helpline.call != nil, "\(helpline.name) needs a number to call")
                for dial in [helpline.call?.dial, helpline.text?.dial].compactMap({ $0 }) {
                    let digitsOnly = dial.allSatisfy { $0.isNumber }
                    #expect(digitsOnly, "\(dial) must be digits only")
                    #expect(CrisisResources.callURL(dial)?.absoluteString == "tel:\(dial)")
                }
                if let website = helpline.website {
                    #expect(website.scheme == "https", "\(website)")
                }
            }
        }
        #expect(Set(CrisisResources.regions.map(\.region)).count == CrisisResources.regions.count)
    }

    @Test func regionLookup() {
        #expect(CrisisResources.resources(for: "in")?.region == "IN")
        #expect(CrisisResources.resources(for: "FR") == nil, "Unverified regions show the directory instead")
        #expect(CrisisResources.resources(for: nil) == nil)
        #expect(CrisisResources.directory.absoluteString == "https://findahelpline.com")
    }
}
