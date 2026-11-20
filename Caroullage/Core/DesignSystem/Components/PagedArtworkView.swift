//
//  PagedArtworkView.swift
//  Caroullage
//
//  A card's artwork that you can swipe through, one slide per page — the way a
//  carousel template in SCRL's feed (and the Instagram post it becomes) pages
//  sideways under your thumb.
//
//  The Carousel tab used to show page dots over a single cover image. The dots
//  promised pages that the card could not show, so a swipe did nothing. This
//  view makes the promise good: every rendered slide sits side by side in a
//  paging scroll view, and `PageDotsView` follows the page that is showing.
//
//  Two things about touch handling, both of which the obvious version gets
//  wrong:
//
//  • The scroll view takes no touches itself. A `UIScrollView` inside a
//    collection-view cell swallows the taps that select the cell, so tapping a
//    card would stop opening its template. Its pan recogniser is moved onto
//    this view instead: the pan still drives the scroll view, and a plain tap
//    falls through to the cell exactly as it did when the artwork was an
//    image view.
//
//  • The pan only starts for a sideways drag. This view gets
//    `gestureRecognizerShouldBegin` for every recogniser attached to it, and it
//    refuses the pan when the drag is mostly vertical. That vertical drag then
//    scrolls the grid, so a page of cards still scrolls when your thumb
//    happens to land on a picture.
//

import UIKit

@MainActor
final class PagedArtworkView: UIView {

    /// Called whenever the settled or dragged-to page changes.
    var onPageChange: ((Int) -> Void)?
    /// Called when a finger starts paging the artwork — the moment the other
    /// pages are certainly wanted.
    var onDragBegan: (() -> Void)?

    private let scrollView = UIScrollView()
    private var pageViews: [UIImageView] = []

    private(set) var pageCount = 1
    private(set) var currentPage = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.scrollsToTop = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        scrollView.delegate = self
        // See the header: the scroll view must not be the hit-test target, or
        // the cell can never be selected.
        scrollView.isUserInteractionEnabled = false
        addSubview(scrollView)
        addGestureRecognizer(scrollView.panGestureRecognizer)

        setPageCount(1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Content

    /// Resizes the strip to `count` pages and returns to the first. Image views
    /// are reused, so a recycled cell does not rebuild its whole strip.
    func setPageCount(_ count: Int) {
        let count = max(1, count)
        while pageViews.count < count {
            let view = UIImageView()
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            view.backgroundColor = Theme.Color.cellWell
            scrollView.addSubview(view)
            pageViews.append(view)
        }
        for (index, view) in pageViews.enumerated() { view.isHidden = index >= count }
        pageCount = count
        // One page has nowhere to go: no rubber-band, no sideways pan to
        // compete with the grid's vertical scroll.
        scrollView.panGestureRecognizer.isEnabled = count > 1
        scrollView.alwaysBounceHorizontal = count > 1
        setNeedsLayout()
        scroll(to: 0, animated: false)
    }

    /// Sets one page's picture. Crossfades by default, so an artwork that lands
    /// after the card is already on screen eases in rather than popping.
    func setImage(_ image: UIImage?, at index: Int, animated: Bool = true) {
        guard pageViews.indices.contains(index) else { return }
        let view = pageViews[index]
        guard animated, image != nil else {
            view.image = image
            return
        }
        UIView.transition(
            with: view,
            duration: Theme.Motion.duration(Theme.Motion.quick),
            options: [.transitionCrossDissolve, .allowUserInteraction]
        ) { view.image = image }
    }

    func image(at index: Int) -> UIImage? {
        pageViews.indices.contains(index) ? pageViews[index].image : nil
    }

    /// Clears every page and returns to a single, empty, unscrolled page.
    func reset() {
        pageViews.forEach { $0.image = nil }
        setPageCount(1)
    }

    /// Moves to `page`, clamped to the strip. Used by VoiceOver's next/previous
    /// page actions, where there is no finger to drag.
    func scroll(to page: Int, animated: Bool) {
        let target = min(max(page, 0), pageCount - 1)
        let width = scrollView.bounds.width
        if width > 0 {
            scrollView.setContentOffset(CGPoint(x: CGFloat(target) * width, y: 0), animated: animated)
        }
        updateCurrentPage(target)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        // `bounds` + `center`-free frame math is fine here: nothing in this view
        // is ever transformed (the press scale lives on the cell).
        scrollView.frame = CGRect(origin: .zero, size: size)
        for (index, view) in pageViews.enumerated() {
            view.frame = CGRect(x: CGFloat(index) * size.width, y: 0,
                                width: size.width, height: size.height)
        }
        scrollView.contentSize = CGSize(width: size.width * CGFloat(pageCount), height: size.height)
        // A size change (rotation, a masonry relayout) must keep the page that
        // was showing, not leave the strip parked between two pages.
        if !scrollView.isDragging, !scrollView.isDecelerating, size.width > 0 {
            scrollView.contentOffset = CGPoint(x: CGFloat(currentPage) * size.width, y: 0)
        }
    }

    // MARK: - Direction gate

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === scrollView.panGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        guard pageCount > 1 else { return false }
        // Velocity is the intent of a flick; the distance moved so far is the
        // tie-break for a drag that has not built up speed yet.
        let pan = scrollView.panGestureRecognizer
        var direction = pan.velocity(in: self)
        if direction == .zero { direction = pan.translation(in: self) }
        return abs(direction.x) > abs(direction.y)
    }

