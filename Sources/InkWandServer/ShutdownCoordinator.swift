#if os(Linux)
import Dispatch
import Foundation
import Glibc

final class ShutdownCoordinator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "inkwand.server.shutdown")
    private let lock = NSLock()
    private var cleanup: (() -> Void)?
    private var didShutdown = false
    private var sources: [DispatchSourceSignal] = []

    func setCleanup(_ cleanup: @escaping () -> Void) {
        lock.lock()
        self.cleanup = cleanup
        lock.unlock()
    }

    func installSignalHandlers() {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        sources = [SIGINT, SIGTERM].map { signalNumber in
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: queue)
            source.setEventHandler { [weak self] in
                self?.shutdownAndExit()
            }
            source.resume()
            return source
        }
    }

    func shutdownAndExit() -> Never {
        lock.lock()
        let shouldRunCleanup = !didShutdown
        didShutdown = true
        let cleanup = cleanup
        lock.unlock()

        if shouldRunCleanup {
            print("\nShutting down InkWandServer...")
            cleanup?()
        }

        exit(EXIT_SUCCESS)
    }
}
#endif
