//
//  ChatMentionTextStyling.swift
//  AppleIM
//

import UIKit

/// 消息内容展示样式
struct ChatMessageContentStyle {
    let textColor: UIColor
    let secondaryTextColor: UIColor
    let tintColor: UIColor
}

/// 聊天 @ 文本高亮工具，只处理展示属性，不改变原始发送文本。
enum ChatMentionTextStyling {
    static func attributedText(
        for text: String,
        baseColor: UIColor,
        mentionColor: UIColor = .systemBlue,
        font: UIFont
    ) -> NSAttributedString {
        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: [
                .foregroundColor: baseColor,
                .font: font
            ]
        )
        for range in mentionRanges(in: text) {
            attributedText.addAttribute(.foregroundColor, value: mentionColor, range: range)
        }
        return attributedText
    }

    static func mentionRanges(in text: String) -> [NSRange] {
        let pattern = "@[^\\s@，。！？、,.!?;:；：）)\\]】}]+"
        guard let regularExpression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        return regularExpression.matches(in: text, range: fullRange).map(\.range)
    }
}
