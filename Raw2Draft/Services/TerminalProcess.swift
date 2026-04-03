import Foundation
import Darwin
import GhosttyTerminal

/// Manages a child process (claude) connected via a PTY, bridged to an InMemoryTerminalSession
/// for rendering in libghostty.
final class TerminalProcess: @unchecked Sendable {
    let session: InMemoryTerminalSession
    private(set) var masterFd: Int32 = -1
    private(set) var childPid: pid_t = 0
    private(set) var isRunning = false
    private var readSource: DispatchSourceRead?

    /// Weak-reference box to break the init-time self-capture cycle.
    private class Weak { weak var process: TerminalProcess? }

    init() {
        let weak = Weak()
        session = InMemoryTerminalSession(
            write: { data in
                guard let process = weak.process, process.masterFd >= 0 else { return }
                data.withUnsafeBytes { buf in
                    guard let ptr = buf.baseAddress else { return }
                    Darwin.write(process.masterFd, ptr, buf.count)
                }
            },
            resize: { viewport in
                guard let process = weak.process, process.masterFd >= 0 else { return }
                var winSize = winsize(
                    ws_row: UInt16(viewport.rows),
                    ws_col: UInt16(viewport.columns),
                    ws_xpixel: UInt16(viewport.widthPixels),
                    ws_ypixel: UInt16(viewport.heightPixels)
                )
                ioctl(process.masterFd, TIOCSWINSZ, &winSize)
            }
        )
        weak.process = self
    }

    /// Fork a child process connected via PTY running the given command.
    func start(params: TerminalProcessParams) {
        var masterFd: Int32 = 0
        var winSize = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)

        let pid = forkpty(&masterFd, nil, nil, &winSize)
        guard pid >= 0 else { return }

        if pid == 0 {
            // Child process
            // Set environment
            for (key, value) in params.environment {
                setenv(key, value, 1)
            }
            // Change directory
            chdir(params.currentDirectory)
            // Build argv
            let argv = [params.executable] + params.args
            let cArgs = argv.map { strdup($0)! }
            let cArgv = cArgs + [nil]
            execvp(params.executable, cArgv)
            // If exec fails, exit child
            _exit(127)
        }

        // Parent process
        self.masterFd = masterFd
        self.childPid = pid
        self.isRunning = true
        startReadLoop()
    }

    /// Send data to the child process as if the user typed it.
    func sendInput(_ string: String) {
        guard masterFd >= 0 else { return }
        let data = Data(string.utf8)
        data.withUnsafeBytes { buf in
            guard let ptr = buf.baseAddress else { return }
            Darwin.write(masterFd, ptr, buf.count)
        }
    }

    /// Terminate the child process.
    func terminate() {
        guard isRunning, childPid > 0 else { return }
        kill(childPid, SIGTERM)
        // Give it a moment, then force kill
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.isRunning else { return }
            kill(self.childPid, SIGKILL)
        }
    }

    /// Clean up resources.
    func cleanup() {
        readSource?.cancel()
        readSource = nil
        if masterFd >= 0 {
            close(masterFd)
            masterFd = -1
        }
        isRunning = false
    }

    // MARK: - Private

    private func startReadLoop() {
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFd, queue: .global(qos: .userInteractive))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 8192)
            let bytesRead = read(self.masterFd, &buffer, buffer.count)
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                self.session.receive(data)
            } else {
                // EOF or error — process exited
                self.handleProcessExit()
            }
        }
        source.setCancelHandler { [weak self] in
            self?.cleanup()
        }
        source.resume()
        readSource = source
    }

    private func handleProcessExit() {
        var status: Int32 = 0
        waitpid(childPid, &status, WNOHANG)
        // WIFEXITED/WEXITSTATUS are C macros not available in Swift — replicate their logic
        let exited = (status & 0x7f) == 0
        let exitCode = exited ? Int32((status >> 8) & 0xff) : 1
        isRunning = false
        session.finish(exitCode: UInt32(exitCode), runtimeMilliseconds: 0)
        readSource?.cancel()
    }

    deinit {
        terminate()
        cleanup()
    }
}
