import AVFAudio
import Darwin
import Foundation

/// Runs the bundled Csound library as a DSP component while AVAudioEngine owns
/// the hardware device and its real-time clock. This avoids the command-line
/// AUHAL driver's polling loop and gives the future iOS port the same host model.
final class EmbeddedCsoundHost: @unchecked Sendable {
    enum HostError: LocalizedError {
        case missingLibrary(String)
        case missingSymbol(String)
        case csoundFailure(operation: String, code: Int32)
        case invalidAudioConfiguration

        var errorDescription: String? {
            switch self {
            case .missingLibrary(let detail):
                "Unable to load bundled Csound: \(detail)"
            case .missingSymbol(let name):
                "Bundled Csound is missing the API symbol \(name)."
            case .csoundFailure(let operation, let code):
                "Csound \(operation) failed with status \(code)."
            case .invalidAudioConfiguration:
                "Csound returned an invalid audio configuration."
            }
        }
    }

    private typealias Csound = OpaquePointer
    private typealias Create = @convention(c) (UnsafeMutableRawPointer?) -> Csound?
    private typealias Destroy = @convention(c) (Csound?) -> Void
    private typealias SetOption = @convention(c) (Csound?, UnsafePointer<CChar>?) -> Int32
    private typealias CompileCsd = @convention(c) (Csound?, UnsafePointer<CChar>?) -> Int32
    private typealias Start = @convention(c) (Csound?) -> Int32
    private typealias PerformKsmps = @convention(c) (Csound?) -> Int32
    private typealias GetSpout = @convention(c) (Csound?) -> UnsafeMutablePointer<Double>?
    private typealias GetUInt = @convention(c) (Csound?) -> UInt32
    private typealias GetDouble = @convention(c) (Csound?) -> Double
    private typealias InputMessageAsync = @convention(c) (Csound?, UnsafePointer<CChar>?) -> Void
    private typealias Stop = @convention(c) (Csound?) -> Void
    private typealias Cleanup = @convention(c) (Csound?) -> Int32
    private typealias Reset = @convention(c) (Csound?) -> Void

    private struct API: @unchecked Sendable {
        let library: UnsafeMutableRawPointer
        let create: Create
        let destroy: Destroy
        let setOption: SetOption
        let compileCsd: CompileCsd
        let start: Start
        let performKsmps: PerformKsmps
        let getSpout: GetSpout
        let getKsmps: GetUInt
        let getNchnls: GetUInt
        let getSr: GetDouble
        let inputMessageAsync: InputMessageAsync
        let stop: Stop
        let cleanup: Cleanup
        let reset: Reset

        init(libraryURL: URL) throws {
            guard let library = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL) else {
                let detail = dlerror().map { String(cString: $0) } ?? libraryURL.path
                throw HostError.missingLibrary(detail)
            }
            self.library = library
            do {
                create = try Self.load("csoundCreate", from: library)
                destroy = try Self.load("csoundDestroy", from: library)
                setOption = try Self.load("csoundSetOption", from: library)
                compileCsd = try Self.load("csoundCompileCsd", from: library)
                start = try Self.load("csoundStart", from: library)
                performKsmps = try Self.load("csoundPerformKsmps", from: library)
                getSpout = try Self.load("csoundGetSpout", from: library)
                getKsmps = try Self.load("csoundGetKsmps", from: library)
                getNchnls = try Self.load("csoundGetNchnls", from: library)
                getSr = try Self.load("csoundGetSr", from: library)
                inputMessageAsync = try Self.load("csoundInputMessageAsync", from: library)
                stop = try Self.load("csoundStop", from: library)
                cleanup = try Self.load("csoundCleanup", from: library)
                reset = try Self.load("csoundReset", from: library)
            } catch {
                dlclose(library)
                throw error
            }
        }

