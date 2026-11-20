//
//  HomeCardCell.swift
//  Caroullage
//
//  The card every Home strip below the hero is built from (2026-11-20 redesign).
//
//  The hero learned to present each kind of work the way it is used — video
//  plays, a carousel deals out as a deck, tall work stands as a story. The
//  strips under it did not: every one was the same 160 x 200 crop with its name
//  printed on a dark scrim, so six strips read as one wall, a 1:1 grid lost its
//  top and bottom to a 4:5 crop, and a carousel arrived as three small pages on
//  a grey blur of themselves.
//
//  This card carries the hero's idea down the page. Each `HomeCardStyle` is a
//  native shape for one kind of work, and every style shares one caption
//  system — name and a one-line fact BELOW the artwork, on the app surface,
//  the way the Collage gallery's `BrowseTemplateCell` already does it. No
//  scrims: nothing is printed over a photograph any more.
//
//  Motion stays where it was. Only a reel moves (the same gated loop the old
//  video card ran); posters, stories and decks are still, so the hero remains
//  the one thing on the screen that performs.
//

import UIKit

/// How a Home card presents its artwork. Chosen per collection — see
/// `HomeCollection.cardStyle`.
enum HomeCardStyle: String, Sendable, CaseIterable {
    /// A collage shown WHOLE, aspect-fitted and mounted on a mat tinted from
    /// its own colour: a print in a frame. Nothing is cropped.
    case poster
    /// The poster, larger — for the collection that leads (the season).
    case feature
    /// Full-bleed 9:16 with story progress segments: tall work as a story.
    case story
    /// Full-bleed 9:16 looping video.
    case reel
    /// A carousel's first slide in front, the next two stacked behind it.
    case deck

    /// The artwork's size. The caption block is added below it.
    var artworkSize: CGSize {
        switch self {
        case .poster: return CGSize(width: 156, height: 195)
        case .feature: return CGSize(width: 212, height: 265)
        case .story, .reel: return CGSize(width: 132, height: 235)
        case .deck: return CGSize(width: 204, height: 195)
        }
    }

    /// Room for the name and the meta line under the artwork, scaled with
    /// Dynamic Type so a larger text size grows the strip instead of clipping.
    @MainActor static var captionHeight: CGFloat {
        let name = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 20)
        let meta = UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 17)
        return HomeCardCell.captionGap + name + 1 + meta
    }

    @MainActor var cellSize: CGSize {
        CGSize(width: artworkSize.width, height: artworkSize.height + Self.captionHeight)
    }
}

@MainActor
final class HomeCardCell: UICollectionViewCell {
    static let reuseID = "HomeCardCell"

    /// Between the artwork and the name.
    fileprivate static let captionGap: CGFloat = 8
    private static let badgeSide: CGFloat = 24
    /// The mat's margin around a mounted poster.
    private static let matInset: CGFloat = 12

    /// What fills the artwork.
    enum Artwork {
        /// One rendered still (a collage). Rendered lazily, off the scroll.
        case still(() async -> CGImage?)
        /// A carousel's slides, in order.
        case slides(() async -> [CGImage])
        /// A looping video with its poster.
        case video(poster: UIImage?, loop: URL?)
    }

    struct Content {
        var name: String
        var meta: String
        var identifier: String
        var style: HomeCardStyle
        var artwork: Artwork
        var locked = false
        var saved = false
        /// Page count, spoken for a carousel.
        var pages: Int?
    }

    // The artwork is a shadowed holder around a clipped, rounded mat; the
    // shadow would be cut off by the mat's own clip.
    private let artworkHolder = UIView()
    private let mat = UIView()
    /// Poster/feature: the mounted print. Story: the full-bleed frame.
    private let printView = UIView()
    private let imageView = UIImageView()
    private let playerView = LoopingPreviewPlayerView()
    private let storyChrome = HeroStoryChromeView()
    /// Deck: front card first, then the two behind it.
    private var slideCards: [UIView] = []
    private var slideImages: [UIImageView] = []
    private var slideShades: [UIView] = []
    private let counter = HomeCardCapsule()

    private let lockBadge = UIImageView()
    private let savedBadge = UIImageView()
    private let playBadge = UIImageView()
    private let nameLabel = UILabel()
    private let metaLabel = UILabel()

