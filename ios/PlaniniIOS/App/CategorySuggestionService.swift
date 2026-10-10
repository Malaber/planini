import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import PlaniniCore

struct CategorySuggestionService {
    enum SuggestionError: Error {
        case unavailable
        case invalidResponse
    }

    private static let availabilityOverrideKey = "PLANINI_UI_TEST_APPLE_INTELLIGENCE_AVAILABLE"
    private static let categoryOverrideKey = "PLANINI_UI_TEST_CATEGORY_SUGGESTION"
    private static let expectedNameKey = "PLANINI_UI_TEST_CATEGORY_SUGGESTION_EXPECTED_NAME"
    private static let expectedQuantityKey = "PLANINI_UI_TEST_CATEGORY_SUGGESTION_EXPECTED_QUANTITY"
    private static let expectedNoteKey = "PLANINI_UI_TEST_CATEGORY_SUGGESTION_EXPECTED_NOTE"

    private let availability: () -> Bool
    private let suggestion: (
        GroceryCategorySuggestionRequest,
        [GroceryCategorySummary]
    ) async throws -> UUID

    var isAvailable: Bool {
        availability()
    }

    func suggestCategory(
        request: GroceryCategorySuggestionRequest,
        categories: [GroceryCategorySummary]
    ) async throws -> UUID {
        try await suggestion(request, categories)
    }

    static func live(processInfo: ProcessInfo = .processInfo) -> CategorySuggestionService {
        let environment = processInfo.environment
        if environment["PLANINI_UI_TEST_MODE"] == "1",
            environment[availabilityOverrideKey] == "0"
        {
            return CategorySuggestionService(
                availability: { false },
                suggestion: { _, _ in throw SuggestionError.unavailable }
            )
        }
        if environment["PLANINI_UI_TEST_MODE"] == "1",
            environment[availabilityOverrideKey] == "1",
            let categoryName = environment[categoryOverrideKey]
        {
            let expectedRequest = GroceryCategorySuggestionRequest(
                name: environment[expectedNameKey] ?? "",
                quantity: environment[expectedQuantityKey] ?? "",
                note: environment[expectedNoteKey] ?? ""
            )
            return CategorySuggestionService(
                availability: { true },
                suggestion: { request, categories in
                    guard request == expectedRequest,
                          let categoryID = categories.first(where: {
                              $0.name.caseInsensitiveCompare(categoryName) == .orderedSame
                          })?.id
                    else {
                        throw SuggestionError.invalidResponse
                    }
                    return categoryID
                }
            )
        }

        return CategorySuggestionService(
            availability: { foundationModelIsAvailable },
            suggestion: { request, categories in
                #if canImport(FoundationModels)
                if #available(iOS 26.0, *) {
                    return try await suggestWithFoundationModels(
                        request: request,
                        categories: categories
                    )
                }
                #endif
                throw SuggestionError.unavailable
            }
        )
    }

    private static var foundationModelIsAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func suggestWithFoundationModels(
        request: GroceryCategorySuggestionRequest,
        categories: [GroceryCategorySummary]
    ) async throws -> UUID {
        guard foundationModelIsAvailable, categories.isEmpty == false else {
            throw SuggestionError.unavailable
        }

        let categoryIdentifiers = categories.map { $0.id.uuidString }
        let responseSchema = GenerationSchema(
            type: String.self,
            description: "Identifier of the single best matching grocery-list category.",
            anyOf: categoryIdentifiers
        )
        let session = LanguageModelSession {
            "Select exactly one category identifier from the supplied choices."
        }
        let response = try await session.respond(
            to: GroceryCategorySuggestionPrompt.make(request: request, categories: categories),
            schema: responseSchema
        )
        let generatedIdentifier = try response.content.value(String.self)
        guard let categoryID = GroceryCategorySuggestionResolver.categoryID(
            for: generatedIdentifier,
            categories: categories
        ) else {
            throw SuggestionError.invalidResponse
        }
        return categoryID
    }
    #endif
}
