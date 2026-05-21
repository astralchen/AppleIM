//
//  AppLanguage.swift
//  AppleIM
//
//  应用内语言与本地化读取
//

import Foundation
import UIKit

/// 应用当前支持的实际显示语言。
nonisolated enum AppLanguage: String, CaseIterable, Codable, Equatable, Sendable {
    /// 简体中文
    case simplifiedChinese = "zh-Hans"
    /// 繁体中文
    case traditionalChinese = "zh-Hant"
    /// 英文
    case english = "en"
    /// 阿拉伯文
    case arabic = "ar"

    /// String Catalog 使用的语言标识。
    var identifier: String { rawValue }

    /// Locale 使用的标识。
    var localeIdentifier: String { rawValue }

    /// 语言显示名本地化 key。
    var displayNameKey: String {
        switch self {
        case .simplifiedChinese:
            return "language.option.simplifiedChinese"
        case .traditionalChinese:
            return "language.option.traditionalChinese"
        case .english:
            return "language.option.english"
        case .arabic:
            return "language.option.arabic"
        }
    }

    /// 是否需要从右到左布局。
    var isRightToLeft: Bool {
        self == .arabic
    }

    /// UI 语义方向。
    var semanticContentAttribute: UISemanticContentAttribute {
        isRightToLeft ? .forceRightToLeft : .forceLeftToRight
    }

    /// 按系统首选语言列表解析当前支持的语言。
    nonisolated static func resolveSystemLanguage(from preferredLanguages: [String]) -> AppLanguage {
        for preferredLanguage in preferredLanguages {
            if let language = resolveSystemLanguage(from: preferredLanguage) {
                return language
            }
        }

        return .simplifiedChinese
    }

    /// 解析单个系统语言标识，支持 `zh` 无脚本时按地区推断繁简。
    nonisolated private static func resolveSystemLanguage(from preferredLanguage: String) -> AppLanguage? {
        let normalized = preferredLanguage.replacingOccurrences(of: "_", with: "-")
        let lowercased = normalized.lowercased()

        if lowercased.hasPrefix("zh-hant") {
            return .traditionalChinese
        }

        if lowercased.hasPrefix("zh-hans") {
            return .simplifiedChinese
        }

        if lowercased == "zh" || lowercased.hasPrefix("zh-") {
            let traditionalRegions = ["hk", "mo", "tw"]
            let parts = lowercased.split(separator: "-").map(String.init)
            if parts.contains(where: traditionalRegions.contains) {
                return .traditionalChinese
            }
            return .simplifiedChinese
        }

        if lowercased.hasPrefix("en") {
            return .english
        }

        if lowercased.hasPrefix("ar") {
            return .arabic
        }

        return nil
    }
}

/// 应用内语言偏好。
nonisolated enum AppLanguagePreference: Equatable, Sendable {
    /// 跟随系统语言。
    case system
    /// 使用用户手动选择的语言。
    case language(AppLanguage)

    /// 持久化字符串。
    var storageValue: String {
        switch self {
        case .system:
            return "system"
        case .language(let language):
            return language.identifier
        }
    }

    /// 从持久化字符串恢复偏好。
    init(storageValue: String?) {
        guard let storageValue, storageValue != "system" else {
            self = .system
            return
        }

        if let language = AppLanguage(rawValue: storageValue) {
            self = .language(language)
        } else {
            self = .system
        }
    }
}

/// 语言变更上下文，页面用它刷新方向和文案。
@MainActor
struct AppLanguageContext {
    let preference: AppLanguagePreference
    let resolvedLanguage: AppLanguage
    let semanticContentAttribute: UISemanticContentAttribute
}

/// `NotificationCenter` 返回的观察 token 本身来自 Objective-C，未标注 Sendable。
///
/// token 只在主 actor 隔离的语言管理器内创建、移除和释放，不跨线程共享。
nonisolated private struct NotificationObservationToken: @unchecked Sendable {
    let value: NSObjectProtocol
}

/// 可响应应用内语言切换的 UI 对象。
@MainActor
protocol AppLanguageUpdatable: AnyObject {
    /// 语言变化后刷新用户可见文案、方向和布局。
    func applyLanguageChange(_ context: AppLanguageContext)
}

/// 应用内语言管理器。
@MainActor
final class AppLanguageManager {
    static let shared = AppLanguageManager()

    static let didChangeNotification = Notification.Name("AppLanguageManager.didChangeNotification")

