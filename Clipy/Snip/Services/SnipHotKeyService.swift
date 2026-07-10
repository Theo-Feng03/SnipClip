//
//  SnipHotKeyService.swift
//
//  Clipy
//

import Dependencies
import Foundation
import Magnet

final class SnipHotKeyService {
    private static let identifier = "Snip"

    @Dependency(\.defaultAppStorage)
    private var appStorage

    private(set) var keyCombo: KeyCombo?
    var onTrigger: (() -> Void)?

    func setup() {
        let combo = savedKeyCombo() ?? KeyCombo(key: .a, cocoaModifiers: [.command, .shift])
        change(to: combo)
    }

    func change(to keyCombo: KeyCombo?) {
        self.keyCombo = keyCombo
        save(keyCombo)

        HotKeyCenter.shared.unregisterHotKey(with: Self.identifier)
        guard let keyCombo else { return }
        let hotKey = HotKey(identifier: Self.identifier, keyCombo: keyCombo) { [weak self] _ in
            self?.onTrigger?()
        }
        hotKey.register()
    }
}

private extension SnipHotKeyService {
    func savedKeyCombo() -> KeyCombo? {
        guard let data = appStorage.object(forKey: Constants.HotKey.snipKeyCombo) as? Data else { return nil }
        return NSKeyedUnarchiver.unarchiveObject(with: data) as? KeyCombo
    }

    func save(_ keyCombo: KeyCombo?) {
        appStorage.set(keyCombo?.archive(), forKey: Constants.HotKey.snipKeyCombo)
        appStorage.synchronize()
    }
}
