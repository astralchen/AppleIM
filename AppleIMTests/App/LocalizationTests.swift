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
                "chat.input.placeholder",
                "chat.media.imageUnavailable",
                "chat.media.videoUnavailable",
                "chat.media.image.accessibility",
                "chat.media.playVideo.accessibility",
                "chat.voice.play.accessibility",
                "chat.voice.stop.accessibility",
                "chat.voicePreview.play.accessibility",
                "chat.voicePreview.pause.accessibility",
                "chat.voicePreview.send.accessibility",
                "chat.voiceRecording.stop.accessibility",
                "chat.attachment.remove.accessibility",
                "chat.upload.progress.accessibility",
                "chat.photoLibrary.photo.accessibility",
                "chat.photoLibrary.video.accessibility",
                "chat.photoLibrary.selected.accessibility",
                "chat.emoji.empty",
                "chat.emoji.recent",
                "chat.emoji.favorites",
                "chat.mention.search.placeholder",
                "chat.mention.title",
                "chat.mention.dismiss.accessibility",
                "chat.mention.multiSelect",
                "chat.mention.done",
                "chat.mention.all",
                "chat.mention.all.subtitle",
                "chat.mention.nicknameFormat",
                "chat.mention.selected",
                "chat.mention.notSelected",
                "chat.mention.jumpToSection.accessibility",
                "chat.groupAnnouncement.inlineFormat"
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

    @Test func appLanguageManagerRefreshesSystemPreferenceWhenLocaleNotificationArrives() async throws {
        let suiteName = "AppleIMTests.Localization.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        let notificationCenter = NotificationCenter()
        var preferredLanguages = ["en-US"]
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let manager = AppLanguageManager(
            userDefaults: userDefaults,
            preferredLanguagesProvider: { preferredLanguages },
            notificationCenter: notificationCenter
        )

        #expect(manager.preference == .system)
        #expect(manager.resolvedLanguage == .english)

        preferredLanguages = ["ar-SA"]
        notificationCenter.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)

        try await waitForCondition {
            manager.resolvedLanguage == .arabic
                && manager.currentLayoutDirection == .forceRightToLeft
        }
    }
}