    private func updateCurrentPage(_ page: Int) {
        guard page != currentPage else { return }
        currentPage = page
        onPageChange?(page)
    }
}

extension PagedArtworkView: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        onDragBegan?()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let width = scrollView.bounds.width
        guard width > 0, scrollView.isDragging || scrollView.isDecelerating else { return }
        // The dot moves at the halfway point, not when the page settles — the
        // indicator should agree with what is mostly on screen.
        let page = min(max(Int((scrollView.contentOffset.x / width).rounded()), 0), pageCount - 1)
        guard page != currentPage else { return }
        // A tick per slide crossed, like a picker detent: the thumb feels the
        // pages it is counting.
        Haptics.selectionChanged()
        updateCurrentPage(page)
    }
}

/// Page dots for a paged card: a row of small dots with the current one drawn
/// as a short capsule, the way SCRL's feed and Instagram's own carousel post
/// mark the slide you are on.
@MainActor
final class PageDotsView: UIView {

    static let dotSize: CGFloat = 6
    private static let activeWidth: CGFloat = 16
    private static let spacing: CGFloat = 5

    private var dots: [UIView] = []
    private(set) var numberOfPages = 0
    private(set) var currentPage = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        // The card speaks its page for VoiceOver; the dots are a picture of it.
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(numberOfPages: Int) {
        self.numberOfPages = max(0, numberOfPages)
        currentPage = 0
        while dots.count < self.numberOfPages {
            let dot = UIView()
            dot.layer.cornerRadius = Self.dotSize / 2
            dot.layer.cornerCurve = .continuous
            addSubview(dot)
            dots.append(dot)
        }
        for (index, dot) in dots.enumerated() { dot.isHidden = index >= self.numberOfPages }
        restyle()
        setNeedsLayout()
        layoutIfNeeded()
    }

    func setCurrentPage(_ page: Int, animated: Bool) {
        let page = min(max(page, 0), max(numberOfPages - 1, 0))
        guard page != currentPage else { return }
        currentPage = page
        let changes = {
            self.restyle()
            self.layoutDots()
        }
        guard animated else { return changes() }
        UIView.animate(
            withDuration: Theme.Motion.duration(Theme.Motion.quick),
            delay: 0, options: [.beginFromCurrentState, .allowUserInteraction],
            animations: changes)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.rowWidth(for: numberOfPages), height: Self.dotSize)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutDots()
    }

    private static func rowWidth(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return activeWidth + CGFloat(count - 1) * (dotSize + spacing)
    }

    private func layoutDots() {
        var x = (bounds.width - Self.rowWidth(for: numberOfPages)) / 2
        let y = (bounds.height - Self.dotSize) / 2
        for index in 0..<numberOfPages {
            let width = index == currentPage ? Self.activeWidth : Self.dotSize
            dots[index].frame = CGRect(x: x, y: y, width: width, height: Self.dotSize)
            x += width + Self.spacing
        }
    }

    private func restyle() {
        for (index, dot) in dots.enumerated() where index < numberOfPages {
            dot.backgroundColor = index == currentPage
                ? Theme.Color.textPrimary
                : Theme.Color.textSecondary.withAlphaComponent(0.35)
        }
    }
}
