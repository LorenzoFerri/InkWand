#if os(macOS)
import ApplicationServices
import Foundation
import IOKit.hidsystem

enum MacPrivacyPermissions {
    static func requestInputPermissions(verbose: Bool) {
        let accessibilityGranted = AXIsProcessTrusted()
        if !accessibilityGranted {
            let accessibilityOptions = [
                "AXTrustedCheckOptionPrompt": true
            ] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(accessibilityOptions)
        }

        let hidPostAccess = IOHIDCheckAccess(kIOHIDRequestTypePostEvent)
        let hidPostGranted: Bool
        if hidPostAccess == kIOHIDAccessTypeUnknown {
            hidPostGranted = IOHIDRequestAccess(kIOHIDRequestTypePostEvent)
        } else {
            hidPostGranted = hidPostAccess == kIOHIDAccessTypeGranted
        }

        let cgPostGranted = CGPreflightPostEventAccess() || CGRequestPostEventAccess()

        ServerLog.info("macOS input permissions: accessibility=\(accessibilityGranted) hidPost=\(hidPostGranted) cgPost=\(cgPostGranted)")

        if verbose || !accessibilityGranted || !hidPostGranted || !cgPostGranted {
            if !accessibilityGranted {
                ServerLog.info("macOS Accessibility is not granted. Grant InkWand in System Settings > Privacy & Security > Accessibility if pad shortcuts do not work.")
            }
            if !hidPostGranted {
                ServerLog.info("macOS input posting permission requested. Grant InkWandServer in System Settings > Privacy & Security if prompted, then reopen the app if input does not work.")
            }
            if !cgPostGranted {
                ServerLog.info("macOS CoreGraphics event posting is not granted. Grant InkWandServer in System Settings > Privacy & Security > Input Monitoring and Accessibility, then reopen the app.")
            }
        }
    }
}
#endif
