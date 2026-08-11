import Foundation
import VascularCore

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("Core check failed: \(message)") }
}

let factory = VesselGraphFactory()
var seededSessionA = VascularSession(nextSeed: 123_456)
var seededSessionB = VascularSession(nextSeed: 123_456)
let drawnA = (0..<8).map { _ in seededSessionA.drawSeed() }
let drawnB = (0..<8).map { _ in seededSessionB.drawSeed() }
require(drawnA == drawnB, "explicit session seeding is not reproducible for diagnostics")
require(Set(drawnA).count == drawnA.count, "session seed stream repeated a value")
require(zip(drawnA, drawnA.dropFirst()).allSatisfy { pair in pair.1 != pair.0 &+ 1 },
        "session exposed sequential seeds to the sound engine")
let freshSessionA = VascularSession()
let freshSessionB = VascularSession()
require(freshSessionA.nextSeed != freshSessionB.nextSeed,
        "fresh application sessions reused the same entropy seed")
let source = PadCoordinate(row: 0, column: 0)
let destination = PadCoordinate(row: 0, column: 3)
let first = factory.make(source: source, destination: destination, seed: 42)
let second = factory.make(source: source, destination: destination, seed: 42)

require(first.sourceFamily == second.sourceFamily, "source selection is not deterministic")
require(first.processors == second.processors, "processor selection is not deterministic")
let lockedGenerator = GeneratorLock(
    sourceSeed: first.sourceSeed,
    sourceFamily: first.sourceFamily,
    fundamentalHz: first.sourceFundamentalHz
)
let recreatedFromLock = factory.make(
    source: source,
    destination: destination,
    seed: 9_876_543,
    generatorLock: lockedGenerator
)
require(recreatedFromLock.sourceSeed == first.sourceSeed,
        "generator lock did not preserve synthesis identity")
require(recreatedFromLock.sourceFamily == first.sourceFamily,
        "generator lock did not preserve the source family")
require(recreatedFromLock.sourceFundamentalHz == first.sourceFundamentalHz,
        "generator lock did not preserve the fundamental")
require(recreatedFromLock.processors != first.processors,
        "generator lock incorrectly froze the processor chain")
