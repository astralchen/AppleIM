import Foundation
import Testing
import UIKit

@testable import AppleIM

@MainActor
extension AppleIMTests {
    @Test func appLanguagePreferenceDefaultsToSystemAndResolvesPreferredLanguage() throws {
        let suiteName = "AppleIMTests.Localization.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let manager = AppLanguageManager(
            userDefaults: userDefaults,
            preferredLanguagesProvider: { ["ar-SA", "en-US"] }
        )

        #expect(manager.preference == .system)
        #expect(manager.resolvedLanguage == .arabic)
        #expect(manager.currentLayoutDirection == .forceRightToLeft)
    }

    @Test func appLanguageManagerPersistsManualPreferenceAheadOfSystemLanguage() throws {
        let suiteName = "AppleIMTests.Localization.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let firstManager = AppLanguageManager(
            userDefaults: userDefaults,
            preferredLanguagesProvider: { ["ar-SA"] }
        )

        firstManager.setPreference(.language(.english))
        let secondManager = AppLanguageManager(
            userDefaults: userDefaults,
            preferredLanguagesProvider: { ["ar-SA"] }
        )

        #expect(secondManager.preference == .language(.english))
        #expect(secondManager.resolvedLanguage == .english)
        #expect(secondManager.currentLayoutDirection == .forceLeftToRight)
    }

    @Test func appLanguageManagerInfersChineseScriptAndFallsBackToSimplifiedChinese() throws {
        #expect(AppLanguage.resolveSystemLanguage(from: ["zh-HK"]) == .traditionalChinese)
        #expect(AppLanguage.resolveSystemLanguage(from: ["zh-TW"]) == .traditionalChinese)
        #expect(AppLanguage.resolveSystemLanguage(from: ["zh-CN"]) == .simplifiedChinese)
        #expect(AppLanguage.resolveSystemLanguage(from: ["fr-FR"]) == .simplifiedChinese)
    }

    @Test func localizableStringCatalogContainsCompleteSupportedLanguageSet() throws {
        let catalog = try LocalizableCatalogLoader.loadSourceCatalog(named: "Localizable")

        try catalog.assertCompleteTranslations(
            languages: AppLanguage.allCases.map(\.identifier),
            requiredKeys: [
                "app.name",
                "language.option.system",
                "language.section.iphoneLanguages",
                "language.title.select",
                "language.search.placeholder",
                "language.subtitle.english",
                "account.action.language",
                "login.submit",
                "conversation.title",
                "chat.input.placeholder"
            ]
        )
    }

    @Test func infoPlistStringCatalogContainsAppNameAndPermissionUsageDescriptions() throws {
        let catalog = try LocalizableCatalogLoader.loadSourceCatalog(named: "InfoPlist")

        try catalog.assertCompleteTranslations(
            languages: AppLanguage.allCases.map(\.identifier),
            requiredKeys: [
                "CFBundleDisplayName",
                "CFBundleName",
                "NSMicrophoneUsageDescription",
                "NSPhotoLibraryUsageDescription"
            ]
        )
    }

    @Test func l10nReadsCurrentLanguageAndFallsBackToBaseLanguageForMissingKeys() throws {
        let manager = AppLanguageManager(
            userDefaults: UserDefaults(suiteName: "AppleIMTests.Localization.\(UUID().uuidString)") ?? .standard,
            preferredLanguagesProvider: { ["ar-SA"] }
        )
        let l10n = L10n(languageManager: manager)

        #expect(l10n.tr("language.option.arabic") == "العربية")
        #expect(l10n.tr("missing.localization.key") == "missing.localization.key")
    }
}