    private var style: HomeCardStyle = .poster
    private var artworkAspect: CGFloat = 0.8
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)

        artworkHolder.layer.shadowColor = UIColor.black.cgColor
        artworkHolder.layer.shadowOpacity = 0.10
        artworkHolder.layer.shadowRadius = 10
        artworkHolder.layer.shadowOffset = CGSize(width: 0, height: 4)

        mat.backgroundColor = Theme.Color.artworkMat
        mat.layer.cornerRadius = Theme.Radius.lg
        mat.layer.cornerCurve = .continuous
        mat.clipsToBounds = true

        // The mounted print: a hairline shadow so it sits ON the mat.
        printView.layer.shadowColor = UIColor.black.cgColor
        printView.layer.shadowOpacity = 0.18
        printView.layer.shadowRadius = 6
        printView.layer.shadowOffset = CGSize(width: 0, height: 3)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerCurve = .continuous

        for index in 0..<3 {
            let card = UIView()
            card.layer.shadowColor = UIColor.black.cgColor
            card.layer.shadowOpacity = index == 0 ? 0.22 : 0.14
            card.layer.shadowRadius = 8
            card.layer.shadowOffset = CGSize(width: 0, height: 4)
            let image = UIImageView()
            image.contentMode = .scaleAspectFill
            image.clipsToBounds = true
            image.layer.cornerRadius = 6
            image.layer.cornerCurve = .continuous
            image.backgroundColor = Theme.Color.artworkMatDeep
            card.addSubview(image)
            let shade = UIView()
            shade.backgroundColor = .black
            shade.alpha = index == 0 ? 0 : 0.12 * CGFloat(index)
            image.addSubview(shade)
            slideCards.append(card)
            slideImages.append(image)
            slideShades.append(shade)
        }

        // The segments are white; a soft shadow keeps them legible on the
        // white grounds several story templates have.
        storyChrome.layer.shadowColor = UIColor.black.cgColor
        storyChrome.layer.shadowOpacity = 0.35
        storyChrome.layer.shadowRadius = 2
        storyChrome.layer.shadowOffset = .zero

        counter.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        counter.textColor = Theme.Color.textOnToast
        counter.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        counter.clipsToBounds = true

        configureBadge(lockBadge, symbol: "lock.fill",
                       tint: Theme.Color.textOnAccent, background: Theme.Color.accentStrong)
        configureBadge(savedBadge, symbol: "heart.fill",
                       tint: Theme.Color.textOnToast,
                       background: Theme.Color.toast.withAlphaComponent(0.55))
        configureBadge(playBadge, symbol: "play.fill",
                       tint: Theme.Color.textOnToast,
                       background: Theme.Color.toast.withAlphaComponent(0.45))

        nameLabel.font = Theme.Typography.rounded(15, .semibold, .subheadline)
        nameLabel.textColor = Theme.Color.textPrimary
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.lineBreakMode = .byTruncatingTail

        metaLabel.font = Theme.Typography.caption
        metaLabel.textColor = Theme.Color.textSecondary
        metaLabel.adjustsFontForContentSizeCategory = true
        metaLabel.lineBreakMode = .byTruncatingTail

        contentView.addSubview(artworkHolder)
        artworkHolder.addSubview(mat)
        mat.addSubview(printView)
        printView.addSubview(imageView)
        mat.addSubview(playerView)
        for card in slideCards.reversed() { mat.addSubview(card) }
        mat.addSubview(counter)
        mat.addSubview(storyChrome)
        mat.addSubview(lockBadge)
        mat.addSubview(savedBadge)
        mat.addSubview(playBadge)
        contentView.addSubview(nameLabel)
        contentView.addSubview(metaLabel)

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func configureBadge(_ badge: UIImageView, symbol: String, tint: UIColor, background: UIColor) {
        badge.contentMode = .center
        badge.tintColor = tint
        badge.backgroundColor = background
        badge.layer.cornerRadius = Self.badgeSide / 2
        badge.layer.cornerCurve = .continuous
        badge.clipsToBounds = true
        badge.isHidden = true
        badge.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            setPressed(isHighlighted, scale: 0.96)
        }
    }

    // MARK: Configure

    func configure(_ content: Content) {
        style = content.style
        nameLabel.text = content.name
        metaLabel.text = content.meta
        lockBadge.isHidden = !content.locked
        savedBadge.isHidden = !content.saved

        accessibilityIdentifier = content.identifier
        accessibilityLabel = content.name
        var spoken = [content.meta]
        if let pages = content.pages, pages >= 2 { spoken.append(String(localized: "\(pages) pages")) }
        if content.saved { spoken.append(String(localized: "saved")) }
        accessibilityValue = spoken.filter { !$0.isEmpty }.joined(separator: ", ")

        let isDeck = style == .deck
        let isVideo: Bool
        if case .video = content.artwork { isVideo = true } else { isVideo = false }
        printView.isHidden = isDeck || isVideo
        playerView.isHidden = !isVideo
        playBadge.isHidden = !isVideo
        slideCards.forEach { $0.isHidden = !isDeck }
        counter.isHidden = true
        storyChrome.isHidden = style != .story
        storyChrome.stop()
        mat.backgroundColor = Theme.Color.artworkMat
        // A mounted print gets a small radius; a full-bleed frame IS the card.
        imageView.layer.cornerRadius = mounts ? 4 : 0
        printView.layer.shadowOpacity = mounts ? 0.18 : 0

        loadTask?.cancel()
        loadTask = nil
        switch content.artwork {
        case let .still(render):
            loadTask = Task { @MainActor [weak self] in
                let image = await render()
                guard !Task.isCancelled, let self else { return }
                self.show(still: image)
            }
        case let .slides(render):
            loadTask = Task { @MainActor [weak self] in
                let slides = await render()
                guard !Task.isCancelled, let self else { return }
                self.show(slides: slides, total: content.pages ?? slides.count)
            }
        case let .video(poster, loop):
            playerView.configure(loopURL: loop, poster: poster)
        }
        setNeedsLayout()
    }

    /// Whether the artwork is mounted on the mat rather than filling it.
    private var mounts: Bool { style == .poster || style == .feature }

    private func show(still: CGImage?) {
        let image = still.map { UIImage(cgImage: $0) }
        if let still { artworkAspect = CGFloat(still.width) / CGFloat(max(still.height, 1)) }
        let tint = mounts ? HomeCardTint.mat(from: still) : Theme.Color.artworkMat
        setNeedsLayout()
        layoutIfNeeded()
        UIView.transition(
            with: mat, duration: Theme.Motion.duration(Theme.Motion.quick),
            options: [.transitionCrossDissolve, .allowUserInteraction]
        ) {
            self.imageView.image = image
            self.mat.backgroundColor = tint
        }
    }

    private func show(slides: [CGImage], total: Int) {
        if let first = slides.first {
            artworkAspect = CGFloat(first.width) / CGFloat(max(first.height, 1))
        }
        let tint = HomeCardTint.mat(from: slides.first)
        counter.text = "1/\(max(total, slides.count))"
        counter.isHidden = slides.count < 2
        setNeedsLayout()
        layoutIfNeeded()
        UIView.transition(
            with: mat, duration: Theme.Motion.duration(Theme.Motion.quick),
            options: [.transitionCrossDissolve, .allowUserInteraction]
        ) {
            for (index, view) in self.slideImages.enumerated() {
                view.image = slides.indices.contains(index) ? UIImage(cgImage: slides[index]) : nil
                self.slideCards[index].isHidden = !slides.indices.contains(index)
            }
            self.mat.backgroundColor = tint
        }
    }

    func play() { if !playerView.isHidden { playerView.play() } }
    func stop() { playerView.stop() }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let artwork = style.artworkSize
        let width = contentView.bounds.width
        let height = min(artwork.height, contentView.bounds.height)
        artworkHolder.frame = CGRect(x: 0, y: 0, width: width, height: height)
        mat.frame = artworkHolder.bounds
        artworkHolder.layer.shadowPath = UIBezierPath(
            roundedRect: artworkHolder.bounds, cornerRadius: Theme.Radius.lg).cgPath

        let bounds = mat.bounds
        if mounts {
            let fitted = Self.fit(aspect: artworkAspect, in: bounds.insetBy(dx: Self.matInset, dy: Self.matInset))
            printView.frame = fitted
            imageView.frame = printView.bounds
            printView.layer.shadowPath = UIBezierPath(roundedRect: printView.bounds, cornerRadius: 4).cgPath
        } else {
            printView.frame = bounds
            imageView.frame = bounds
        }
        playerView.frame = bounds
        layoutDeck(in: bounds)

        let side = Self.badgeSide
        let inset = Theme.Spacing.xs
        lockBadge.frame = CGRect(x: inset, y: inset, width: side, height: side)
        savedBadge.frame = CGRect(x: bounds.maxX - inset - side, y: inset, width: side, height: side)
        playBadge.frame = CGRect(
            x: bounds.maxX - inset - side,
            y: savedBadge.isHidden ? inset : inset + side + Theme.Spacing.xxs,
            width: side, height: side)
        storyChrome.frame = CGRect(x: 10, y: 10, width: bounds.width - 20, height: 3)
        // Badges sit under the story segments, never on them.
        if style == .story {
            lockBadge.frame.origin.y += 8
            savedBadge.frame.origin.y += 8
        }

        let captionTop = height + Self.captionGap
        let nameHeight = ceil(nameLabel.font.lineHeight)
        nameLabel.frame = CGRect(x: 2, y: captionTop, width: width - 4, height: nameHeight)
        metaLabel.frame = CGRect(
            x: 2, y: nameLabel.frame.maxY + 1, width: width - 4, height: ceil(metaLabel.font.lineHeight))
    }

    /// The front slide on the leading side, the next two stepping out behind it
    /// to the trailing edge — smaller and a touch darker each step.
    private func layoutDeck(in bounds: CGRect) {
        guard style == .deck else { return }
        let inset: CGFloat = 14
        let frontHeight = bounds.height - inset * 2
        let frontWidth = min(frontHeight * artworkAspect, bounds.width * 0.66)
        let front = CGRect(x: inset, y: (bounds.height - frontHeight) / 2,
                           width: frontWidth, height: frontWidth / artworkAspect)
        let available = bounds.width - inset - front.maxX
        let scales: [CGFloat] = [1, 0.88, 0.76]
        for (index, card) in slideCards.enumerated() {
            let scale = scales[index]
            let size = CGSize(width: front.width * scale, height: front.height * scale)
            // Each step shows a fixed share of the room to the right of the front card.
            let reveal = index == 0 ? 0 : available * (index == 1 ? 0.55 : 1)
            let maxX = front.maxX + reveal
            card.frame = CGRect(x: maxX - size.width, y: bounds.midY - size.height / 2,
                                width: size.width, height: size.height)
            slideImages[index].frame = card.bounds
            slideShades[index].frame = card.bounds
            card.layer.shadowPath = UIBezierPath(roundedRect: card.bounds, cornerRadius: 6).cgPath
        }
        counter.sizeToFit()
        counter.layer.cornerRadius = counter.bounds.height / 2
        counter.frame.origin = CGPoint(x: front.maxX - counter.bounds.width - 6, y: front.minY + 6)
    }

    private static func fit(aspect: CGFloat, in rect: CGRect) -> CGRect {
        guard aspect > 0, rect.width > 0, rect.height > 0 else { return rect }
        var size = CGSize(width: rect.width, height: rect.width / aspect)
        if size.height > rect.height { size = CGSize(width: rect.height * aspect, height: rect.height) }
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                      width: size.width, height: size.height).integral
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        playerView.stop()
        playerView.configure(loopURL: nil, poster: nil)
        imageView.image = nil
        slideImages.forEach { $0.image = nil }
        nameLabel.text = nil
        metaLabel.text = nil
        artworkAspect = 0.8
        accessibilityValue = nil
        accessibilityCustomActions = nil
    }
}

