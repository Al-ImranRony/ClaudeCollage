//
//  Haptics.swift
//  ClaudeCollage
//
//  A centralised, semantic haptics vocabulary. The `UIViewController.haptic(_:)`
//  and `notify(_:)` helpers this replaced allocated a fresh `UIFeedbackGenerator`
//  on every call, which the system had to spin up cold — adding latency and
//  occasionally dropping the first tap. This holds long-lived, `prepare()`-primed
//  generators and exposes intent-named triggers so call sites read as design
//  decisions ("selection changed", "action succeeded") rather than raw styles.
//  Step 05b removed the last callers of the old helpers, and the helpers with
//  them, so there is now one way to make the phone buzz.
//

import UIKit

/// App-wide haptic feedback. Main-actor isolated because `UIFeedbackGenerator`
/// must be driven from the main thread.
@MainActor
public enum Haptics {

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    /// Call just before an imminent haptic (e.g. on gesture-begin) to remove
    /// first-fire latency. Safe to call repeatedly.
    public static func prepare() {
        light.prepare()
        selection.prepare()
    }

    /// A crisp tick as a value in a picker/segmented control changes.
    public static func selectionChanged() {
        selection.selectionChanged()
        selection.prepare()
    }

    /// A light tap for a routine control tap (button, tool toggle).
    public static func tap() {
        light.impactOccurred()
        light.prepare()
    }

    /// A firmer tap for a committed action (apply, add photo, snap-to-grid).
    public static func impact() {
        medium.impactOccurred()
    }

    /// A sharp tick for boundary contact (pan hits a cell edge, zoom clamps).
    public static func boundary() {
        rigid.impactOccurred(intensity: 0.6)
    }

    /// A gentle tap for soft, continuous feedback (drag preview settle).
    public static func softTap() {
        soft.impactOccurred()
    }

    public static func success() {
        notification.notificationOccurred(.success)
    }

    public static func warning() {
        notification.notificationOccurred(.warning)
    }

    public static func error() {
        notification.notificationOccurred(.error)
    }
}
