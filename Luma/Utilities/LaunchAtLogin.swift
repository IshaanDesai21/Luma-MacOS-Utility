import ServiceManagement

/// Thin wrapper over `SMAppService` for managing the login item.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled {
                try service.register()
            }
        } else {
            if service.status == .enabled {
                try service.unregister()
            }
        }
    }
}
