import Testing
@testable import PlaniniCore

struct LocalizationTests {
    @Test func matchesOverrideAndPreferredLocales() {
        let catalog = PlaniniLocalizationCatalog(
            catalogs: [
                "en": ["common": ["settings": "Settings"]],
                "de": ["common": ["settings": "Einstellungen"]],
            ]
        )

        #expect(catalog.availableLocales == ["de", "en"])
        #expect(catalog.effectiveLocale(preferredLocales: ["fr-FR", "de-DE"]) == "de")
        #expect(catalog.effectiveLocale(preferredLocales: ["de-DE"], overrideLocale: "en-US") == "en")
        #expect(catalog.effectiveLocale(preferredLocales: ["fr-FR"], overrideLocale: "fr") == "en")
    }

    @Test func translatesWithFallbackAndParameters() {
        let catalog = PlaniniLocalizationCatalog(
            catalogs: [
                "en": [
                    "ios": [
                        "item": [
                            "quantity": "Qty: {quantity}",
                            "nested": ["value": "Nested"],
                        ],
                    ],
                ],
                "de": [
                    "ios": [
                        "item": [
                            "quantity": "Menge: {quantity}",
                        ],
                    ],
                ],
            ]
        )

        #expect(
            catalog.translate(locale: "de-DE", key: "ios.item.quantity", params: ["quantity": "2"])
                == "Menge: 2"
        )
        #expect(catalog.translate(locale: "de", key: "ios.item.nested.value") == "Nested")
        #expect(catalog.translate(locale: "de", key: "ios.item.missing") == "ios.item.missing")
    }

    @Test func handlesEmptyAndMissingLocaleFallbacks() {
        let catalog = PlaniniLocalizationCatalog(
            defaultLocale: "fr",
            catalogs: [
                "en": ["common": ["settings": "Settings"]],
            ]
        )

        #expect(catalog.normalizedAvailableLocale("  ") == nil)
        #expect(catalog.effectiveLocale(preferredLocales: [], overrideLocale: nil) == "fr")
        #expect(catalog.translate(locale: "de", key: "common.settings") == "common.settings")
    }
}