    private let storageKey = "chatbridge.appLanguagePreference"
    private let userDefaults: UserDefaults
    private let preferredLanguagesProvider: () -> [String]
    private let notificationCenter: NotificationCenter
    private var localeObservation: NotificationObservationToken?
    private(set) var resolvedLanguage: AppLanguage

    var preference: AppLanguagePreference {
        didSet {
            guard oldValue != preference else { return }
            userDefaults.set(preference.storageValue, forKey: storageKey)
            resolvedLanguage = Self.resolve(preference: preference, preferredLanguages: preferredLanguagesProvider())
            postLanguageChangeNotification()
        }
    }

    var currentLocale: Locale {
        Locale(identifier: resolvedLanguage.localeIdentifier)
    }

    var currentLayoutDirection: UISemanticContentAttribute {
        resolvedLanguage.semanticContentAttribute
    }

    var currentContext: AppLanguageContext {
        AppLanguageContext(
            preference: preference,
            resolvedLanguage: resolvedLanguage,
            semanticContentAttribute: currentLayoutDirection
        )
    }

    init(
        userDefaults: UserDefaults = .standard,
        preferredLanguagesProvider: @escaping () -> [String] = { Locale.preferredLanguages },
        notificationCenter: NotificationCenter = .default
    ) {
        self.userDefaults = userDefaults
        self.preferredLanguagesProvider = preferredLanguagesProvider
        self.notificationCenter = notificationCenter
        let preference = AppLanguagePreference(storageValue: userDefaults.string(forKey: storageKey))
        self.preference = preference
        self.resolvedLanguage = Self.resolve(preference: preference, preferredLanguages: preferredLanguagesProvider())
        observeSystemLocaleChanges()
    }

    deinit {
        if let localeObservation {
            notificationCenter.removeObserver(localeObservation.value)
        }
    }

    func setPreference(_ preference: AppLanguagePreference) {
        self.preference = preference
    }

    /// UI 测试需要隔离上一次运行留下的语言偏好，避免跨用例污染。
    func resetPreferenceForUITesting() {
        userDefaults.removeObject(forKey: storageKey)
        preference = .system
        resolvedLanguage = Self.resolve(preference: preference, preferredLanguages: preferredLanguagesProvider())
    }

    /// 仅在跟随系统时重新解析系统语言；解析结果变化才通知 UI 刷新。
    @discardableResult
    func refreshSystemLanguageIfNeeded() -> Bool {
        guard preference == .system else { return false }
        let nextLanguage = Self.resolve(preference: preference, preferredLanguages: preferredLanguagesProvider())
        guard nextLanguage != resolvedLanguage else { return false }
        resolvedLanguage = nextLanguage
        postLanguageChangeNotification()
        return true
    }

    private static func resolve(preference: AppLanguagePreference, preferredLanguages: [String]) -> AppLanguage {
        switch preference {
        case .system:
            return AppLanguage.resolveSystemLanguage(from: preferredLanguages)
        case .language(let language):
            return language
        }
    }

    private func postLanguageChangeNotification() {
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: self,
            userInfo: ["context": currentContext]
        )
    }

    private func observeSystemLocaleChanges() {
        localeObservation = NotificationObservationToken(
            value: notificationCenter.addObserver(
                forName: NSLocale.currentLocaleDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshSystemLanguageIfNeeded()
                }
            }
        )
    }
}

/// 本地化字符串读取入口。
nonisolated struct L10nKey: RawRepresentable, ExpressibleByStringLiteral, Hashable, Sendable {
    let rawValue: String

    nonisolated init(rawValue: String) {
        self.rawValue = rawValue
    }

    nonisolated init(stringLiteral value: String) {
        self.rawValue = value
    }
}

/// 本地化字符串读取入口。
@MainActor
final class L10n {
    static let shared = L10n(languageManager: .shared)

    private let languageManager: AppLanguageManager
    private let tableName: String
    private let bundle: Bundle

    init(languageManager: AppLanguageManager, tableName: String = "Localizable", bundle: Bundle = .main) {
        self.languageManager = languageManager
        self.tableName = tableName
        self.bundle = bundle
    }

    func tr(_ key: L10nKey, _ arguments: CVarArg...) -> String {
        localizedString(for: key.rawValue, arguments: arguments)
    }

    func tr(_ key: String, _ arguments: CVarArg...) -> String {
        localizedString(for: key, arguments: arguments)
    }

