import Testing

@testable import AppleIM

extension AppleIMTests {
    @Test func featureModulesExposeServiceNames() {
        _ = ConversationListService.self
        _ = LocalConversationListService.self
        _ = ContactListService.self
        _ = LocalContactListService.self
        _ = SearchService.self
        _ = LocalSearchService.self
    }
}
