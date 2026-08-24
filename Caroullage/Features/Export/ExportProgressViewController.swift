//
//  ExportProgressViewController.swift
//  Caroullage
//
//  Step 04 slice 6a — the export progress modal.
//
//  Implements the plan's Export Progress UX: an indeterminate spinner for the first
//  few seconds, a 0–100% bar once it's clear the export is a long one, a
//  "Processing…" label carrying elapsed time, and a Cancel button that tears the
//  writer down cleanly. `isModalInPresentation` keeps it on screen — the plan is
//  explicit that the user must not be able to accidentally dismiss it mid-export.
//
//  All of the "what should be on screen" decisions live in `ExportProgressState`
//  (unit-tested); this view controller only renders them.
//

import UIKit

final class ExportProgressViewController: UIViewController {

    /// Invoked when the user taps Cancel. The host flips the cancellation token.
    var onCancel: (() -> Void)?

    private let card = UIView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let percentLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let cancelButton = UIButton(type: .system)

    private let exportTitle: String
    /// The Lock Screen / Dynamic Island twin of this modal. A no-op when Live
    /// Activities are unavailable, so it never affects the export.
    private let liveActivity = ExportLiveActivityController()
    private var startDate = Date()
    /// `nonisolated(unsafe)` so the nonisolated `deinit` can invalidate it; it is
    /// only ever created and mutated on the main actor.
    private nonisolated(unsafe) var timer: Timer?
    private var fraction: Double = 0
    private var isCancelling = false

    // MARK: - Init

    init(title: String = "Exporting video…") {
        self.exportTitle = title
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        // The plan: the sheet stays open during export — no accidental dismissal.
        isModalInPresentation = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { timer?.invalidate() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        setupCard()
        startDate = Date()
        startTicking()
        liveActivity.start(title: exportTitle)
        render()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        timer?.invalidate()
        timer = nil
        // The modal is dismissed exactly when the export finishes / is cancelled,
        // so this is the right moment to tear the Live Activity down too.
        liveActivity.end()
    }

    // MARK: - Public API

    /// Feeds a new completed fraction (0…1). `nonisolated` because the exporter
    /// reports progress from its private write queue; the hop to the main actor
    /// happens here so callers don't have to.
    nonisolated func update(fraction newFraction: Double) {
        let clamped = min(1, max(0, newFraction))
        Task { @MainActor [weak self] in
            self?.fraction = clamped
            self?.render()
        }
    }

    /// Switches the UI to the "Cancelling…" state while the writer tears down.
    func beginCancelling() {
        isCancelling = true
        cancelButton.isEnabled = false
        render()
    }

    // MARK: - Setup

    private func setupCard() {
        card.backgroundColor = Theme.Color.surfaceRaised
        card.layer.cornerRadius = Theme.Radius.lg
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        titleLabel.text = exportTitle
        titleLabel.font = Theme.Typography.headline
        titleLabel.textColor = Theme.Color.textPrimary
        titleLabel.textAlignment = .center

        statusLabel.font = Theme.Typography.caption
        statusLabel.textColor = Theme.Color.textSecondary
        statusLabel.textAlignment = .center
        statusLabel.accessibilityIdentifier = "exportProgressStatus"

        percentLabel.font = Theme.Typography.title2
        percentLabel.textColor = Theme.Color.textPrimary
        percentLabel.textAlignment = .center
        percentLabel.accessibilityIdentifier = "exportProgressPercent"

        spinner.color = Theme.Color.accent
        spinner.startAnimating()

        progressView.progressTintColor = Theme.Color.accent
        progressView.trackTintColor = Theme.Color.controlFill
        progressView.accessibilityIdentifier = "exportProgressBar"

        var config = UIButton.Configuration.plain()
        config.title = "Cancel"
        cancelButton.configuration = config
        cancelButton.tintColor = Theme.Color.accent
        cancelButton.titleLabel?.font = Theme.Typography.button
        cancelButton.accessibilityIdentifier = "exportCancelProgressButton"
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            titleLabel, spinner, percentLabel, progressView, statusLabel, cancelButton
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = Theme.Spacing.sm
        stack.setCustomSpacing(Theme.Spacing.md, after: titleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.72),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: Theme.Spacing.lg),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Theme.Spacing.lg),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Theme.Spacing.lg),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Theme.Spacing.sm),
        ])
    }

    private func startTicking() {
        // Drives the elapsed-time label and the spinner→bar switch.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Rendering

    private func render() {
        let state = ExportProgressState(fraction: fraction,
                                        elapsed: Date().timeIntervalSince(startDate),
                                        isCancelling: isCancelling)
        statusLabel.text = state.statusText
        percentLabel.text = state.percentText
        progressView.setProgress(Float(state.fraction), animated: true)
        if !state.isCancelling { liveActivity.update(fraction: state.fraction) }

        // Under the threshold it's a spinner; past it, a real bar + percentage.
        let showsBar = state.showsProgressBar && !state.isCancelling
        progressView.isHidden = !showsBar
        percentLabel.isHidden = !showsBar
        spinner.isHidden = showsBar
        if showsBar { spinner.stopAnimating() } else { spinner.startAnimating() }
    }

    @objc private func cancelTapped() {
        Haptics.tap()
        beginCancelling()
        onCancel?()
    }
}
