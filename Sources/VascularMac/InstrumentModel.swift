import Foundation
import SwiftUI
import VascularCore

@MainActor
final class InstrumentModel: ObservableObject {
    @Published private(set) var session = VascularSession()
    @Published private(set) var awakenedPad: PadCoordinate?
    @Published private(set) var selectedVesselID: UUID?
    @Published private(set) var status = "LONG-PRESS THE LEFT PAD OF AN EMPTY TRACK"
    @Published private(set) var controllerStatus = "LAUNCHPAD · SEARCHING"
    @Published private(set) var hubPulseBright = false
    @Published private(set) var editingTrack: Int?
    @Published private(set) var processorRandomizeTrack: Int?
    @Published private(set) var trackVolumes = Array(repeating: TrackMixer.defaultVolume, count: 8)
    @Published private(set) var trackPans = Array(repeating: TrackMixer.defaultPan, count: 8)
    @Published private(set) var trackSends = Array(repeating: TrackSendLevels.zero, count: 8)
    @Published private(set) var trackGates = Array(repeating: TrackMixer.defaultGate, count: 8)
    @Published private(set) var shiftHeld = false
    @Published private(set) var activeSceneSlots: [Int: Int] = [:]
    @Published private(set) var projectViewOpen = false
    @Published private(set) var activeProjectSlot: Int?
    @Published private(set) var projectSaveConfirmationSlot: Int?
    @Published private(set) var projectSaveConfirmationBright = false
    @Published private(set) var globalSceneViewOpen = false
    @Published private(set) var activeGlobalSceneSlot: Int?
    @Published private(set) var globalSceneSaveConfirmationSlot: Int?
    @Published private(set) var globalSceneSaveConfirmationBright = false
    @Published private(set) var masterEffectsViewOpen = false
    @Published private(set) var masterEffects = MasterEffectParameters.defaults
    @Published private(set) var destructiveEffectsViewOpen = false
    @Published private(set) var destructiveEffects = DestructiveEffectParameters.defaults

    private let graphFactory = VesselGraphFactory()
    private let audioEngine: any AudioEngine
    private var launchpad: LaunchpadController?
    private var launchpadPadsDown: Set<PadCoordinate> = []
    private var launchpadSource: PadCoordinate?
    private var longPressTask: Task<Void, Never>?
    private var auxiliaryPressTimes: [Int: ContinuousClock.Instant] = [:]
    private var consumedAuxiliaryRows: Set<Int> = []
    private var processorRandomizeLatched = false
    private var scenePressTimes: [Int: ContinuousClock.Instant] = [:]
    private var sceneBank = TrackSceneBank()
    private var sceneRecallGeneration = Array(repeating: UInt64(0), count: 8)
    private let projectStore = ProjectStore()
    private var projectBank = ProjectBank()
    private var projectButtonPressTime: ContinuousClock.Instant?
    private var projectSlotPressTimes: [Int: ContinuousClock.Instant] = [:]
    private var projectRecallGeneration: UInt64 = 0
    private var projectSaveConfirmationTask: Task<Void, Never>?
    private var globalSceneBank = GlobalSceneBank()
    private var globalSceneButtonPressTime: ContinuousClock.Instant?
    private var globalSceneSlotPressTimes: [Int: ContinuousClock.Instant] = [:]
    private var globalSceneRecallGeneration: UInt64 = 0
    private var globalSceneSaveConfirmationTask: Task<Void, Never>?
    private var masterEffectsButtonPressTime: ContinuousClock.Instant?
    private var destructiveEffectsButtonPressTime: ContinuousClock.Instant?

    var activeTrackCount: Int {
        Set(session.vessels.map { $0.source.row }).count
    }

    var processorCount: Int {
        session.vessels.reduce(0) { $0 + $1.processors.count }
    }

    init(audioEngine: any AudioEngine = CsoundProcessEngine()) {
        self.audioEngine = audioEngine
        do {
            projectBank = try projectStore.load()
        } catch {
            status = "PROJECT STORE ERROR · \(error.localizedDescription.uppercased())"
        }
        let controller = LaunchpadController { [weak self] event in
            Task { @MainActor [weak self] in self?.handleLaunchpad(event) }
        }
        launchpad = controller
        let names = controller.connect()
        controllerStatus = names.isEmpty
            ? "LAUNCHPAD · NOT CONNECTED"
            : "LAUNCHPAD · PROGRAMMER MODE"
        renderController()
    }

    func awaken(_ pad: PadCoordinate) {
        guard editingTrack == nil else { return }
        awakenedPad = pad
        status = pad.column == 0
            ? "TRACK \(pad.row + 1) GENERATOR ARMED — SELECT THE NEW ENDPOINT"
            : "HOLD THE LEFTMOST GENERATOR TO MANAGE THIS TRACK"
        renderController()
    }

    func longPress(_ pad: PadCoordinate) {
        if destructiveEffectsViewOpen {
            adjustDestructiveEffects(with: pad)
            renderController()
        } else if masterEffectsViewOpen {
            adjustMasterEffects(with: pad)
            renderController()
        } else if projectViewOpen, let slot = ProjectGrid.slot(for: pad) {
            saveProject(slot: slot)
            renderController()
        } else if globalSceneViewOpen, let slot = GlobalSceneGrid.slot(for: pad) {
            saveGlobalScene(slot: slot)
            renderController()
        } else if let track = editingTrack, let slot = TrackMixer.sceneSlot(for: pad) {
            saveScene(track: track, slot: slot)
            renderController()
        } else {
            awaken(pad)
        }
    }