// MARK: - Mat tint

/// The colour a poster is mounted on: the artwork's own hue, nearly white in
/// light mode and nearly black in dark — a mat chosen to flatter the print
/// rather than a grey well that looks like a loading state.
enum HomeCardTint {
    @MainActor static func mat(from image: CGImage?) -> UIColor {
        guard let image else { return Theme.Color.artworkMat }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        HeroStageTint.tint(of: image).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let light = UIColor(hue: hue, saturation: min(saturation * 0.32, 0.16), brightness: 0.965, alpha: 1)
        let dark = UIColor(hue: hue, saturation: min(saturation * 0.45, 0.30), brightness: 0.19, alpha: 1)
        return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }
}

// MARK: - Capsule label

/// A small padded label for the deck's "1/5" counter.
private final class HomeCardCapsule: UILabel {
    private let insets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let base = super.sizeThatFits(size)
        return CGSize(width: base.width + insets.left + insets.right,
                      height: base.height + insets.top + insets.bottom)
    }
}

// MARK: - Meta lines

/// The one-line fact under a card's name: "4 photos · 1:1", "5 pages · 4:5",
/// "Video · 9:16".
enum HomeCardMeta {
    static func photos(_ count: Int, ratio: String) -> String {
        let photos = count == 1 ? String(localized: "1 photo") : String(localized: "\(count) photos")
        return join(photos, ratio)
    }

    static func pages(_ count: Int, ratio: String) -> String {
        join(String(localized: "\(count) pages"), ratio)
    }

    static func video(size: CGSize?) -> String {
        join(String(localized: "Video"), size.map(ratioLabel(for:)) ?? "")
    }

    /// The nearest familiar canvas ratio for a pixel size.
    static func ratioLabel(for size: CGSize) -> String {
        guard size.width > 0, size.height > 0 else { return "" }
        let aspect = size.width / size.height
        let known: [(String, CGFloat)] = [
            ("1:1", 1), ("4:5", 0.8), ("9:16", 9.0 / 16), ("3:4", 0.75), ("16:9", 16.0 / 9),
        ]
        return known.min { abs($0.1 - aspect) < abs($1.1 - aspect) }?.0 ?? ""
    }

    private static func join(_ parts: String...) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
