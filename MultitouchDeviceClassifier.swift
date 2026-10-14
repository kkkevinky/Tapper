import Foundation

struct MultitouchDeviceDescriptor: Equatable {
    let isBuiltIn: Bool
    let isOpaqueSurface: Bool
    let preferenceKeys: Set<String>
    let productName: String?
}

enum MultitouchDeviceClassifier {
    static func isMagicMouse(_ descriptor: MultitouchDeviceDescriptor) -> Bool {
        guard !descriptor.isBuiltIn else { return false }

        // Current macOS versions expose Magic Mouse-specific preference keys even
        // when MTDeviceIsOpaqueSurface unexpectedly returns false.
        if descriptor.preferenceKeys.contains(where: { $0.hasPrefix("Mouse") }) {
            return true
        }

        // Never fall back to the legacy opaque flag for a device explicitly
        // identified as a trackpad.
        if descriptor.preferenceKeys.contains(where: { $0.hasPrefix("Trackpad") }) {
            return false
        }

        if let productName = descriptor.productName,
           productName.range(of: "Magic Mouse", options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }

        // Preserve compatibility with systems where the original private API
        // correctly marks the Magic Mouse as an opaque external surface.
        return descriptor.isOpaqueSurface
    }
}
