import ApplicationServices
import CoreGraphics

func ensureAccessibility() -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
}

func ensureScreenRecording() -> Bool {
    if CGPreflightScreenCaptureAccess() { return true }
    return CGRequestScreenCaptureAccess()
}
