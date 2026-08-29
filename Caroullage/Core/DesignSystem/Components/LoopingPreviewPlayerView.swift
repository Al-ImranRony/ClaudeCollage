//
//  LoopingPreviewPlayerView.swift
//  Caroullage
//
//  Step 07 — the moving half of the Home showcase.
//
//  A still frame cannot sell a video collage: the transitions, the beat-sync and
//  the motion ARE the product. So a video card plays a short, silent loop of the
//  real thing. Everything here exists to keep that from costing anything the user
//  would notice — the poster is up instantly and is the permanent state whenever
//  motion should not run, and no decoder is created until someone calls `play()`,
//  so a strip scrolled past off-screen never spins up a video pipeline.
//

import AVFoundation
import UIKit

/// A poster image that can be told to play a muted, looping video over itself.
@MainActor
final class LoopingPreviewPlayerView: UIView {

    private let posterView = UIImageView()

    private var loopURL: URL?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    /// Whether an auto-playing decorative loop is appropriate right now.
    ///
    /// Reduce Motion is the accessibility half. Low Power Mode is the courtesy
    /// half and is just as load-bearing: a user who has asked the phone to stop
    /// spending battery has not asked for three video decoders on a home screen.
    /// Either one means the poster is not a placeholder — it is the finished
    /// state, and no player is ever created.
    static var isMotionAllowed: Bool {
        !Theme.Motion.isReduced
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// True while a player exists and is on screen.
    var isPlaying: Bool { player != nil }

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Pure chrome: whatever hosts this (a cell, the hero card) owns the tap.
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = Theme.Color.cellWell

        posterView.contentMode = .scaleAspectFill
        posterView.clipsToBounds = true
        posterView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(posterView)
        NSLayoutConstraint.activate([
            posterView.topAnchor.constraint(equalTo: topAnchor),
            posterView.leadingAnchor.constraint(equalTo: leadingAnchor),
            posterView.trailingAnchor.constraint(equalTo: trailingAnchor),
            posterView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Sets what this view shows. Any playback already running is torn down
    /// first — reusing the view for a different card while the old loop is still
    /// decoding would leave the previous video playing over the new poster.
    func configure(loopURL: URL?, poster: UIImage?) {
        stop()
        self.loopURL = loopURL
        posterView.image = poster
    }

    /// Starts the loop. Nothing happens — deliberately and silently — when
    /// motion is not allowed, when there is no loop to play, or when a player is
    /// already running; all three are ordinary states for a strip being scrolled,
    /// not errors, and the poster is a complete answer in every one of them.
    func play() {
        guard Self.isMotionAllowed, player == nil, let loopURL else { return }

        let queuePlayer = AVQueuePlayer()
        // These previews are decorative and must never be heard, and — more
        // importantly — must never stop the user's music. `isMuted` guarantees
        // the first: it takes the output to zero. It does NOT guarantee the
        // second, because the app runs on the default `soloAmbient` audio
        // session, which is non-mixing: an item with an enabled audio track can
        // still activate the session and duck whatever was playing, at zero
        // volume, for no reason. The durable fix is upstream — the bundled loops
        // are authored WITHOUT an audio track, so there is nothing to activate
        // the session for. Setting a global `AVAudioSession` category here would
        // be the wrong lever: it is app-wide state, and this view would be
        // silently changing how the video editor's own playback behaves.
        queuePlayer.isMuted = true
        // A silent decorative loop is not a reason to hold the display awake.
        // Left on (the default) it would keep a phone parked on Home from ever
        // dimming, which is exactly the battery complaint Low Power Mode above
        // is trying to avoid.
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = false

        // `AVPlayerLooper` needs the queue player and does the re-enqueueing
        // itself, which is why this is not a plain `AVPlayer` plus a
        // did-play-to-end observer: that approach shows a visible stall at every
        // wrap while the item seeks back to zero.
        let template = AVPlayerItem(url: loopURL)
        looper = AVPlayerLooper(player: queuePlayer, templateItem: template)

        let layer = AVPlayerLayer(player: queuePlayer)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        // Added above the poster, which stays underneath rather than being
        // hidden: it covers the black frame the player layer shows for the
        // instant before its first decoded frame arrives.
        self.layer.addSublayer(layer)

        playerLayer = layer
        player = queuePlayer
        queuePlayer.play()
    }

    /// Pauses, detaches the player layer and releases the pipeline, so an
    /// off-screen card holds nothing but its poster.
    func stop() {
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        looper = nil
        player = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A CALayer that is not a view's backing layer animates its own frame
        // changes implicitly, so on rotation or a cell resize the video would
        // visibly slide into its new box a beat behind the poster under it.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = bounds
        CATransaction.commit()
    }
}