    func tap(_ pad: PadCoordinate) {
        defer { renderController() }
        if let track = processorRandomizeTrack {
            randomizeProcessor(at: pad, forTrack: track)
            if processorRandomizeLatched {
                processorRandomizeTrack = nil
                processorRandomizeLatched = false
            }
            return
        }
        if shiftHeld {
            awakenedPad = nil
            if pad.column == 0 {
                toggleGeneratorLock(row: pad.row)
            } else if currentTrackEndpoint(row: pad.row) == pad {
                toggleChainLock(row: pad.row, endpoint: pad)
            } else {
                status = "SHIFT · SELECT A GENERATOR OR CURRENT ENDPOINT"
            }
            return
        }
        if destructiveEffectsViewOpen {
            adjustDestructiveEffects(with: pad)
            return
        }
        if masterEffectsViewOpen {
            adjustMasterEffects(with: pad)
            return
        }
        if projectViewOpen {
            if let slot = ProjectGrid.slot(for: pad) { loadProject(slot: slot) }
            return
        }
        if globalSceneViewOpen {
            if let slot = GlobalSceneGrid.slot(for: pad) { loadGlobalScene(slot: slot) }
            return
        }
        if let track = editingTrack {
            if let slot = TrackMixer.sceneSlot(for: pad) {
                loadScene(track: track, slot: slot)
                return
            }
            adjustTrack(track, with: pad)
            return
        }
        guard let source = awakenedPad else {
            selectVessel(at: pad)
            return
        }

        guard source != pad else {
            awakenedPad = nil
            status = "SOURCE CANCELLED"
            return
        }

        let topology = TrackTopology(vessels: session.vessels)
        let decision = topology.managementAction(from: source, to: pad)
        let actionCanGrow: Bool = switch decision {
        case .create, .extend: true
        default: false
        }
        if actionCanGrow,
           let chainLock = session.chainLocks[source.row],
           let generatorLock = session.generatorLocks[source.row],
           generatorLock == chainLock.generatorLock,
           pad.column >= chainLock.endpointColumn,
           !chainLock.matchesLivePrefix(in: session.vessels, row: source.row) {
            restoreLockedChain(chainLock, row: source.row, destination: pad)
            return
        }
        let parents: [VesselGraph]
        let segmentSource: PadCoordinate
        switch decision {
        case .create:
            parents = []
            segmentSource = source
        case .extend(let parent):
            parents = [parent]
            segmentSource = parent.destination
        case .trim:
            markTrackDirty(source.row)
            session.vessels = topology.trimmingTrack(row: source.row, endingAt: pad)
            selectedVesselID = nil
            awakenedPad = nil
            let remaining = session.vessels
                .filter { $0.source.row == source.row }
                .reduce(0) { $0 + $1.processors.count }
            status = "TRACK \(source.row + 1) TRIMMED · \(remaining) PROCESSORS"
            synchronizeAudio()
            return
        case .clear:
            markTrackDirty(source.row)
            session.vessels.removeAll { $0.source.row == source.row }
            selectedVesselID = nil
            awakenedPad = nil
            status = "TRACK \(source.row + 1) CLEARED"
            synchronizeAudio()
            return
        case .rejected(let violation):
            awakenedPad = nil
            status = rejectionMessage(violation, row: source.row)
            return
        }

        let vesselSeed = session.drawSeed()
        let trackProcessors = session.vessels
            .filter { $0.source.row == source.row }
            .flatMap(\.processors)
        let activeSourceFamilies = Set(
            session.vessels
                .filter { $0.parentVesselIDs.isEmpty }
                .map(\.sourceFamily)
        )
        let vessel = graphFactory.make(
            source: segmentSource,
            destination: pad,
            seed: vesselSeed,
            parentVessels: parents,
            existingProcessors: trackProcessors,
            avoidingSourceFamilies: activeSourceFamilies,
            generatorLock: parents.isEmpty ? session.generatorLocks[source.row] : nil,
            harmonicAnchor: parents.isEmpty ? session.harmonicAnchor : nil
        )
        markTrackDirty(source.row)
        session.vessels.append(vessel)
        selectedVesselID = vessel.id
        awakenedPad = nil
        status = vessel.isExtension
            ? "TRACK \(source.row + 1) EXTENDED · +\(vessel.processors.count) PROCESSORS"
            : "TRACK \(source.row + 1) · \(displayName(vessel.sourceFamily)) · \(vessel.processors.count) PROCESSORS"

        synchronizeAudio()
    }