var lockSession = VascularSession(nextSeed: 99)
lockSession.generatorLocks[0] = lockedGenerator
let harmonicAnchor = HarmonicAnchor(
    fundamentalHz: first.sourceFundamentalHz,
    sourceSeed: first.sourceSeed
)
lockSession.harmonicAnchor = harmonicAnchor
let lockRoundTrip = try! JSONDecoder().decode(
    VascularSession.self,
    from: JSONEncoder().encode(lockSession)
)
require(lockRoundTrip == lockSession, "generator assignment did not survive session coding")
let legacySession = try! JSONDecoder().decode(
    VascularSession.self,
    from: Data(#"{"vessels":[],"nextSeed":99}"#.utf8)
)
require(legacySession.generatorLocks.isEmpty,
        "a legacy session without generator locks did not decode safely")
require(legacySession.chainLocks.isEmpty,
        "a legacy session without chain locks did not decode safely")
require(legacySession.harmonicAnchor == nil,
        "a legacy session unexpectedly acquired a harmonic anchor")
let relatedRoots = (0..<64).map { index in
    factory.make(
        source: PadCoordinate(row: index % 8, column: 0),
        destination: PadCoordinate(row: index % 8, column: 2),
        seed: UInt64(80_000 + index),
        harmonicAnchor: harmonicAnchor
    )
}
require(relatedRoots.allSatisfy { (29...220).contains($0.sourceFundamentalHz) },
        "a related generator fell outside the curated fundamental register")
func octaveClass(_ ratio: Double) -> Double {
    var value = ratio
    while value < 1 { value *= 2 }
    while value >= 2 { value *= 0.5 }
    return value
}
let allowedClasses = SourcePitch.harmonicRatios.map(octaveClass)
require(relatedRoots.allSatisfy { root in
    let relationship = octaveClass(root.sourceFundamentalHz / harmonicAnchor.fundamentalHz)
    return allowedClasses.contains { abs($0 - relationship) < 0.000_000_1 }
}, "a generated source escaped the session's just-intonation field")
require(first.processors.count == 3, "one processor was not created per traversed pad")
require(
    first.processors.map(\.coordinate) == [
        PadCoordinate(row: 0, column: 1),
        PadCoordinate(row: 0, column: 2),
        PadCoordinate(row: 0, column: 3),
    ],
    "processors are not attached to their physical track pads"
)
require(
    first.processors.allSatisfy { (0.34...0.9).contains($0.intensity) },
    "a processor lies outside its curated intensity range"
)

let destructiveKinds: Set<ProcessorKind> = [.waveshaper, .overdrive, .bitCrusher]
let paletteGraphs = (1...128).map { seed in
    factory.make(
        source: PadCoordinate(row: seed % 8, column: 0),
        destination: PadCoordinate(row: seed % 8, column: 7),
        seed: UInt64(seed)
    )
}
require(paletteGraphs.allSatisfy {
    $0.processors.filter { destructiveKinds.contains($0.kind) }.count <= 1
}, "a track received multiple destructive processors")
require(paletteGraphs.allSatisfy {
    $0.processors.prefix(2).allSatisfy { !destructiveKinds.contains($0.kind) }
}, "a destructive processor erased source identity at the start of a track")
require(Set(paletteGraphs.flatMap { $0.processors.map(\.kind) }).count >= 13,
        "curation collapsed the processor vocabulary")
let archetypeGraphs = (0..<7).map { palette in
    factory.make(
        source: PadCoordinate(row: palette, column: 0),
        destination: PadCoordinate(row: palette, column: 7),
        seed: UInt64(70_000 + palette)
    )
}
require(Set(archetypeGraphs.map { $0.processors.map(\.kind) }).count == 7,
        "root processing archetypes produced identical chains")

var occupiedFamilies: Set<SourceFamily> = []
var distinctRoots: [VesselGraph] = []
for row in 0..<8 {
    let root = factory.make(
        source: PadCoordinate(row: row, column: 0),
        destination: PadCoordinate(row: row, column: 2),
        seed: UInt64(10_000 + row),
        avoidingSourceFamilies: occupiedFamilies
    )
    occupiedFamilies.insert(root.sourceFamily)
    distinctRoots.append(root)
}
require(Set(distinctRoots.map(\.sourceFamily)).count == 8,
        "simultaneous tracks reused source families despite available alternatives")

let physicalFamilies: Set<SourceFamily> = [
    .karplusStrong, .preparedString, .struckPlate, .struckMembrane,
    .bowedBody, .reedBore, .glassBowl, .woodenBody,
]
require(SourceFamily.allCases.count >= 20,
        "the source vocabulary lost physical/acoustic archetypes")
let broadSourceDraw = (1...512).map { seed in
    factory.make(
        source: PadCoordinate(row: seed % 8, column: 0),
        destination: PadCoordinate(row: seed % 8, column: 1),
        seed: UInt64(900_000 + seed)
    ).sourceFamily
}
require(physicalFamilies.isSubset(of: Set(broadSourceDraw)),
        "one or more physical/acoustic source families cannot enter normal selection")

let empty = TrackTopology(vessels: [])
require(
    empty.managementAction(from: source, to: destination) == .create,
    "left-edge gesture did not create a track root"
)
require(
    empty.managementAction(
        from: PadCoordinate(row: 0, column: 1),
        to: PadCoordinate(row: 0, column: 3)
    ) == .rejected(.generatorMustBeHeld),
    "a non-generator pad was accepted as the management handle"
)
require(
    empty.managementAction(
        from: source,
        to: PadCoordinate(row: 1, column: 3)
    ) == .rejected(.mustStayOnSameTrack),
    "a vessel was allowed to change rows"
)
require(
    empty.managementAction(from: source, to: source)
        == .rejected(.targetMustBeToRightOfGenerator),
    "the generator was accepted as its own endpoint"
)

let oneTrack = TrackTopology(vessels: [first])
let extensionDestination = PadCoordinate(row: 0, column: 6)
require(
    oneTrack.managementAction(from: source, to: extensionDestination)
        == .extend(parent: first),
    "generator gesture did not offer a linear extension"
)
require(
    oneTrack.managementAction(from: source, to: PadCoordinate(row: 0, column: 2))
        == .trim,
    "generator gesture did not offer a trim before the endpoint"
)
require(
    oneTrack.managementAction(from: source, to: destination) == .clear,
    "generator-to-endpoint gesture did not clear the track"
)
require(
    oneTrack.managementAction(
        from: PadCoordinate(row: 0, column: 2),
        to: extensionDestination
    ) == .rejected(.generatorMustBeHeld),
    "an intermediate processor was accepted as the management handle"
)

let extensionSegment = factory.make(
    source: first.destination,
    destination: extensionDestination,
    seed: 43,
    parentVessels: [first]
)
require(extensionSegment.isExtension, "track segment was not marked as an extension")
require(extensionSegment.sourceFamily == first.sourceFamily, "extension changed source family")
require(extensionSegment.sourceSeed == first.sourceSeed, "extension copied source identity")
require(extensionSegment.sourceFundamentalHz == first.sourceFundamentalHz,
        "extension changed the source's harmonic role")
require(extensionSegment.rootVesselID == first.id, "extension changed track lineage")
require(extensionSegment.processors.count == 3, "extension did not append each new pad")
require(
    extensionSegment.processors.first?.coordinate != extensionSegment.source,
    "endpoint processed twice"
)

let extendedTopology = TrackTopology(vessels: [first, extensionSegment])
let chainLock = TrackChainLock(
    vessels: [first, extensionSegment],
    endpointColumn: extensionSegment.destination.column,
    generatorLock: lockedGenerator
)
require(chainLock.endpointColumn == 6, "chain lock lost its endpoint")
require(chainLock.vessels.flatMap(\.processors)
            == [first, extensionSegment].flatMap(\.processors),
        "chain lock changed exact processor parameters or ordering")
require(chainLock.matchesLivePrefix(in: [first, extensionSegment], row: 0),
        "an unchanged locked chain was not recognized as its exact live prefix")
let unlockedSuffix = factory.make(
    source: extensionSegment.destination,
    destination: PadCoordinate(row: 0, column: 7),
    seed: 44_444,
    parentVessels: [extensionSegment],
    existingProcessors: [first, extensionSegment].flatMap(\.processors)
)
require(chainLock.matchesLivePrefix(
    in: [first, extensionSegment, unlockedSuffix],
    row: 0
), "an unlocked suffix incorrectly invalidated the permanent locked prefix")
require(
    extendedTopology.managementAction(
        from: source,
        to: PadCoordinate(row: 0, column: 7)
    ) == .extend(parent: extensionSegment),
    "a complete locked prefix could not be extended farther to the right"
)
let shortenedInsideLock = extendedTopology.trimmingTrack(
    row: 0,
    endingAt: PadCoordinate(row: 0, column: 4)
)
require(!chainLock.matchesLivePrefix(in: shortenedInsideLock, row: 0),
        "a chain shortened inside the lock was mistaken for a complete locked prefix")
var chainLockSession = VascularSession(
    vessels: [],
    nextSeed: 101,
    generatorLocks: [0: lockedGenerator],
    chainLocks: [0: chainLock],
    harmonicAnchor: harmonicAnchor
)
let chainLockData = try JSONEncoder().encode(chainLockSession)
let decodedChainLockSession = try JSONDecoder().decode(
    VascularSession.self,
    from: chainLockData
)
require(decodedChainLockSession == chainLockSession,
        "exact chain lock did not survive session coding")
let trimInsideExtension = extendedTopology.trimmingTrack(
    row: 0,
    endingAt: PadCoordinate(row: 0, column: 4)
)
require(trimInsideExtension.count == 2, "trim discarded the retained extension segment")
require(trimInsideExtension[1].id == extensionSegment.id, "trim changed segment identity")
require(trimInsideExtension[1].destination.column == 4, "trim endpoint is incorrect")
require(trimInsideExtension[1].processors == Array(extensionSegment.processors.prefix(1)),
        "trim changed the retained processor")

let trimInsideRoot = extendedTopology.trimmingTrack(
    row: 0,
    endingAt: PadCoordinate(row: 0, column: 2)
)
require(trimInsideRoot.count == 1, "trim left disconnected downstream segments")
require(trimInsideRoot[0].id == first.id, "trim restarted the root vessel")
require(trimInsideRoot[0].rootVesselID == first.id, "trim changed source lineage")
require(trimInsideRoot[0].sourceFundamentalHz == first.sourceFundamentalHz,
        "trim changed the retained generator's fundamental")
require(trimInsideRoot[0].processors == Array(first.processors.prefix(2)),
        "trim changed retained processor identities")

let parallel = factory.make(
    source: PadCoordinate(row: 1, column: 0),
    destination: PadCoordinate(row: 1, column: 5),
    seed: 44
)
let topology = VesselTopology(vessels: [first, extensionSegment, parallel])
require(topology.hubs.isEmpty, "parallel tracks incorrectly produced a hub")
require(
    TrackTopology(vessels: [first, extensionSegment, parallel]).descendants(of: first.id)
        == Set([first.id, extensionSegment.id]),
    "downstream track drainage scope is invalid"
)

require(PadCoordinate(row: 0, column: 0).index == 0, "first coordinate mapping is invalid")
require(PadCoordinate(row: 7, column: 7).index == 63, "last coordinate mapping is invalid")
require(
    LaunchpadGridMapping.coordinate(for: 81) == PadCoordinate(row: 0, column: 0),
    "Launchpad top-left mapping is invalid"
)
require(
    LaunchpadGridMapping.coordinate(for: 18) == PadCoordinate(row: 7, column: 7),
    "Launchpad bottom-right mapping is invalid"
)
require(
    LaunchpadGridMapping.note(for: PadCoordinate(row: 0, column: 0)) == 81,
    "Launchpad reverse mapping is invalid"
)
require(LaunchpadGridMapping.auxiliaryNote(forRow: 0) == 89,
        "top auxiliary button mapping is invalid")
require(LaunchpadGridMapping.auxiliaryNote(forRow: 7) == 19,
        "bottom auxiliary button mapping is invalid")
require(LaunchpadGridMapping.auxiliaryRow(for: 59) == 3,
        "auxiliary input mapping is invalid")
require(LaunchpadGridMapping.auxiliaryPhase(status: 0xB0, value: 127) == .pressed,
        "Control Change auxiliary press is not recognized")
require(LaunchpadGridMapping.auxiliaryPhase(status: 0xB0, value: 0) == .released,
        "Control Change auxiliary release is not recognized")
require(LaunchpadGridMapping.shiftNote == 98, "top-right Shift mapping is invalid")
require(LaunchpadGridMapping.projectNote == 91, "top-left Projects mapping is invalid")
require(LaunchpadGridMapping.masterEffectsNote == 92,
        "second top-row master-effects mapping is invalid")
require(LaunchpadGridMapping.destructiveEffectsNote == 93,
        "third top-row destructive-effects mapping is invalid")
require(LaunchpadGridMapping.globalScenesNote == 94,
        "fourth top-row global-scenes mapping is invalid")
require(
    LaunchpadGridMapping.destructiveEffectsPhase(
        note: 93, status: 0xB0, value: 127
    ) == .pressed,
    "destructive-effects press is not recognized"
)
require(
    LaunchpadGridMapping.destructiveEffectsPhase(
        note: 93, status: 0xB0, value: 0
    ) == .released,
    "destructive-effects release is not recognized"
)
require(
    LaunchpadGridMapping.masterEffectsPhase(note: 92, status: 0xB0, value: 127) == .pressed,
    "master-effects press is not recognized"
)
require(
    LaunchpadGridMapping.masterEffectsPhase(note: 92, status: 0xB0, value: 0) == .released,
    "master-effects release is not recognized"
)
require(
    LaunchpadGridMapping.projectPhase(note: 91, status: 0xB0, value: 127) == .pressed,
    "Projects press is not recognized"
)
require(
    LaunchpadGridMapping.projectPhase(note: 91, status: 0xB0, value: 0) == .released,
    "Projects release is not recognized"
)
require(
    LaunchpadGridMapping.globalScenesPhase(note: 94, status: 0xB0, value: 127) == .pressed,
    "global-scenes press is not recognized"
)
require(
    LaunchpadGridMapping.globalScenesPhase(note: 94, status: 0xB0, value: 0) == .released,
    "global-scenes release is not recognized"
)
require(
    LaunchpadGridMapping.shiftPhase(note: 98, status: 0xB0, value: 127) == .pressed,
    "Shift press is not recognized"
)
require(
    LaunchpadGridMapping.shiftPhase(note: 98, status: 0xB0, value: 0) == .released,
    "Shift release is not recognized"
)
require(
    LaunchpadGridMapping.shiftPhase(note: 97, status: 0xB0, value: 127) == nil,
    "a neighboring top button was mistaken for Shift"
)
require(TrackPalette.hues.count == 8, "fixed track palette does not cover every track")
require(Set(TrackPalette.hues).count == 8, "fixed track colours are not distinct")
require(TrackMixer.volume(forColumn: 0) == 0, "volume bar does not begin at zero")
require(TrackMixer.volume(forColumn: 7) == 1, "volume bar does not reach unity")
require(TrackMixer.volumePadRow == 7, "volume is not on physical bottom row 1")
require(TrackMixer.panPadRow == 6, "pan is not on physical row 2")
require(TrackMixer.reverbPadRow == 0, "reverb send is not on the top row")
require(TrackMixer.delayPadRow == 1, "delay send is not second from the top")
require(TrackMixer.saturationPadRow == 2,
        "saturation send is not third from the top")
require(TrackMixer.crusherPadRow == 3, "crusher send is not fourth from the top")
require(TrackMixer.gatePadRow == 4, "rhythmic gate is not on programmer notes 41–48")
require(TrackMixer.scenePadRows == [5], "scene slots are not on programmer notes 31–38")
require(LaunchpadGridMapping.note(for: PadCoordinate(row: 4, column: 0)) == 41,
        "rhythmic gate does not begin at programmer note 41")
require(LaunchpadGridMapping.note(for: PadCoordinate(row: 5, column: 0)) == 31,
        "lower reserved row does not begin at programmer note 31")
require(LaunchpadGridMapping.note(for: PadCoordinate(row: 5, column: 7)) == 38,
        "lower reserved row does not end at programmer note 38")
require(TrackMixer.send(forColumn: 0) == 0, "send bar does not begin at zero")
require(TrackMixer.send(forColumn: 7) == 1, "send bar does not reach unity")
require(TrackMixer.sendColumn(for: 0) == 0, "zero send has an invalid marker")
require(TrackMixer.sendColumn(for: 1) == 7, "unity send has an invalid marker")
require(TrackSendLevels.zero == TrackSendLevels(), "track sends do not default to zero")
require(
    TrackMixer.sceneSlot(for: PadCoordinate(row: 5, column: 0)) == 0,
    "scene row does not begin at slot 1"
)
require(
    TrackMixer.sceneSlot(for: PadCoordinate(row: 5, column: 7)) == 7,
    "scene row does not end at slot 8"
)
require(
    TrackMixer.sceneSlot(for: PadCoordinate(row: 4, column: 0)) == nil,
    "rhythmic-gate row was mistaken for a scene slot"
)
require(
    TrackMixer.sceneSlot(for: PadCoordinate(row: 3, column: 0)) == nil,
    "an effect-send row was mistaken for a scene slot"
)
let sceneSnapshot = TrackScene(
    vessels: [first, extensionSegment],
    volume: 0.71,
    pan: -1.0 / 3.0,
    sends: TrackSendLevels(reverb: 0.4, delay: 0.2, saturation: 0.6, crusher: 0.1),
    gate: 2.0 / 3.0,
    generatorLock: lockedGenerator,
    chainLock: chainLock,
    harmonicAnchor: harmonicAnchor
)
var sceneBank = TrackSceneBank()
require(sceneBank.occupiedSlots(track: 0).isEmpty, "new scene bank was not empty")
sceneBank.setScene(sceneSnapshot, track: 0, slot: 7)
require(sceneBank.scene(track: 0, slot: 7) == sceneSnapshot,
        "scene bank did not preserve the complete track snapshot")
require(sceneBank.occupiedSlots(track: 0) == Set([7]),
        "occupied scene indication is incorrect")
require(sceneBank.scene(track: 1, slot: 7) == nil,
        "a scene leaked into another track's bank")
require(sceneBank.scene(track: 0, slot: 8) == nil,
        "out-of-range scene access was accepted")
require(TrackMixer.pan(forColumn: 0) == -1, "pan bar does not reach full left")
require(TrackMixer.pan(forColumn: 3) == 0, "left centre pan cell is biased")
require(TrackMixer.pan(forColumn: 4) == 0, "right centre pan cell is biased")
require(TrackMixer.pan(forColumn: 7) == 1, "pan bar does not reach full right")
require(TrackMixer.gate(forColumn: 3) == 0, "left centre gate cell is not off")
require(TrackMixer.gate(forColumn: 4) == 0, "right centre gate cell is not off")
require(TrackMixer.gateClockMultiplier(for: -1) == 0.125,
        "slowest gate is not an eighth-speed clock division")
require(TrackMixer.gateClockMultiplier(for: -1.0 / 3.0) == 0.5,
        "nearest left gate is not a half-speed clock division")
require(TrackMixer.gateClockMultiplier(for: 1.0 / 3.0) == 2,
        "nearest right gate is not a double-speed clock multiplication")
require(TrackMixer.gateClockMultiplier(for: 1) == 8,
        "fastest gate is not an eightfold clock multiplication")
require(TrackMixer.defaultGate == 0, "rhythmic gate does not default to off")
require(LaunchpadFader.stepCount == 32 && LaunchpadFader.levelsPerPad == 4,
        "Launchpad faders do not expose four levels across eight pads")
require(LaunchpadFader.unipolarValue(forStep: 0) == 0,
        "high-resolution unipolar fader does not begin at zero")
require(LaunchpadFader.unipolarValue(forStep: 31) == 1,
        "high-resolution unipolar fader does not reach unity")
let fineBase = LaunchpadFader.unipolarValue(forStep: 12)
let fineStep13 = LaunchpadFader.nextUnipolarStep(currentValue: fineBase, padColumn: 3)
let fineStep14 = LaunchpadFader.nextUnipolarStep(
    currentValue: LaunchpadFader.unipolarValue(forStep: fineStep13), padColumn: 3
)
let fineStep15 = LaunchpadFader.nextUnipolarStep(
    currentValue: LaunchpadFader.unipolarValue(forStep: fineStep14), padColumn: 3
)
require([fineStep13, fineStep14, fineStep15] == [13, 14, 15],
        "repeated fader presses did not traverse the four within-pad levels")
require(LaunchpadFader.nextUnipolarStep(
    currentValue: LaunchpadFader.unipolarValue(forStep: fineStep15), padColumn: 3
) == 12, "within-pad fader levels did not cycle back to the first intensity")
require(LaunchpadFader.nextUnipolarStep(
    currentValue: LaunchpadFader.unipolarValue(forStep: 15), padColumn: 4
) == 16, "upward fader movement did not enter the next pad continuously")
require(LaunchpadFader.nextUnipolarStep(
    currentValue: LaunchpadFader.unipolarValue(forStep: 16), padColumn: 3
) == 15, "downward fader movement did not enter the prior pad continuously")
require(LaunchpadFader.bipolarValue(forStep: 15) == 0
            && LaunchpadFader.bipolarValue(forStep: 16) == 0,
        "high-resolution bipolar fader lost its two-pad centre")
require(MasterEffectControl.allCases.map(\.rawValue) == Array(0..<8),
        "master-effect controls do not cover all eight rows in order")
require(MasterEffectParameters.value(forColumn: 0) == 0,
        "master-effect bar does not begin at zero")
require(MasterEffectParameters.value(forColumn: 7) == 1,
        "master-effect bar does not reach unity")
var effectParameters = MasterEffectParameters.defaults
effectParameters.setValue(1.2, for: .reverbDecay)
effectParameters.setValue(-0.2, for: .delayFeedback)
require(effectParameters.reverbDecay == 1 && effectParameters.delayFeedback == 0,
        "master-effect parameters were not safety-clamped")
require(DestructiveEffectControl.allCases.map(\.rawValue) == Array(0..<8),
        "destructive-effect controls do not cover all eight rows in order")
require(DestructiveEffectParameters.value(forColumn: 0) == 0,
        "destructive-effect bar does not begin at zero")
require(DestructiveEffectParameters.value(forColumn: 7) == 1,
        "destructive-effect bar does not reach unity")
var destructiveParameters = DestructiveEffectParameters.defaults
destructiveParameters.setValue(1.2, for: .saturationDrive)
destructiveParameters.setValue(-0.2, for: .crusherJitter)
require(destructiveParameters.saturationDrive == 1
            && destructiveParameters.crusherJitter == 0,
        "destructive-effect parameters were not safety-clamped")

require(ProjectGrid.slot(for: PadCoordinate(row: 7, column: 0)) == 0,
        "bottom-left project pad is not slot 1")
require(ProjectGrid.slot(for: PadCoordinate(row: 7, column: 7)) == 7,
        "bottom project row does not end at slot 8")
require(ProjectGrid.slot(for: PadCoordinate(row: 4, column: 0)) == 24,
        "fourth project row does not begin at slot 25")
require(ProjectGrid.slot(for: PadCoordinate(row: 4, column: 7)) == 31,
        "fourth project row does not end at slot 32")
require(ProjectGrid.slot(for: PadCoordinate(row: 3, column: 0)) == nil,
        "reserved upper project row was assigned a project slot")
require(ProjectGrid.pad(for: 31) == PadCoordinate(row: 4, column: 7),
        "project slot reverse mapping is invalid")
require(GlobalSceneGrid.slot(for: PadCoordinate(row: 7, column: 0)) == 0,
        "bottom-left global-scene pad is not slot 1")
require(GlobalSceneGrid.slot(for: PadCoordinate(row: 4, column: 7)) == 31,
        "fourth global-scene row does not end at slot 32")
require(GlobalSceneGrid.slot(for: PadCoordinate(row: 3, column: 0)) == nil,
        "reserved upper global-scene row was assigned a slot")

let globalSceneSnapshot = GlobalSceneState(
    session: VascularSession(vessels: [first, extensionSegment], nextSeed: 654_321),
    trackVolumes: [0.71] + Array(repeating: 1, count: 7),
    trackPans: [-1.0 / 3.0] + Array(repeating: 0, count: 7),
    trackSends: [sceneSnapshot.sends] + Array(repeating: .zero, count: 7),
    trackGates: [sceneSnapshot.gate] + Array(repeating: 0, count: 7),
    activeTrackSceneSlots: [0: 7],
    masterEffects: effectParameters,
    destructiveEffects: destructiveParameters
)
require(globalSceneSnapshot.hasValidTrackState,
        "complete global scene state was rejected")
var globalSceneBank = GlobalSceneBank()
globalSceneBank.setScene(globalSceneSnapshot, slot: 31)
require(globalSceneBank.scene(slot: 31) == globalSceneSnapshot,
        "global scene bank did not preserve complete machine state")
require(globalSceneBank.occupiedSlots == Set([31]),
        "occupied global scene slots are incorrect")
require(globalSceneBank.scene(slot: 32) == nil,
        "out-of-range global scene access was accepted")

let projectSnapshot = ProjectState(
    session: VascularSession(
        vessels: [first, extensionSegment],
        nextSeed: 987_654,
        generatorLocks: [0: lockedGenerator],
        chainLocks: [0: chainLock],
        harmonicAnchor: harmonicAnchor
    ),
    trackVolumes: [0.71] + Array(repeating: 1, count: 7),
    trackPans: [-1.0 / 3.0] + Array(repeating: 0, count: 7),
    trackSends: [sceneSnapshot.sends] + Array(repeating: .zero, count: 7),
    trackGates: [sceneSnapshot.gate] + Array(repeating: 0, count: 7),
    sceneBank: sceneBank,
    activeSceneSlots: [0: 7],
    masterEffects: effectParameters,
    destructiveEffects: destructiveParameters,
    globalSceneBank: globalSceneBank,
    activeGlobalSceneSlot: 31
)
require(projectSnapshot.hasValidTrackState, "complete project state was rejected")
var projectBank = ProjectBank()
projectBank.setProject(projectSnapshot, slot: 31)
require(projectBank.project(slot: 31) == projectSnapshot,
        "project bank did not preserve complete machine state")
require(projectBank.occupiedSlots == Set([31]), "occupied project slots are incorrect")
require(projectBank.project(slot: 32) == nil, "out-of-range project access was accepted")
let projectData = try JSONEncoder().encode(projectBank)
let decodedProjectBank = try JSONDecoder().decode(ProjectBank.self, from: projectData)
require(decodedProjectBank == projectBank,
        "persistent project archive did not round-trip")
var legacyObject = try JSONSerialization.jsonObject(with: projectData) as! [String: Any]
var legacyProjects = legacyObject["projects"] as! [String: Any]
var legacyProject = legacyProjects["31"] as! [String: Any]
legacyProject.removeValue(forKey: "masterEffects")
legacyProject.removeValue(forKey: "destructiveEffects")
legacyProject.removeValue(forKey: "globalSceneBank")
legacyProject.removeValue(forKey: "activeGlobalSceneSlot")
legacyProject["formatVersion"] = 1
legacyProjects["31"] = legacyProject
legacyObject["projects"] = legacyProjects
let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
let legacyBank = try JSONDecoder().decode(ProjectBank.self, from: legacyData)
require(legacyBank.project(slot: 31)?.masterEffects == .defaults,
        "legacy project did not receive master-effect defaults")
require(legacyBank.project(slot: 31)?.destructiveEffects == .defaults,
        "legacy project did not receive destructive-effect defaults")
require(legacyBank.project(slot: 31)?.globalSceneBank == GlobalSceneBank(),
        "legacy project did not receive an empty global-scene bank")
require(legacyBank.project(slot: 31)?.isSupportedFormat == true,
        "compatible legacy project format was rejected")

print("VascularCoreChecks passed")
