import AppKit

/// Base class for modules: holds shared services and gives modules an `@objc`
/// capable object for target/action wiring (menu items, buttons, etc.).
@MainActor
class ModuleObject: NSObject {
    let services: ModuleServices

    init(services: ModuleServices) {
        self.services = services
        super.init()
    }
}
