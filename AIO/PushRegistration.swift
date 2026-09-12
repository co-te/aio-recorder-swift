//
//  PushRegistration.swift — APNs device-token registration for closed-app push.
//  The Pi push server (docker stuff/push/:8020) holds the .p8 key and does
//  the live polling + APNs sends. This file only registers + uploads the token.
//

import UIKit
import UserNotifications

final class PushRegistrar: NSObject, UIApplicationDelegate {
    static let shared = PushRegistrar()
    private let d = UserDefaults.standard

    /// Pi push server base URL, derived from the tik host (same Pi).
    private var serverBase: String {
        let host = d.string(forKey: "tik_host") ?? TikSettings.defaults.host
        let port = d.object(forKey: "push_port") as? Int ?? 8020
        return "http://\(host):\(port)"
    }

    var lastToken: String? {
        d.string(forKey: "apns_token")
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = nil
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        d.set(hex, forKey: "apns_token")
        Task { await self.upload(token: hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        d.removeObject(forKey: "apns_token")
    }

    static func register() {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func upload(token: String) async {
        guard let url = URL(string: serverBase + "/register") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "token": token,
            "bundle": Bundle.main.bundleIdentifier ?? "app.coral8757.pisces1195",
        ])
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Re-upload stored token (call when Pi IP changes).
    func reupload() {
        guard let t = lastToken else { return }
        Task { await upload(token: t) }
    }
}
