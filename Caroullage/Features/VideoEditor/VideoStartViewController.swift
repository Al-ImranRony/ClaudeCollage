//
//  VideoStartViewController.swift
//  Caroullage
//
//  The host for `VideoStartView` — the sheet every "new video" door opens
//  (Home's Video chip, the "+" sheet's Video row). Mirrors
//  `CarouselStartViewController`: dismiss first, then act, because the editor
//  is pushed onto the presenting tab's stack and UIKit will not do that from
//  behind this sheet.
//

import SwiftUI
import UIKit

@MainActor
final class VideoStartViewController: UIViewController {

    var onPickTemplate: ((VideoTemplate) -> Void)?
    /// Called with the chosen "w:h" ratio.
    var onPickBlank: ((String) -> Void)?

    private let templates: [VideoTemplate]

    init(templates: [VideoTemplate]) {
        self.templates = templates
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = Theme.Radius.xl
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.background

        let start = VideoStartView(
            templates: templates,
            onPickTemplate: { [weak self] template in
                guard let self else { return }
                let handler = self.onPickTemplate
                Haptics.tap()
                self.dismiss(animated: true) { handler?(template) }
            },
            onPickBlank: { [weak self] ratio in
                guard let self else { return }
                let handler = self.onPickBlank
                Haptics.tap()
                self.dismiss(animated: true) { handler?(ratio) }
            },
            onCancel: { [weak self] in self?.dismiss(animated: true) })
        let host = UIHostingController(rootView: start)
        host.view.accessibilityIdentifier = "videoStartSheet"
        host.view.backgroundColor = .clear

        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }
}
