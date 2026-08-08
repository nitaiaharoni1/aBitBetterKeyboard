import CoreGraphics
import Foundation

/// Picks which reader gets the frame, and decides whether a screenshot leaves
/// the device.
///
/// The routing question is not "is this screen Hebrew". Nothing on the device
/// can answer that, because the only component that reads text is the one that
/// cannot see Hebrew. The question it actually asks is "did the on-device
/// recogniser read everything that looks like writing?" — which
/// `VisionScreenReader` answers by comparing text regions found against text
/// regions read, without ever naming a script.
///
/// The trade is deliberately lopsided. A Hebrew screen sent down the on-device
/// path yields a confident, wrong message that the user then replies to in their
/// own name. An English screen sent to the cloud costs about five seconds. So
/// the gate is set where no Hebrew or mixed screen in the bar passes it, at the
/// price of three of twelve English screens going to the cloud unnecessarily.
public struct RoutedScreenReader: ScreenReader {
    private let onDevice: any ScreenReader
    private let cloud: (any ScreenReader)?

    public init(onDevice: any ScreenReader = VisionScreenReader(), cloud: (any ScreenReader)?) {
        self.onDevice = onDevice
        self.cloud = cloud
    }

    public func read(_ frame: CGImage) async throws -> AIOutput<ScreenReading?> {
        do {
            return try await onDevice.read(frame)
        } catch ScreenReadError.notReadableOnDevice {
            guard let cloud else { throw ScreenReadError.noCloudReader }
            return try await cloud.read(frame)
        }
    }
}
