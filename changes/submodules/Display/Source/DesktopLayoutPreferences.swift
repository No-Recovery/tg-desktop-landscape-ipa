import Foundation
import UIKit

/// How the app is oriented on an iPhone. Chosen in Settings > Layout.
public enum DesktopOrientationMode: String {
    /// Always landscape: the desktop-style layout (chat list on the left, chat on the right).
    case landscape
    /// Always portrait: the regular phone layout.
    case portrait
    /// Follows the way the phone is held.
    case auto
}

/// Where the tab bar (Contacts, Calls, Chats, Settings) is shown in the desktop-style layout.
public enum DesktopTabBarPlacement: String {
    /// A vertical bar at the right screen edge, behind the chat.
    case right
    /// A horizontal bar at the bottom, below the chat list.
    case bottom
}

public enum DesktopLayoutPreferences {
    public static let orientationKey = "desktopOrientationMode"
    public static let tabBarPlacementKey = "desktopTabBarPlacement"
    public static let didChangeNotification = Notification.Name("DesktopLayoutPreferencesDidChange")
    
    public static var orientationMode: DesktopOrientationMode {
        get {
            if let value = UserDefaults.standard.string(forKey: DesktopLayoutPreferences.orientationKey), let mode = DesktopOrientationMode(rawValue: value) {
                return mode
            }
            return .landscape
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: DesktopLayoutPreferences.orientationKey)
            NotificationCenter.default.post(name: DesktopLayoutPreferences.didChangeNotification, object: nil)
        }
    }
    
    public static var tabBarPlacement: DesktopTabBarPlacement {
        get {
            if let value = UserDefaults.standard.string(forKey: DesktopLayoutPreferences.tabBarPlacementKey), let placement = DesktopTabBarPlacement(rawValue: value) {
                return placement
            }
            return .right
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: DesktopLayoutPreferences.tabBarPlacementKey)
            NotificationCenter.default.post(name: DesktopLayoutPreferences.didChangeNotification, object: nil)
        }
    }
}
