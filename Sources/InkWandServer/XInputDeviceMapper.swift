#if os(Linux)
import Foundation

final class XInputDeviceMapper {
    private let verbose: Bool
    private var stylusAttempts = 0
    private var touchAttempts = 0
    private var didLogUnavailable = false
    private var didLogStylusMissing = false
    private var didLogTouchMissing = false
    private static let maxAttempts = 100

    init(verbose: Bool) {
        self.verbose = verbose
    }

    func mapStylusIfNeeded() {
        mapIfNeeded(
            attempts: &stylusAttempts,
            deviceName: UInputPenDevice.deviceName,
            pen: true,
            didLogMissing: &didLogStylusMissing
        )
    }

    func mapTouchIfNeeded() {
        mapIfNeeded(
            attempts: &touchAttempts,
            deviceName: UInputTouchDevice.deviceName,
            pen: false,
            didLogMissing: &didLogTouchMissing
        )
    }

    private func mapIfNeeded(attempts: inout Int, deviceName: String, pen: Bool, didLogMissing: inout Bool) {
        guard attempts < Self.maxAttempts else { return }
        attempts += 1

        guard shouldUseXInput else { return }

        do {
            let list = try runXInput(arguments: ["list"])
            guard let id = findDeviceID(in: list, deviceName: deviceName, pen: pen) else {
                if verbose, !didLogMissing {
                    didLogMissing = true
                    ServerLog.info("xinput device not visible yet: \(deviceName)")
                }
                return
            }

            _ = try runXInput(
                arguments: [
                    "set-prop",
                    id,
                    "Coordinate Transformation Matrix",
                    "1", "0", "0",
                    "0", "1", "0",
                    "0", "0", "1",
                ]
            )
        } catch {
            if verbose, !didLogUnavailable {
                didLogUnavailable = true
                ServerLog.info("xinput mapping unavailable: \(error)")
            }
        }
    }

    private var shouldUseXInput: Bool {
        if ProcessInfo.processInfo.environment["XDG_SESSION_TYPE"] == "wayland" {
            return false
        }
        guard let display = ProcessInfo.processInfo.environment["DISPLAY"], !display.isEmpty else {
            return false
        }
        return true
    }

    private func findDeviceID(in xinputList: String, deviceName: String, pen: Bool) -> String? {
        let targetPrefix = pen ? "\(deviceName) Pen" : deviceName

        for line in xinputList.split(separator: "\n", omittingEmptySubsequences: true) {
            let text = String(line)
            guard text.contains(targetPrefix), let idRange = text.range(of: "id=") else {
                continue
            }

            let suffix = text[idRange.upperBound...]
            let id = suffix.prefix { $0.isNumber }
            if !id.isEmpty {
                return String(id)
            }
        }

        return nil
    }

    private func runXInput(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["xinput"] + arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw ServerError.commandFailed("xinput \(arguments.joined(separator: " ")) \(text)", process.terminationStatus)
        }

        return text
    }
}
#endif
