//
//  FavoritesStore.swift
//  Caroullage
//
//  Home retention, phase 4 — the templates a user has saved.
//
//  `UserDefaults`, not SwiftData. There are no relationships and tens of
//  ids, and every model added to `ModelContainerFactory`'s schema is a
//  migration whose failure silently falls back to an in-memory store — i.e.
//  lost projects — so the project database is the wrong place to put a
//  heart. Insertion-ordered, so the "Saved" strips on Home are stable rather
//  than reshuffling on every toggle. The same shape as `CreditStore`.
//

import Foundation

@MainActor
public final class FavoritesStore {

    public static let shared = FavoritesStore()

    /// Posted, with the store as `object`, after any toggle.
    public static let didChangeNotification = Notification.Name("FavoritesStore.didChange")

    public enum Kind: String, Sendable, CaseIterable {
        case photo, carousel
    }

    public struct Item: Hashable, Sendable {
        public let kind: Kind
        public let id: String

        public init(kind: Kind, id: String) {
            self.kind = kind
            self.id = id
        }

        var key: String { "\(kind.rawValue):\(id)" }

        init?(key: String) {
            guard let separator = key.firstIndex(of: ":"),
                  let kind = Kind(rawValue: String(key[..<separator])) else { return nil }
            let id = String(key[key.index(after: separator)...])
            guard !id.isEmpty else { return nil }
            self.init(kind: kind, id: id)
        }
    }

    private static let key = "favorites.items"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isSaved(_ item: Item) -> Bool {
        keys.contains(item.key)
    }

    /// Flips the item and answers its new state.
    @discardableResult
    public func toggle(_ item: Item) -> Bool {
        var all = keys
        let saved: Bool
        if let index = all.firstIndex(of: item.key) {
            all.remove(at: index)
            saved = false
        } else {
            all.append(item.key)
            saved = true
        }
        keys = all
        Analytics.track(.favouriteToggled(id: item.key, saved: saved))
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        return saved
    }

    /// Saved ids of one kind, oldest first.
    public func savedIDs(kind: Kind) -> [String] {
        keys.compactMap(Item.init(key:)).filter { $0.kind == kind }.map(\.id)
    }

    public var count: Int { keys.count }

    private var keys: [String] {
        get { defaults.stringArray(forKey: Self.key) ?? [] }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