    private func synchronizeAudio() {
        let vessels = session.vessels
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.audioEngine.synchronize(vessels)
            } catch {
                self.status = "AUDIO ERROR · \(error.localizedDescription.uppercased())"
            }
        }
    }

    func drainSelected() {
        defer { renderController() }
        guard let id = selectedVesselID,
              let index = session.vessels.firstIndex(where: { $0.id == id }) else {
            status = "NO CHAIN SELECTED"
            return
        }
        let vessel = session.vessels[index]
        markTrackDirty(vessel.source.row)
        let descendants = TrackTopology(vessels: session.vessels).descendants(of: vessel.id)
        session.vessels.removeAll { descendants.contains($0.id) }
        selectedVesselID = nil
        status = "TRACK \(vessel.source.row + 1) · CHAIN REMOVED"
        synchronizeAudio()
    }

    func panic() {
        markProjectDirty()
        session.vessels.removeAll()
        activeSceneSlots.removeAll()
        selectedVesselID = nil
        awakenedPad = nil
        status = "ALL TRACKS STOPPED"
        renderController()
        Task { await audioEngine.panic() }
    }

    func closeTrackEditor() {
        scenePressTimes.removeAll()
        editingTrack = nil
        status = "TRACK MATRIX"
        renderController()
    }

    func toggleTrackEditor(row: Int) {
        guard (0..<PadCoordinate.matrixSize).contains(row),
              !projectViewOpen,
              !globalSceneViewOpen,
              !masterEffectsViewOpen,
              !destructiveEffectsViewOpen,
              !shiftHeld else { return }
        longPressTask?.cancel()
        processorRandomizeTrack = nil
        processorRandomizeLatched = false
        consumedAuxiliaryRows.removeAll()
        scenePressTimes.removeAll()
        launchpadSource = nil
        launchpadPadsDown.removeAll()
        awakenedPad = nil
        if editingTrack == row {
            editingTrack = nil
            status = "TRACK MATRIX"
        } else {
            editingTrack = row
            status = mixerStatus(for: row)
        }
        renderController()
    }

    func armProcessorRandomization(row: Int) {
        guard (0..<PadCoordinate.matrixSize).contains(row),
              !projectViewOpen,
              !globalSceneViewOpen,
              !masterEffectsViewOpen,
              !destructiveEffectsViewOpen,
              !shiftHeld else { return }
        editingTrack = nil
        awakenedPad = nil
        processorRandomizeTrack = row
        processorRandomizeLatched = true
        status = "TRACK \(row + 1) · SELECT AN UNLOCKED PROCESSOR TO RANDOMIZE"
        renderController()
    }

    func toggleShiftLatch() {
        setShiftHeld(!shiftHeld)
    }

    func toggleProjectView() {
        shiftHeld = false
        processorRandomizeTrack = nil
        processorRandomizeLatched = false
        consumedAuxiliaryRows.removeAll()
        longPressTask?.cancel()
        scenePressTimes.removeAll()
        projectSlotPressTimes.removeAll()
        globalSceneSlotPressTimes.removeAll()
        launchpadSource = nil
        launchpadPadsDown.removeAll()
        awakenedPad = nil
        editingTrack = nil
        masterEffectsViewOpen = false
        destructiveEffectsViewOpen = false
        globalSceneViewOpen = false
        projectViewOpen.toggle()
        status = projectViewOpen ? "PROJECTS · HOLD SAVE / TAP LOAD" : "TRACK MATRIX"
        renderController()
    }

    func toggleMasterEffectsView() {
        shiftHeld = false
        processorRandomizeTrack = nil
        processorRandomizeLatched = false
        consumedAuxiliaryRows.removeAll()
        longPressTask?.cancel()
        scenePressTimes.removeAll()
        projectSlotPressTimes.removeAll()
        globalSceneSlotPressTimes.removeAll()
        launchpadSource = nil
        launchpadPadsDown.removeAll()
        awakenedPad = nil
        editingTrack = nil
        projectViewOpen = false
        destructiveEffectsViewOpen = false
        globalSceneViewOpen = false
        masterEffectsViewOpen.toggle()
        status = masterEffectsViewOpen
            ? "MASTER RETURNS · REVERB / DELAY"
            : "TRACK MATRIX"
        renderController()
    }

    func toggleDestructiveEffectsView() {
        shiftHeld = false
        processorRandomizeTrack = nil
        processorRandomizeLatched = false
        consumedAuxiliaryRows.removeAll()
        longPressTask?.cancel()
        scenePressTimes.removeAll()
        projectSlotPressTimes.removeAll()
        globalSceneSlotPressTimes.removeAll()
        launchpadSource = nil
        launchpadPadsDown.removeAll()
        awakenedPad = nil
        editingTrack = nil
        projectViewOpen = false
        masterEffectsViewOpen = false
        globalSceneViewOpen = false
        destructiveEffectsViewOpen.toggle()
        status = destructiveEffectsViewOpen
            ? "MASTER RETURNS · SATURATION / DECIMATION"
            : "TRACK MATRIX"
        renderController()
    }

    func toggleGlobalSceneView() {
        shiftHeld = false
        processorRandomizeTrack = nil
        processorRandomizeLatched = false
        consumedAuxiliaryRows.removeAll()
        longPressTask?.cancel()
        scenePressTimes.removeAll()
        projectSlotPressTimes.removeAll()
        globalSceneSlotPressTimes.removeAll()
        launchpadSource = nil
        launchpadPadsDown.removeAll()
        awakenedPad = nil
        editingTrack = nil
        projectViewOpen = false
        masterEffectsViewOpen = false
        destructiveEffectsViewOpen = false
        globalSceneViewOpen.toggle()
        status = globalSceneViewOpen
            ? "GLOBAL SCENES · HOLD SAVE / TAP LOAD"
            : "TRACK MATRIX"
        renderController()
    }

    func shutdown() {
        longPressTask?.cancel()
        projectSaveConfirmationTask?.cancel()
        globalSceneSaveConfirmationTask?.cancel()
        launchpad?.disconnect()
        launchpad = nil
        let audioEngine = audioEngine
        let completion = DispatchSemaphore(value: 0)
        Task.detached {
            await audioEngine.panic()
            completion.signal()
        }
        _ = completion.wait(timeout: .now() + 2)
    }

    func advanceHubPulse() {
        guard !VesselTopology(vessels: session.vessels).hubs.isEmpty else {
            if hubPulseBright { hubPulseBright = false }
            return
        }
        hubPulseBright.toggle()
        renderController()
    }

    private func handleLaunchpad(_ event: LaunchpadEvent) {
        switch event {
        case .projectPressed:
            projectButtonPressTime = .now

        case .projectReleased:
            guard let start = projectButtonPressTime else { return }
            projectButtonPressTime = nil
            guard start.duration(to: .now) < .milliseconds(480) else { return }
            toggleProjectView()

        case .masterEffectsPressed:
            masterEffectsButtonPressTime = .now

        case .masterEffectsReleased:
            guard let start = masterEffectsButtonPressTime else { return }
            masterEffectsButtonPressTime = nil
            guard start.duration(to: .now) < .milliseconds(480) else { return }
            toggleMasterEffectsView()

        case .destructiveEffectsPressed:
            destructiveEffectsButtonPressTime = .now

        case .destructiveEffectsReleased:
            guard let start = destructiveEffectsButtonPressTime else { return }
            destructiveEffectsButtonPressTime = nil
            guard start.duration(to: .now) < .milliseconds(480) else { return }
            toggleDestructiveEffectsView()

        case .globalScenesPressed:
            globalSceneButtonPressTime = .now

        case .globalScenesReleased:
            guard let start = globalSceneButtonPressTime else { return }
            globalSceneButtonPressTime = nil
            guard start.duration(to: .now) < .milliseconds(480) else { return }
            toggleGlobalSceneView()

        case .pressed(let pad, _):
            if let track = processorRandomizeTrack {
                consumedAuxiliaryRows.insert(track)
                randomizeProcessor(at: pad, forTrack: track)
                renderController()
                return
            }
            if destructiveEffectsViewOpen {
                adjustDestructiveEffects(with: pad)
                renderController()
                return
            }
            if masterEffectsViewOpen {
                adjustMasterEffects(with: pad)
                renderController()
                return
            }
            if projectViewOpen {
                if let slot = ProjectGrid.slot(for: pad) {
                    projectSlotPressTimes[slot] = .now
                    status = projectBank.project(slot: slot) == nil
                        ? "PROJECT \(slot + 1) EMPTY · HOLD TO SAVE"
                        : "PROJECT \(slot + 1) · TAP LOAD / HOLD OVERWRITE"
                    renderController()
                }
                return
            }
            if globalSceneViewOpen {
                if let slot = GlobalSceneGrid.slot(for: pad) {
                    globalSceneSlotPressTimes[slot] = .now
                    status = globalSceneBank.scene(slot: slot) == nil
                        ? "GLOBAL SCENE \(slot + 1) EMPTY · HOLD TO SAVE"
                        : "GLOBAL SCENE \(slot + 1) · TAP LOAD / HOLD OVERWRITE"
                    renderController()
                }
                return
            }
            if shiftHeld {
                longPressTask?.cancel()
                launchpadSource = nil
                launchpadPadsDown.removeAll()
                awakenedPad = nil
                if pad.column == 0 {
                    toggleGeneratorLock(row: pad.row)
                } else if currentTrackEndpoint(row: pad.row) == pad {
                    toggleChainLock(row: pad.row, endpoint: pad)
                } else {
                    status = "SHIFT · SELECT A GENERATOR OR CURRENT ENDPOINT"
                }
                renderController()
                return
            }
            if let track = editingTrack {
                if let slot = TrackMixer.sceneSlot(for: pad) {
                    scenePressTimes[slot] = .now
                    status = sceneBank.scene(track: track, slot: slot) == nil
                        ? "TRACK \(track + 1) · SCENE \(slot + 1) EMPTY · HOLD TO SAVE"
                        : "TRACK \(track + 1) · SCENE \(slot + 1) · TAP LOAD / HOLD OVERWRITE"
                    renderController()
                    return
                }
                adjustTrack(track, with: pad)
                renderController()
                return
            }
            launchpadPadsDown.insert(pad)
            if let source = launchpadSource, source != pad {
                longPressTask?.cancel()
                if awakenedPad != source { awaken(source) }
                tap(pad)
            } else if launchpadSource == nil {
                launchpadSource = pad
                longPressTask?.cancel()
                longPressTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(480))
                    guard !Task.isCancelled,
                          let self,
                          self.launchpadPadsDown.contains(pad) else { return }
                    self.awaken(pad)
                }
            }

        case .released(let pad):
            if masterEffectsViewOpen || destructiveEffectsViewOpen { return }
            if projectViewOpen,
               let slot = ProjectGrid.slot(for: pad),
               let start = projectSlotPressTimes.removeValue(forKey: slot) {
                if start.duration(to: .now) >= .milliseconds(480) {
                    saveProject(slot: slot)
                } else {
                    loadProject(slot: slot)
                }
                renderController()
                return
            }
            if globalSceneViewOpen,
               let slot = GlobalSceneGrid.slot(for: pad),
               let start = globalSceneSlotPressTimes.removeValue(forKey: slot) {
                if start.duration(to: .now) >= .milliseconds(480) {
                    saveGlobalScene(slot: slot)
                } else {
                    loadGlobalScene(slot: slot)
                }
                renderController()
                return
            }
            if let track = editingTrack,
               let slot = TrackMixer.sceneSlot(for: pad),
               let start = scenePressTimes.removeValue(forKey: slot) {
                if start.duration(to: .now) >= .milliseconds(480) {
                    saveScene(track: track, slot: slot)
                } else {
                    loadScene(track: track, slot: slot)
                }
                renderController()
                return
            }
            launchpadPadsDown.remove(pad)
            if launchpadSource == pad {
                longPressTask?.cancel()
                launchpadSource = nil
                if awakenedPad == pad { awakenedPad = nil }
                renderController()
            }

        case .auxiliaryPressed(let row):
            guard !projectViewOpen && !globalSceneViewOpen && !masterEffectsViewOpen
                    && !destructiveEffectsViewOpen else { return }
            auxiliaryPressTimes[row] = .now
            consumedAuxiliaryRows.remove(row)
            editingTrack = nil
            processorRandomizeTrack = row
            processorRandomizeLatched = false
            status = "TRACK \(row + 1) · SELECT AN UNLOCKED PROCESSOR TO RANDOMIZE"
            renderController()

        case .auxiliaryReleased(let row):
            guard let start = auxiliaryPressTimes.removeValue(forKey: row) else { return }
            processorRandomizeTrack = nil
            processorRandomizeLatched = false
            if consumedAuxiliaryRows.remove(row) != nil {
                renderController()
            } else if start.duration(to: .now) < .milliseconds(480) {
                toggleTrackEditor(row: row)
            } else {
                status = "TRACK MATRIX"
                renderController()
            }

        case .shiftPressed:
            setShiftHeld(true)

        case .shiftReleased:
            setShiftHeld(false)
        }
    }

    private func setShiftHeld(_ held: Bool) {
        processorRandomizeTrack = nil
        processorRandomizeLatched = false
        consumedAuxiliaryRows.removeAll()
        shiftHeld = held
        if held {
            projectViewOpen = false
            masterEffectsViewOpen = false
            destructiveEffectsViewOpen = false
            globalSceneViewOpen = false
            projectSlotPressTimes.removeAll()
            globalSceneSlotPressTimes.removeAll()
            editingTrack = nil
            scenePressTimes.removeAll()
            longPressTask?.cancel()
            launchpadSource = nil
            launchpadPadsDown.removeAll()
            awakenedPad = nil
            status = "SHIFT · SELECT A GENERATOR OR CURRENT ENDPOINT"
        } else if status.hasPrefix("SHIFT · SELECT") {
            status = "TRACK MATRIX"
        }
        renderController()
    }

    private func toggleGeneratorLock(row: Int) {
        if session.generatorLocks.removeValue(forKey: row) != nil {
            let clearedChainLock = session.chainLocks.removeValue(forKey: row) != nil
            markTrackDirty(row)
            status = clearedChainLock
                ? "TRACK \(row + 1) · GENERATOR + CHAIN UNLOCKED"
                : "TRACK \(row + 1) · GENERATOR UNLOCKED"
            return
        }
        guard let root = session.vessels.first(where: {
            $0.parentVesselIDs.isEmpty && $0.source.row == row
        }) else {
            status = "TRACK \(row + 1) · CREATE A GENERATOR BEFORE LOCKING"
            return
        }
        let newLock = GeneratorLock(
            sourceSeed: root.sourceSeed,
            sourceFamily: root.sourceFamily,
            fundamentalHz: root.sourceFundamentalHz
        )
        session.generatorLocks[row] = newLock
        if let chainLock = session.chainLocks[row],
           chainLock.generatorLock != newLock {
            session.chainLocks.removeValue(forKey: row)
        }
        markTrackDirty(row)
        if session.harmonicAnchor == nil {
            session.harmonicAnchor = HarmonicAnchor(
                fundamentalHz: root.sourceFundamentalHz,
                sourceSeed: root.sourceSeed
            )
            status = "TRACK \(row + 1) · \(displayName(root.sourceFamily)) · HARMONIC ANCHOR"
        } else {
            status = "TRACK \(row + 1) · \(displayName(root.sourceFamily)) LOCKED"
        }
    }

    private func randomizeProcessor(at pad: PadCoordinate, forTrack track: Int) {
        guard pad.row == track else {
            status = "TRACK \(track + 1) · SELECT A PROCESSOR ON THIS TRACK"
            return
        }
        if pad.column == 0 {
            randomizeGenerator(row: track)
            return
        }
        if let lock = session.chainLocks[track], pad.column <= lock.endpointColumn {
            status = "TRACK \(track + 1) · PAD \(pad.column + 1) IS CHAIN-LOCKED"
            return
        }
        guard let vesselIndex = session.vessels.firstIndex(where: { vessel in
            vessel.source.row == track && vessel.processors.contains { $0.coordinate == pad }
        }), let processorIndex = session.vessels[vesselIndex].processors.firstIndex(where: {
            $0.coordinate == pad
        }) else {
            status = "TRACK \(track + 1) · NO PROCESSOR AT PAD \(pad.column + 1)"
            return
        }

        let vessel = session.vessels[vesselIndex]
        let current = vessel.processors[processorIndex]
        let replacement = graphFactory.rerandomize(current, seed: session.drawSeed())
        var processors = vessel.processors
        processors[processorIndex] = replacement
        session.vessels[vesselIndex] = VesselGraph(
            id: vessel.id,
            source: vessel.source,
            destination: vessel.destination,
            seed: vessel.seed,
            sourceSeed: vessel.sourceSeed,
            sourceFundamentalHz: vessel.sourceFundamentalHz,
            rootVesselID: vessel.rootVesselID,
            sourceFamily: vessel.sourceFamily,
            processors: processors,
            hasAuxiliaryGenerator: vessel.hasAuxiliaryGenerator,
            parentVesselIDs: vessel.parentVesselIDs
        )
        markTrackDirty(track)
        selectedVesselID = vessel.id
        status = "TRACK \(track + 1) · PAD \(pad.column + 1) \(current.kind.rawValue.uppercased()) RANDOMIZED"
        synchronizeAudio()
    }

    private func randomizeGenerator(row: Int) {
        if session.generatorLocks[row] != nil || session.chainLocks[row] != nil {
            status = "TRACK \(row + 1) · GENERATOR IS LOCKED"
            return
        }
        guard let root = session.vessels.first(where: {
            $0.parentVesselIDs.isEmpty && $0.source.row == row
        }) else {
            status = "TRACK \(row + 1) · NO GENERATOR TO RANDOMIZE"
            return
        }
        let newSourceSeed = session.drawSeed()
        session.vessels = session.vessels.map { vessel in
            guard vessel.source.row == row else { return vessel }
            return VesselGraph(
                id: vessel.id,
                source: vessel.source,
                destination: vessel.destination,
                seed: vessel.seed,
                sourceSeed: newSourceSeed,
                sourceFundamentalHz: vessel.sourceFundamentalHz,
                rootVesselID: vessel.rootVesselID,
                sourceFamily: vessel.sourceFamily,
                processors: vessel.processors,
                hasAuxiliaryGenerator: vessel.hasAuxiliaryGenerator,
                parentVesselIDs: vessel.parentVesselIDs
            )
        }
        markTrackDirty(row)
        selectedVesselID = root.id
        status = "TRACK \(row + 1) · \(displayName(root.sourceFamily)) GENERATOR RANDOMIZED"
        synchronizeAudio()
    }

    private func toggleChainLock(row: Int, endpoint: PadCoordinate) {
        guard let generatorLock = session.generatorLocks[row] else {
            status = "TRACK \(row + 1) · LOCK THE GENERATOR FIRST"
            return
        }
        let trackVessels = session.vessels.filter { $0.source.row == row }
        if let existing = session.chainLocks[row],
           existing.endpointColumn == endpoint.column,
           existing.vessels == trackVessels {
            session.chainLocks.removeValue(forKey: row)
            markProjectDirty()
            status = "TRACK \(row + 1) · CHAIN UNLOCKED"
            return
        }
        guard !trackVessels.isEmpty else {
            status = "TRACK \(row + 1) · NO CHAIN TO LOCK"
            return
        }
        session.chainLocks[row] = TrackChainLock(
            vessels: trackVessels,
            endpointColumn: endpoint.column,
            generatorLock: generatorLock
        )
        markProjectDirty()
        status = "TRACK \(row + 1) · CHAIN LOCKED THROUGH PAD \(endpoint.column + 1)"
    }

    private func restoreLockedChain(
        _ chainLock: TrackChainLock,
        row: Int,
        destination: PadCoordinate
    ) {
        markTrackDirty(row)
        session.vessels.removeAll { $0.source.row == row }
        session.vessels.append(contentsOf: chainLock.vessels)
        var terminal = chainLock.vessels.last
        var addedProcessors = 0
        if destination.column > chainLock.endpointColumn, let parent = terminal {
            let extensionSegment = graphFactory.make(
                source: parent.destination,
                destination: destination,
                seed: session.drawSeed(),
                parentVessels: [parent],
                existingProcessors: chainLock.vessels.flatMap(\.processors),
                generatorLock: nil,
                harmonicAnchor: session.harmonicAnchor
            )
            session.vessels.append(extensionSegment)
            terminal = extensionSegment
            addedProcessors = extensionSegment.processors.count
        }
        selectedVesselID = terminal?.id
        awakenedPad = nil
        status = addedProcessors == 0
            ? "TRACK \(row + 1) · LOCKED CHAIN RESTORED"
            : "TRACK \(row + 1) · LOCK RESTORED · +\(addedProcessors) PROCESSORS"
        synchronizeAudio()
    }

    private func adjustTrack(_ track: Int, with pad: PadCoordinate) {
        markTrackDirty(track)
        var adjustedSendName: String?
        switch pad.row {
        case TrackMixer.volumePadRow:
            let step = LaunchpadFader.nextUnipolarStep(
                currentValue: trackVolumes[track], padColumn: pad.column
            )
            trackVolumes[track] = LaunchpadFader.unipolarValue(forStep: step)
        case TrackMixer.panPadRow:
            let step = LaunchpadFader.nextBipolarStep(
                currentValue: trackPans[track], padColumn: pad.column
            )
            trackPans[track] = LaunchpadFader.bipolarValue(forStep: step)
        case TrackMixer.reverbPadRow:
            let step = LaunchpadFader.nextUnipolarStep(
                currentValue: trackSends[track].reverb, padColumn: pad.column
            )
            trackSends[track].reverb = LaunchpadFader.unipolarValue(forStep: step)
            adjustedSendName = "REVERB"
        case TrackMixer.delayPadRow:
            let step = LaunchpadFader.nextUnipolarStep(
                currentValue: trackSends[track].delay, padColumn: pad.column
            )
            trackSends[track].delay = LaunchpadFader.unipolarValue(forStep: step)
            adjustedSendName = "DELAY"
        case TrackMixer.saturationPadRow:
            let step = LaunchpadFader.nextUnipolarStep(
                currentValue: trackSends[track].saturation, padColumn: pad.column
            )
            trackSends[track].saturation = LaunchpadFader.unipolarValue(forStep: step)
            adjustedSendName = "SATURATION + OVERDRIVE"
        case TrackMixer.crusherPadRow:
            let step = LaunchpadFader.nextUnipolarStep(
                currentValue: trackSends[track].crusher, padColumn: pad.column
            )
            trackSends[track].crusher = LaunchpadFader.unipolarValue(forStep: step)
            adjustedSendName = "BIT CRUSHER + DECIMATOR"
        case TrackMixer.gatePadRow:
            let step = LaunchpadFader.nextBipolarStep(
                currentValue: trackGates[track], padColumn: pad.column
            )
            trackGates[track] = LaunchpadFader.bipolarValue(forStep: step)
        default:
            status = "TRACK \(track + 1) · UNUSED CONTROL"
            return
        }
        if let adjustedSendName {
            let value = switch pad.row {
            case TrackMixer.reverbPadRow: trackSends[track].reverb
            case TrackMixer.delayPadRow: trackSends[track].delay
            case TrackMixer.saturationPadRow: trackSends[track].saturation
            default: trackSends[track].crusher
            }
            status = "TRACK \(track + 1) · \(adjustedSendName) SEND \(Int((value * 100).rounded()))%"
        } else {
            status = mixerStatus(for: track)
        }
        let volume = trackVolumes[track]
        let pan = trackPans[track]
        let sends = trackSends[track]
        let gate = trackGates[track]
        Task { @MainActor [weak self] in
            do {
                try await self?.audioEngine.setTrackMix(
                    row: track,
                    volume: volume,
                    pan: pan,
                    sends: sends,
                    gate: gate
                )
            } catch {
                self?.status = "MIXER ERROR · \(error.localizedDescription.uppercased())"
            }
        }
    }

    private func adjustMasterEffects(with pad: PadCoordinate) {
        guard let control = MasterEffectControl(padRow: pad.row) else { return }
        markProjectDirty()
        let step = LaunchpadFader.nextUnipolarStep(
            currentValue: masterEffects.value(for: control),
            padColumn: pad.column
        )
        masterEffects.setValue(
            LaunchpadFader.unipolarValue(forStep: step),
            for: control
        )
        let label: String = switch control {
        case .reverbSize: "REVERB SIZE"
        case .reverbDecay: "REVERB DECAY"
        case .reverbTone: "REVERB TONE"
        case .reverbMotion: "REVERB MOTION"
        case .delayTime: "DELAY TIME"
        case .delayFeedback: "DELAY FEEDBACK"
        case .delayTone: "DELAY TONE"
        case .delayWidth: "DELAY WIDTH"
        }
        status = "\(label) · \(Int((masterEffects.value(for: control) * 100).rounded()))%"
        let parameters = masterEffects
        Task { @MainActor [weak self] in
            do {
                try await self?.audioEngine.setMasterEffects(parameters)
            } catch {
                self?.status = "MASTER FX ERROR · \(error.localizedDescription.uppercased())"
            }
        }
    }

    private func adjustDestructiveEffects(with pad: PadCoordinate) {
        guard let control = DestructiveEffectControl(padRow: pad.row) else { return }
        markProjectDirty()
        let step = LaunchpadFader.nextUnipolarStep(
            currentValue: destructiveEffects.value(for: control),
            padColumn: pad.column
        )
        destructiveEffects.setValue(
            LaunchpadFader.unipolarValue(forStep: step),
            for: control
        )
        let label: String = switch control {
        case .saturationDrive: "SATURATION DRIVE"
        case .saturationCurve: "SATURATION CURVE"
        case .saturationTone: "SATURATION TONE"
        case .saturationBody: "SATURATION BODY"
        case .crusherBits: "CRUSHER BIT DEPTH"
        case .crusherRate: "DECIMATOR SAMPLE RATE"
        case .crusherJitter: "DECIMATOR CLOCK JITTER"
        case .crusherTone: "CRUSHER TONE"
        }
        status = "\(label) · \(Int((destructiveEffects.value(for: control) * 100).rounded()))%"
        let parameters = destructiveEffects
        Task { @MainActor [weak self] in
            do {
                try await self?.audioEngine.setDestructiveEffects(parameters)
            } catch {
                self?.status = "DESTRUCTIVE FX ERROR · \(error.localizedDescription.uppercased())"
            }
        }
    }

    private func saveScene(track: Int, slot: Int) {
        let vessels = session.vessels.filter { $0.source.row == track }
        guard !vessels.isEmpty else {
            status = "TRACK \(track + 1) · CANNOT SAVE AN EMPTY SCENE"
            return
        }
        markProjectDirty()
        let scene = TrackScene(
            vessels: vessels,
            volume: trackVolumes[track],
            pan: trackPans[track],
            sends: trackSends[track],
            gate: trackGates[track],
            generatorLock: session.generatorLocks[track],
            chainLock: session.chainLocks[track],
            harmonicAnchor: session.harmonicAnchor
        )
        sceneBank.setScene(scene, track: track, slot: slot)
        activeSceneSlots[track] = slot
        status = "TRACK \(track + 1) · SCENE \(slot + 1) SAVED"
    }

    private func loadScene(track: Int, slot: Int) {
        guard let scene = sceneBank.scene(track: track, slot: slot) else {
            status = "TRACK \(track + 1) · SCENE \(slot + 1) EMPTY"
            return
        }
        markProjectDirty()
        session.vessels.removeAll { $0.source.row == track }
        session.vessels.append(contentsOf: scene.vessels)
        trackVolumes[track] = scene.volume
        trackPans[track] = scene.pan
        trackSends[track] = scene.sends
        trackGates[track] = scene.gate
        if let generatorLock = scene.generatorLock {
            session.generatorLocks[track] = generatorLock
        } else {
            session.generatorLocks.removeValue(forKey: track)
        }
        if let chainLock = scene.chainLock {
            session.chainLocks[track] = chainLock
        } else {
            session.chainLocks.removeValue(forKey: track)
        }
        if session.harmonicAnchor == nil {
            session.harmonicAnchor = scene.harmonicAnchor
        }
        selectedVesselID = scene.vessels.last?.id
        awakenedPad = nil
        activeSceneSlots[track] = slot
        status = "TRACK \(track + 1) · SCENE \(slot + 1) LOADED"
        sceneRecallGeneration[track] &+= 1
        restoreSceneAudio(track: track, generation: sceneRecallGeneration[track])
    }

    private func restoreSceneAudio(track: Int, generation: UInt64) {
        let vessels = session.vessels
        let volume = trackVolumes[track]
        let pan = trackPans[track]
        let sends = trackSends[track]
        let gate = trackGates[track]
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.audioEngine.synchronize(vessels)
                try await Task.sleep(for: .milliseconds(260))
                guard self.sceneRecallGeneration[track] == generation else { return }
                try await self.audioEngine.setTrackMix(
                    row: track,
                    volume: volume,
                    pan: pan,
                    sends: sends,
                    gate: gate
                )
            } catch {
                self.status = "SCENE ERROR · \(error.localizedDescription.uppercased())"
            }
        }
    }

    private func saveGlobalScene(slot: Int) {
        let scene = GlobalSceneState(
            session: session,
            trackVolumes: trackVolumes,
            trackPans: trackPans,
            trackSends: trackSends,
            trackGates: trackGates,
            activeTrackSceneSlots: activeSceneSlots,
            masterEffects: masterEffects,
            destructiveEffects: destructiveEffects
        )
        let previousBank = globalSceneBank
        let previousActiveSlot = activeGlobalSceneSlot
        let projectSlotForPersistence = activeProjectSlot
        let previousStoredProject = projectSlotForPersistence.flatMap {
            projectBank.project(slot: $0)
        }
        globalSceneRecallGeneration &+= 1
        globalSceneBank.setScene(scene, slot: slot)
        activeGlobalSceneSlot = slot
        markProjectDirty()
        do {
            // A scene belongs to the active project and is persisted immediately,
            // while the project's own main recall snapshot remains untouched.
            if let projectSlot = projectSlotForPersistence,
               let storedProject = previousStoredProject {
                let updatedProject = ProjectState(
                    session: storedProject.session,
                    trackVolumes: storedProject.trackVolumes,
                    trackPans: storedProject.trackPans,
                    trackSends: storedProject.trackSends,
                    trackGates: storedProject.trackGates,
                    sceneBank: storedProject.sceneBank,
                    activeSceneSlots: storedProject.activeSceneSlots,
                    masterEffects: storedProject.masterEffects,
                    destructiveEffects: storedProject.destructiveEffects,
                    globalSceneBank: globalSceneBank,
                    activeGlobalSceneSlot: slot
                )
                projectBank.setProject(updatedProject, slot: projectSlot)
                try projectStore.save(projectBank)
            }
            status = activeProjectSlot == nil
                ? "GLOBAL SCENE \(slot + 1) SAVED · SAVE A PROJECT TO KEEP"
                : "GLOBAL SCENE \(slot + 1) SAVED"
            startGlobalSceneSaveConfirmation(slot: slot)
        } catch {
            globalSceneBank = previousBank
            activeGlobalSceneSlot = previousActiveSlot
            if let projectSlot = projectSlotForPersistence,
               let previousStoredProject {
                projectBank.setProject(previousStoredProject, slot: projectSlot)
            }
            status = "GLOBAL SCENE SAVE ERROR · \(error.localizedDescription.uppercased())"
        }
    }

    private func loadGlobalScene(slot: Int) {
        guard let scene = globalSceneBank.scene(slot: slot) else {
            status = "GLOBAL SCENE \(slot + 1) EMPTY"
            return
        }
        guard scene.hasValidTrackState else {
            status = "GLOBAL SCENE \(slot + 1) · INVALID STATE"
            return
        }

        markProjectDirty()
        globalSceneRecallGeneration &+= 1
        let generation = globalSceneRecallGeneration
        for track in sceneRecallGeneration.indices { sceneRecallGeneration[track] &+= 1 }
        session = scene.session
        trackVolumes = scene.trackVolumes
        trackPans = scene.trackPans
        trackSends = scene.trackSends
        trackGates = scene.trackGates
        activeSceneSlots = scene.activeTrackSceneSlots
        masterEffects = scene.masterEffects
        destructiveEffects = scene.destructiveEffects
        selectedVesselID = session.vessels.last?.id
        awakenedPad = nil
        activeGlobalSceneSlot = slot
        status = "GLOBAL SCENE \(slot + 1) LOADED"

        let vessels = session.vessels
        let volumes = trackVolumes
        let pans = trackPans
        let sends = trackSends
        let gates = trackGates
        let effects = masterEffects
        let destructive = destructiveEffects
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.audioEngine.synchronize(vessels)
                try await Task.sleep(for: .milliseconds(260))
                guard self.globalSceneRecallGeneration == generation else { return }
                for track in 0..<8 {
                    try await self.audioEngine.setTrackMix(
                        row: track,
                        volume: volumes[track],
                        pan: pans[track],
                        sends: sends[track],
                        gate: gates[track]
                    )
                }
                try await self.audioEngine.setMasterEffects(effects)
                try await self.audioEngine.setDestructiveEffects(destructive)
            } catch {
                self.status = "GLOBAL SCENE ERROR · \(error.localizedDescription.uppercased())"
            }
        }
    }

    private func startGlobalSceneSaveConfirmation(slot: Int) {
        globalSceneSaveConfirmationTask?.cancel()
        globalSceneSaveConfirmationSlot = slot
        globalSceneSaveConfirmationBright = true
        globalSceneSaveConfirmationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<5 {
                try? await Task.sleep(for: .milliseconds(115))
                guard !Task.isCancelled else { return }
                self.globalSceneSaveConfirmationBright.toggle()
                self.renderController()
            }
            try? await Task.sleep(for: .milliseconds(115))
            guard !Task.isCancelled else { return }
            self.globalSceneSaveConfirmationSlot = nil
            self.globalSceneSaveConfirmationBright = false
            self.renderController()
        }
    }

    private func saveProject(slot: Int) {
        let project = ProjectState(
            session: session,
            trackVolumes: trackVolumes,
            trackPans: trackPans,
            trackSends: trackSends,
            trackGates: trackGates,
            sceneBank: sceneBank,
            activeSceneSlots: activeSceneSlots,
            masterEffects: masterEffects,
            destructiveEffects: destructiveEffects,
            globalSceneBank: globalSceneBank,
            activeGlobalSceneSlot: activeGlobalSceneSlot
        )
        projectBank.setProject(project, slot: slot)
        do {
            try projectStore.save(projectBank)
            activeProjectSlot = slot
            status = "PROJECT \(slot + 1) SAVED"
            startProjectSaveConfirmation(slot: slot)
        } catch {
            status = "PROJECT SAVE ERROR · \(error.localizedDescription.uppercased())"
        }
    }

    private func startProjectSaveConfirmation(slot: Int) {
        projectSaveConfirmationTask?.cancel()
        projectSaveConfirmationSlot = slot
        projectSaveConfirmationBright = true
        projectSaveConfirmationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Three quick white/red alternations acknowledge a successful disk
            // write, then the slot returns to its persistent active-project red.
            for _ in 0..<5 {
                try? await Task.sleep(for: .milliseconds(115))
                guard !Task.isCancelled else { return }
                self.projectSaveConfirmationBright.toggle()
                self.renderController()
            }
            try? await Task.sleep(for: .milliseconds(115))
            guard !Task.isCancelled else { return }
            self.projectSaveConfirmationSlot = nil
            self.projectSaveConfirmationBright = false
            self.renderController()
        }
    }

    private func loadProject(slot: Int) {
        guard let project = projectBank.project(slot: slot) else {
            status = "PROJECT \(slot + 1) EMPTY"
            return
        }
        guard project.isSupportedFormat,
              project.hasValidTrackState else {
            status = "PROJECT \(slot + 1) · UNSUPPORTED FORMAT"
            return
        }

        projectRecallGeneration &+= 1
        globalSceneRecallGeneration &+= 1
        let generation = projectRecallGeneration
        for track in sceneRecallGeneration.indices { sceneRecallGeneration[track] &+= 1 }
        session = project.session
        trackVolumes = project.trackVolumes
        trackPans = project.trackPans
        trackSends = project.trackSends
        trackGates = project.trackGates
        sceneBank = project.sceneBank
        activeSceneSlots = project.activeSceneSlots
        masterEffects = project.masterEffects
        destructiveEffects = project.destructiveEffects
        globalSceneBank = project.globalSceneBank
        activeGlobalSceneSlot = project.activeGlobalSceneSlot
        selectedVesselID = session.vessels.last?.id
        awakenedPad = nil
        activeProjectSlot = slot
        status = "PROJECT \(slot + 1) LOADED"

        let vessels = session.vessels
        let volumes = trackVolumes
        let pans = trackPans
        let sends = trackSends
        let gates = trackGates
        let effects = masterEffects
        let destructive = destructiveEffects
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.audioEngine.synchronize(vessels)
                try await Task.sleep(for: .milliseconds(260))
                guard self.projectRecallGeneration == generation else { return }
                for track in 0..<8 {
                    try await self.audioEngine.setTrackMix(
                        row: track,
                        volume: volumes[track],
                        pan: pans[track],
                        sends: sends[track],
                        gate: gates[track]
                    )
                }
                try await self.audioEngine.setMasterEffects(effects)
                try await self.audioEngine.setDestructiveEffects(destructive)
            } catch {
                self.status = "PROJECT LOAD ERROR · \(error.localizedDescription.uppercased())"
            }
        }
    }

    private func markTrackDirty(_ track: Int) {
        sceneRecallGeneration[track] &+= 1
        activeSceneSlots.removeValue(forKey: track)
        markProjectDirty()
    }

    private func markProjectDirty() {
        projectRecallGeneration &+= 1
        // Edits change the in-memory machine state, but the loaded project keeps
        // its identity until another project is loaded or saved. Saving is still
        // the only operation that writes those edits to the active slot.
    }

    private func mixerStatus(for track: Int) -> String {
        let volume = Int((trackVolumes[track] * 100).rounded())
        let pan = trackPans[track]
        let panLabel: String
        if abs(pan) < 0.000_001 {
            panLabel = "C"
        } else if pan < 0 {
            panLabel = "L\(Int((abs(pan) * 100).rounded()))"
        } else {
            panLabel = "R\(Int((pan * 100).rounded()))"
        }
        let sends = trackSends[track]
        let gate = trackGates[track]
        let gateMultiplier = TrackMixer.gateClockMultiplier(for: gate)
        let gateLabel: String
        if gateMultiplier == 0 {
            gateLabel = "OFF"
        } else if gateMultiplier < 1 {
            gateLabel = "÷\(Int((1 / gateMultiplier).rounded()))"
        } else {
            gateLabel = "×\(Int(gateMultiplier.rounded()))"
        }
        return "EDIT TRACK \(track + 1) · V\(volume) · P\(panLabel) · "
            + "GT\(gateLabel) "
            + "RV\(Int((sends.reverb * 100).rounded())) "
            + "DL\(Int((sends.delay * 100).rounded())) "
            + "ST\(Int((sends.saturation * 100).rounded())) "
            + "CR\(Int((sends.crusher * 100).rounded()))"
    }

    private func renderController() {
        launchpad?.render(
            vessels: session.vessels,
            awakenedPad: awakenedPad,
            selectedVesselID: selectedVesselID,
            hubPulseBright: hubPulseBright,
            editingTrack: editingTrack,
            trackVolumes: trackVolumes,
            trackPans: trackPans,
            trackSends: trackSends,
            trackGates: trackGates,
            projectViewOpen: projectViewOpen,
            occupiedProjectSlots: projectBank.occupiedSlots,
            activeProjectSlot: activeProjectSlot,
            projectSaveConfirmationSlot: projectSaveConfirmationSlot,
            projectSaveConfirmationBright: projectSaveConfirmationBright,
            globalSceneViewOpen: globalSceneViewOpen,
            occupiedGlobalSceneSlots: globalSceneBank.occupiedSlots,
            activeGlobalSceneSlot: activeGlobalSceneSlot,
            globalSceneSaveConfirmationSlot: globalSceneSaveConfirmationSlot,
            globalSceneSaveConfirmationBright: globalSceneSaveConfirmationBright,
            masterEffectsViewOpen: masterEffectsViewOpen,
            masterEffects: masterEffects,
            destructiveEffectsViewOpen: destructiveEffectsViewOpen,
            destructiveEffects: destructiveEffects,
            occupiedSceneSlots: editingTrack.map {
                sceneBank.occupiedSlots(track: $0)
            } ?? [],
            activeSceneSlot: editingTrack.flatMap { activeSceneSlots[$0] },
            generatorLockRows: Set(session.generatorLocks.keys),
            chainLockEndpoints: session.chainLocks.mapValues(\.endpointColumn),
            shiftHeld: shiftHeld,
            processorRandomizeTrack: processorRandomizeTrack
        )
    }

    func isGeneratorLocked(row: Int) -> Bool {
        session.generatorLocks[row] != nil
    }

    func projectOccupied(slot: Int) -> Bool {
        projectBank.project(slot: slot) != nil
    }

    func globalSceneOccupied(slot: Int) -> Bool {
        globalSceneBank.scene(slot: slot) != nil
    }

    func chainLockEndpoint(row: Int) -> Int? {
        session.chainLocks[row]?.endpointColumn
    }

    func isChainLockEndpoint(_ pad: PadCoordinate) -> Bool {
        session.chainLocks[pad.row]?.endpointColumn == pad.column
    }

    func sceneOccupied(track: Int, slot: Int) -> Bool {
        sceneBank.scene(track: track, slot: slot) != nil
    }

    func vesselTouching(_ pad: PadCoordinate) -> VesselGraph? {
        session.vessels.last {
            $0.source.gridRoute(to: $0.destination).contains(pad)
        }
    }

    func isTrackBoundary(_ pad: PadCoordinate) -> Bool {
        let parentIDs = Set(session.vessels.flatMap(\.parentVesselIDs))
        return session.vessels.contains { vessel in
            (vessel.parentVesselIDs.isEmpty && vessel.source == pad)
                || (!parentIDs.contains(vessel.id) && vessel.destination == pad)
        }
    }

    private func selectVessel(at pad: PadCoordinate) {
        guard let vessel = vesselTouching(pad) else {
            status = "LONG-PRESS THE LEFT PAD OF AN EMPTY TRACK"
            return
        }
        selectedVesselID = vessel.id
        status = "\(displayName(vessel.sourceFamily)) · \(vessel.processors.count) STAGES"
    }

    private func currentTrackEndpoint(row: Int) -> PadCoordinate? {
        let parentIDs = Set(session.vessels.flatMap(\.parentVesselIDs))
        return session.vessels
            .last { $0.source.row == row && !parentIDs.contains($0.id) }?
            .destination
    }

    private func padLabel(_ pad: PadCoordinate) -> String {
        "\(Character(UnicodeScalar(65 + pad.column)!))\(pad.row + 1)"
    }

    private func displayName(_ source: SourceFamily) -> String {
        source.rawValue
            .unicodeScalars
            .reduce(into: "") { result, scalar in
                if CharacterSet.uppercaseLetters.contains(scalar) { result.append(" ") }
                result.unicodeScalars.append(scalar)
            }
            .uppercased()
    }

    private func rejectionMessage(_ violation: TrackRuleViolation, row: Int) -> String {
        switch violation {
        case .generatorMustBeHeld:
            "TRACK \(row + 1) · HOLD THE LEFTMOST GENERATOR"
        case .mustStayOnSameTrack:
            "PARALLEL MODE · CHAINS CANNOT CHANGE ROWS"
        case .targetMustBeToRightOfGenerator:
            "TRACK \(row + 1) · SELECT A PROCESSOR PAD TO THE RIGHT"
        }
    }
}
