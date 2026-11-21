//
//  TagPillLabel.swift
//  Caroullage
//
//  The small "NEW" pill a fresh template wears over its artwork's top-leading
//  corner. Ink on any photograph — the same `accentStrong` / `textOnAccent`
//  pair as the lock badge it sits opposite, so the two read as one family of
//  marks rather than two styles of sticker.
//
//  Fixed-size type on purpose: it is a badge over artwork, not reading text,
//  and a pill that grew with Dynamic Type would cover the picture it labels.
//  VoiceOver gets the word through the card's accessibility value instead.
//

import UIKit

final class TagPillLabel: UILabel {

    private static let insets = UIEdgeInsets(top: 3, left: 7, bottom: 3, right: 7)

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = Theme.Typography.roundedFixed(10, .heavy)
        textColor = Theme.Color.textOnAccent
        backgroundColor = Theme.Color.accentStrong
        textAlignment = .center
        layer.cornerRadius = 9
        layer.cornerCurve = .continuous
        clipsToBounds = true
        isAccessibilityElement = false
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Sets the pill's word; nil or empty hides it.
    func setTitle(_ title: String?) {
        guard let title, !title.isEmpty else {
            attributedText = nil
            isHidden = true
            return
        }
        isHidden = false
        // Tracked capitals read as a label; the same word in sentence case
        // reads as a caption that wandered onto the photo.
        attributedText = NSAttributedString(
            string: title.uppercased(with: .current),
            attributes: [.kern: 0.8, .font: font as Any, .foregroundColor: textColor as Any])
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: Self.insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        guard size.width > 0 else { return .zero }
        return CGSize(width: size.width + Self.insets.left + Self.insets.right,
                      height: size.height + Self.insets.top + Self.insets.bottom)
    }
}