    private func localizedString(for key: String, arguments: [CVarArg]) -> String {
        let template = localizedTemplate(for: key, language: languageManager.resolvedLanguage)
        guard !arguments.isEmpty else {
            return template
        }

        return String(format: template, locale: languageManager.currentLocale, arguments: arguments)
    }

    private func localizedTemplate(for key: String, language: AppLanguage) -> String {
        if let value = bundleLocalizedString(forKey: key, language: language) {
            return value
        }

        if let fallback = bundleLocalizedString(forKey: key, language: .simplifiedChinese) {
            AppLogger(category: .app).error("Missing localization key=\(key) language=\(language.identifier)")
            return fallback
        }

        AppLogger(category: .app).error("Missing localization key=\(key) language=\(language.identifier) fallback=key")
        return key
    }

    private func bundleLocalizedString(forKey key: String, language: AppLanguage) -> String? {
        guard
            let lprojPath = bundle.path(forResource: language.identifier, ofType: "lproj"),
            let languageBundle = Bundle(path: lprojPath)
        else {
            return nil
        }

        let value = languageBundle.localizedString(forKey: key, value: nil, table: tableName)
        return value == key ? nil : value
    }
}

/// 读取并校验 Xcode String Catalog。
nonisolated struct LocalizableCatalogLoader {
    nonisolated static func loadSourceCatalog(named name: String) throws -> LocalizableStringCatalog {
        let fileName = "\(name).xcstrings"
        let sourceResourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent(fileName)
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: "xcstrings"),
            Bundle(identifier: "com.sondra.AppleIM")?.url(forResource: name, withExtension: "xcstrings"),
            sourceResourceURL,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("AppleIM/Resources")
                .appendingPathComponent(fileName),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("AppleIM")
                .appendingPathComponent(fileName)
        ].compactMap { $0 }

        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw LocalizableStringCatalogError.catalogNotFound(fileName)
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LocalizableStringCatalog.self, from: data)
    }
}

/// String Catalog 最小解码模型。
nonisolated struct LocalizableStringCatalog: Decodable, Sendable {
    let strings: [String: Entry]

    nonisolated func localizedString(forKey key: String, language: String) -> String? {
        strings[key]?.localizations[language]?.stringUnit.value.nilIfEmpty
    }

    nonisolated func assertCompleteTranslations(languages: [String], requiredKeys: [String]) throws {
        for key in requiredKeys {
            guard strings[key] != nil else {
                throw LocalizableStringCatalogError.missingKey(key)
            }
        }

        for (key, entry) in strings {
            for language in languages {
                guard let value = entry.localizations[language]?.stringUnit.value.nilIfEmpty else {
                    throw LocalizableStringCatalogError.missingTranslation(key: key, language: language)
                }

                let baseValue = entry.localizations[AppLanguage.simplifiedChinese.identifier]?.stringUnit.value ?? ""
                guard Self.placeholderTokens(in: value) == Self.placeholderTokens(in: baseValue) else {
                    throw LocalizableStringCatalogError.placeholderMismatch(key: key, language: language)
                }
            }
        }
    }

    nonisolated private static func placeholderTokens(in value: String) -> [String] {
        let pattern = "%(?:\\d+\\$)?[@dDfFuUxXoOeEgGcCsSpaAi]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            Range(match.range, in: value).map { String(value[$0]) }
        }
    }

    nonisolated struct Entry: Decodable, Sendable {
        let localizations: [String: Localization]
    }

    nonisolated struct Localization: Decodable, Sendable {
        let stringUnit: StringUnit
    }

    nonisolated struct StringUnit: Decodable, Sendable {
        let value: String
    }
}

nonisolated enum LocalizableStringCatalogError: Error, Equatable, CustomStringConvertible, Sendable {
    case catalogNotFound(String)
    case missingKey(String)
    case missingTranslation(key: String, language: String)
    case placeholderMismatch(key: String, language: String)

    var description: String {
        switch self {
        case .catalogNotFound(let name):
            return "未找到 String Catalog：\(name)"
        case .missingKey(let key):
            return "缺少本地化 key：\(key)"
        case .missingTranslation(let key, let language):
            return "缺少本地化翻译：\(key) / \(language)"
        case .placeholderMismatch(let key, let language):
            return "本地化占位符不一致：\(key) / \(language)"
        }
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
