import Foundation

final class DistributedObserver: NSObject {
    private let handler: @Sendable (Notification) -> Void

    init(_ name: String, handler: @escaping @Sendable (Notification) -> Void) {
        self.handler = handler
        super.init()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(fire(_:)), name: .init(name), object: nil, suspensionBehavior: .deliverImmediately)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func fire(_ note: Notification) {
        handler(note)
    }
}
