import AppKit
import ServiceManagement

extension Store {
    func initializeLoginItem() {
        // Apply the default once; respect later changes made in macOS Settings.
        if UserDefaults.standard.object(forKey: "loginItemInitialized") == nil {
            setOpenAtLogin(true)
            return
        }
        refreshLoginItem()
    }
    func refreshLoginItem() {
        let status = SMAppService.mainApp.status
        openAtLogin = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
    }
    func setOpenAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            UserDefaults.standard.set(true, forKey: "loginItemInitialized")
        } catch { loginError = "Could not change Open at login: \(error.localizedDescription)" }
        refreshLoginItem()
    }
    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
}