        private static func load<T>(_ name: String, from library: UnsafeMutableRawPointer) throws -> T {
            guard let symbol = dlsym(library, name) else {
                throw HostError.missingSymbol(name)
            }
            return unsafeBitCast(symbol, to: T.self)
        }
    }

    /// Mutable state is touched exclusively by AVAudioEngine's serial render
    /// callback after construction and before engine shutdown.
    private final class RenderState: @unchecked Sendable {
        let api: API
        let csound: Csound
        let ksmps: Int
        let channels: Int
        var frameOffset: Int
        var finished = false

        init(api: API, csound: Csound, ksmps: Int, channels: Int) {
            self.api = api
            self.csound = csound
            self.ksmps = ksmps
            self.channels = channels
            frameOffset = ksmps
        }

        func render(frameCount: Int, buffers: UnsafeMutableAudioBufferListPointer) {
            let outputChannels = min(2, buffers.count)
            for outputChannel in 0..<outputChannels {
                guard let data = buffers[outputChannel].mData else { continue }
                data.assumingMemoryBound(to: Float.self).initialize(repeating: 0, count: frameCount)
            }
            guard !finished, outputChannels > 0 else { return }

            for frame in 0..<frameCount {
                if frameOffset == ksmps {
                    if api.performKsmps(csound) != 0 {
                        finished = true
                        return
                    }
                    frameOffset = 0
                }
                guard let spout = api.getSpout(csound) else {
                    finished = true
                    return
                }
                let input = frameOffset * channels
                for outputChannel in 0..<outputChannels {
                    guard let data = buffers[outputChannel].mData else { continue }
                    let sourceChannel = min(outputChannel, channels - 1)
                    data.assumingMemoryBound(to: Float.self)[frame] = Float(spout[input + sourceChannel])
                }
                frameOffset += 1
            }
        }
    }

    private let api: API
    private let csound: Csound
    private let audioEngine = AVAudioEngine()
    private let sourceNode: AVAudioSourceNode
    private let renderState: RenderState
    private var stopped = false

    init(runtimeURL: URL, orchestraURL: URL) throws {
        let framework = runtimeURL.appending(
            path: "Frameworks/CsoundLib64.framework/Versions/6.0/CsoundLib64"
        )
        let opcodeDirectory = runtimeURL.appending(
            path: "Frameworks/CsoundLib64.framework/Versions/6.0/Resources/Opcodes64"
        )
        setenv("OPCODE6DIR64", opcodeDirectory.path, 1)

        let api = try API(libraryURL: framework)
        guard let csound = api.create(nil) else {
            dlclose(api.library)
            throw HostError.csoundFailure(operation: "creation", code: -1)
        }

        do {
            for option in ["-+ignore_csopts=1", "-n", "-d", "-m0"] {
                let result = option.withCString { api.setOption(csound, $0) }
                guard result == 0 else {
                    throw HostError.csoundFailure(operation: "option \(option)", code: result)
                }
            }
            let compileResult = orchestraURL.path.withCString { api.compileCsd(csound, $0) }
            guard compileResult == 0 else {
                throw HostError.csoundFailure(operation: "compilation", code: compileResult)
            }
            let startResult = api.start(csound)
            guard startResult == 0 else {
                throw HostError.csoundFailure(operation: "startup", code: startResult)
            }

            let ksmps = Int(api.getKsmps(csound))
            let channels = Int(api.getNchnls(csound))
            let sampleRate = api.getSr(csound)
            guard ksmps > 0, channels > 0, sampleRate > 0,
                  let format = AVAudioFormat(
                    standardFormatWithSampleRate: sampleRate,
                    channels: AVAudioChannelCount(min(2, channels))
                  ) else {
                throw HostError.invalidAudioConfiguration
            }

            let state = RenderState(api: api, csound: csound, ksmps: ksmps, channels: channels)
            let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
                state.render(
                    frameCount: Int(frameCount),
                    buffers: UnsafeMutableAudioBufferListPointer(audioBufferList)
                )
                return noErr
            }
            self.api = api
            self.csound = csound
            renderState = state
            sourceNode = node

            audioEngine.attach(node)
            audioEngine.connect(node, to: audioEngine.mainMixerNode, format: format)
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            api.stop(csound)
            _ = api.cleanup(csound)
            api.reset(csound)
            api.destroy(csound)
            dlclose(api.library)
            throw error
        }
    }

    var isRunning: Bool { !stopped && audioEngine.isRunning }

    func inputMessage(_ message: String) {
        guard !stopped else { return }
        message.withCString { api.inputMessageAsync(csound, $0) }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        audioEngine.stop()
        audioEngine.disconnectNodeOutput(sourceNode)
        audioEngine.detach(sourceNode)
        api.stop(csound)
        _ = api.cleanup(csound)
        api.reset(csound)
        api.destroy(csound)
        dlclose(api.library)
    }
}
