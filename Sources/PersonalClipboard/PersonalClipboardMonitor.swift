// Adapted from Riley Testut's Clipper PasteboardMonitor, LocationManager and
// ApplicationMonitor (2019–2020), released under the Unlicense.
// Upstream: https://github.com/lonkelle/Clipper
// See ThirdParty/Clipper/UNLICENSE and docs/PERSONAL-CLIPBOARD.md.
#if PERSONAL_BACKGROUND_CLIPBOARD
import UIKit
import CoreLocation
import CoreFoundation
import UserNotifications
import ObjectiveC
import Combine

private let personalClipboardSavedCallback: @convention(c)
    (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void =
{ _, _, _, _, _ in
    DispatchQueue.main.async { PersonalClipboardMonitor.shared.didSaveClip() }
}

@MainActor
final class PersonalClipboardMonitor: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = PersonalClipboardMonitor()
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "personalClipboard.enabled")
    @Published private(set) var running = false
    @Published private(set) var busy = false
    @Published private(set) var status = "Background monitoring is off"
    @Published private(set) var changeEvents = 0
    @Published private(set) var lastChange: Date?
    private var manager: CLLocationManager?
    private var pasteboardObserver: NSObjectProtocol?
    private var heartbeat: Timer?
    private var privateConnection: AnyClass?
    private var requestGeneration = 0

    func setEnabled(_ value: Bool) {
        requestGeneration += 1
        let generation = requestGeneration
        enabled = value
        UserDefaults.standard.set(value, forKey: "personalClipboard.enabled")
        if !value { stop(); return }
        busy = true
        Task { @MainActor in
            defer { if generation == self.requestGeneration { self.busy = false } }
            guard KeyboardStore().isShared else {
                self.status = PersonalClipboardError.missingSharedStorage.localizedDescription
                return
            }
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                guard generation == self.requestGeneration, self.enabled else { return }
                guard allowed else {
                    self.status = "Allow notifications in Settings to save copies from a copy alert."
                    return
                }
                var preferences = KeyboardStore().preferences
                preferences.clipboardHistory = true
                KeyboardStore().preferences = preferences
                NotificationCenter.default.post(name: PersonalClipboardNotifications.didSave, object: nil)
                self.activateLocation()
            } catch {
                self.status = "Notifications could not be enabled. Open Settings and try again."
            }
        }
    }

    func resume() {
        guard enabled, !busy else { return }
        guard KeyboardStore().isShared else {
            stop()
            status = PersonalClipboardError.missingSharedStorage.localizedDescription
            return
        }
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard self.enabled else { return }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                self.stop()
                self.status = "Allow notifications in Settings to resume copy alerts."
                return
            }
            self.activateLocation()
        }
    }

    private func activateLocation() {
        #if targetEnvironment(simulator)
        status = "Clipboard monitoring needs a real iPhone. The simulator cannot verify Clipper's private listener."
        return
        #else
        if manager == nil {
            let location = CLLocationManager()
            location.delegate = self
            location.distanceFilter = CLLocationDistanceMax
            location.desiredAccuracy = kCLLocationAccuracyReduced
            location.pausesLocationUpdatesAutomatically = false
            location.allowsBackgroundLocationUpdates = true
            manager = location
        }
        guard let manager else { return }
        switch manager.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            status = "Set Location to Always in Settings to keep copy alerts running."
            if UIApplication.shared.applicationState == .active { manager.requestAlwaysAuthorization() }
        case .restricted, .denied:
            stop()
            status = "Location access is unavailable. Set it to Always in Settings to start monitoring."
        case .authorizedAlways:
            do {
                try registerPrivateListener()
                manager.startUpdatingLocation()
                running = true
                status = "Copy listener started. Copy text in Safari to test an alert."
                refreshHeartbeat()
                if heartbeat == nil {
                    let timer = Timer(timeInterval: 20, repeats: true) { _ in
                        DispatchQueue.main.async { PersonalClipboardMonitor.shared.refreshHeartbeat() }
                    }
                    RunLoop.main.add(timer, forMode: .common)
                    heartbeat = timer
                }
            } catch {
                stop()
                status = "Clipper's private clipboard listener is unavailable on this iOS version. Clipboard saving in the app still works."
            }
        @unknown default:
            stop()
            status = "This location permission state is unsupported."
        }
        #endif
    }

    private func registerPrivateListener() throws {
        guard pasteboardObserver == nil else { return }
        guard let bundle = Bundle(path: "/System/Library/PrivateFrameworks/Pasteboard.framework"), bundle.load(),
              let connection = NSClassFromString("PBServerConnection"),
              class_getClassMethod(connection, NSSelectorFromString("beginListeningToPasteboardChangeNotifications")) != nil else {
            throw PersonalClipboardError.pasteNotAllowed
        }
        privateConnection = connection
        pasteboardObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("com.apple.pasteboard.changed"), object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.async { PersonalClipboardMonitor.shared.clipboardDidChange() }
        }
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil,
            personalClipboardSavedCallback, PersonalClipboardNotifications.saved as CFString, nil, .deliverImmediately)
        _ = (connection as AnyObject).perform(NSSelectorFromString("beginListeningToPasteboardChangeNotifications"))
    }

    private func clipboardDidChange() {
        guard enabled, running else { return }
        guard KeyboardStore().preferences.clipboardHistory else { setEnabled(false); return }
        changeEvents += 1
        lastChange = Date()
        if UIApplication.shared.applicationState == .active {
            do { status = try PersonalClipboardCapture.saveCurrent() }
            catch { status = error.localizedDescription }
            return
        }
        // Like Clipper, the listener detects a change without trying to read
        // protected clipboard contents while the companion app is backgrounded.
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = PersonalClipboardNotifications.category
        content.title = "Clipboard changed"
        content.body = "Touch and hold to save the current copy to WianTribe."
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: PersonalClipboardNotifications.changed, content: content, trigger: nil
        ))
    }

    func didSaveClip() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [PersonalClipboardNotifications.changed])
        NotificationCenter.default.post(name: PersonalClipboardNotifications.didSave, object: nil)
    }

    private func refreshHeartbeat() {
        guard enabled, running else { return }
        guard KeyboardStore().preferences.clipboardHistory else { setEnabled(false); return }
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [PersonalClipboardNotifications.stopped])
        let content = UNMutableNotificationContent()
        content.title = "Clipboard monitor paused"
        content.body = "Open WianTribe Personal to resume copy alerts."
        // Clipper renews a queued notification as a heartbeat. If iOS suspends
        // or ends this app, the existing notification asks the person to reopen it.
        center.add(UNNotificationRequest(identifier: PersonalClipboardNotifications.stopped,
            content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)))
    }

    private func stop() {
        running = false
        busy = false
        heartbeat?.invalidate()
        heartbeat = nil
        manager?.stopUpdatingLocation()
        if let observer = pasteboardObserver { NotificationCenter.default.removeObserver(observer) }
        pasteboardObserver = nil
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil,
            CFNotificationName(PersonalClipboardNotifications.saved as CFString), nil)
        if let connection = privateConnection {
            let selector = NSSelectorFromString("endListeningToPasteboardChangeNotifications")
            if class_getClassMethod(connection, selector) != nil { _ = (connection as AnyObject).perform(selector) }
        }
        privateConnection = nil
        let center = UNUserNotificationCenter.current()
        let ids = [PersonalClipboardNotifications.changed, PersonalClipboardNotifications.stopped]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        if !enabled { status = "Background monitoring is off" }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard enabled else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways: activateLocation()
        case .authorizedWhenInUse:
            stop()
            status = "Set Location to Always in Settings, then return to WianTribe."
        case .restricted, .denied:
            stop()
            status = "Location access is unavailable. Set it to Always in Settings."
        case .notDetermined: break
        @unknown default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Location is used only to keep this personal process running.
        // Coordinates are never stored, printed, or sent anywhere.
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard enabled else { return }
        stop()
        status = "The location session paused. Open Settings, check Always access, and restart monitoring."
    }
}

final class PersonalClipboardAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([UNNotificationCategory(identifier: PersonalClipboardNotifications.category,
            actions: [], intentIdentifiers: [])])
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: @escaping () -> Void) {
        Task { @MainActor in
            defer { completion() }
            guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
            if response.notification.request.content.categoryIdentifier == PersonalClipboardNotifications.category {
                // A normal tap opens the companion app; expanding the alert instead
                // uses ClipboardReader without opening the app.
                _ = try? PersonalClipboardCapture.saveCurrent()
            }
            PersonalClipboardMonitor.shared.resume()
        }
    }
}
#endif
