import SwiftUI
import VascularCore

struct MatrixView: View {
    @ObservedObject var model: InstrumentModel
    private let hubTimer = Timer.publish(every: 0.42, on: .main, in: .common).autoconnect()

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: PadCoordinate.matrixSize
    )

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.035, blue: 0.04).ignoresSafeArea()

            VStack(spacing: 14) {
                header
                controlSurface
                footer
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
        .onReceive(hubTimer) { _ in model.advanceHubPulse() }
    }

    private var controlSurface: some View {
        GeometryReader { geometry in
            let matrixSize = max(
                1,
                min(geometry.size.width - 58, geometry.size.height - 48)
            )
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    topButtonRow.frame(width: matrixSize)
                    Color.clear.frame(width: 48, height: 38)
                }
                HStack(alignment: .top, spacing: 10) {
                    matrix.frame(width: matrixSize, height: matrixSize)
                    trackButtonRail.frame(height: matrixSize)
                }
            }
            .frame(width: matrixSize + 58, height: matrixSize + 48)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    private var topButtonRow: some View {
        HStack(spacing: 10) {
            SurfaceButton(label: "PROJ", color: .cyan, active: model.projectViewOpen) {
                model.toggleProjectView()
            }
            SurfaceButton(label: "SPACE", color: .blue, active: model.masterEffectsViewOpen) {
                model.toggleMasterEffectsView()
            }
            SurfaceButton(label: "TEXT", color: .orange, active: model.destructiveEffectsViewOpen) {
                model.toggleDestructiveEffectsView()
            }
            SurfaceButton(label: "SCENE", color: .purple, active: model.globalSceneViewOpen) {
                model.toggleGlobalSceneView()
            }
            ForEach(0..<3, id: \.self) { _ in
                SurfaceButton(label: "—", color: .gray, active: false, enabled: false) {}
            }
            SurfaceButton(label: "SHIFT", color: .white, active: model.shiftHeld) {
                model.toggleShiftLatch()
            }
        }
        .frame(height: 38)
    }

    private var trackButtonRail: some View {
        GeometryReader { geometry in
            let spacing = 10.0
            let height = (geometry.size.height - spacing * 7) / 8
            VStack(spacing: spacing) {
                ForEach(0..<8, id: \.self) { row in
                    let hue = TrackPalette.hue(forRow: row)
                    SurfaceButton(
                        label: "T\(row + 1)",
                        color: Color(hue: hue, saturation: 0.82, brightness: 0.94),
                        active: model.editingTrack == row,
                        enabled: !model.projectViewOpen
                            && !model.globalSceneViewOpen
                            && !model.masterEffectsViewOpen
                            && !model.destructiveEffectsViewOpen
                            && !model.shiftHeld
                    ) {
                        model.toggleTrackEditor(row: row)
                    }
                    .frame(height: max(28, height))
                }
            }
        }
        .frame(width: 48)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ParallelLives")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .tracking(5)
                Text("MODULAR ELECTROACOUSTIC MULTITRACK")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .tracking(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(model.activeTrackCount) TRACKS · \(model.processorCount) PROCESSORS")
                Text("ENGINE · BUNDLED CSOUND 6.18.1")
                Text(model.controllerStatus)
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }

    private var matrix: some View {
        GeometryReader { geometry in
            ZStack {
                if model.editingTrack == nil
                    && !model.projectViewOpen
                    && !model.globalSceneViewOpen
                    && !model.masterEffectsViewOpen
                    && !model.destructiveEffectsViewOpen {
                    vesselLayer(size: geometry.size)
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(0..<64, id: \.self) { index in
                        let pad = PadCoordinate(row: index / 8, column: index % 8)
                        PadView(
                            coordinate: pad,
                            state: state(for: pad),
                            generatorLocked: (pad.column == 0
                                && model.isGeneratorLocked(row: pad.row)
                                && model.vesselTouching(pad) != nil)
                                || model.isChainLockEndpoint(pad),
                            controlLabel: controlLabel(for: pad),
                            onTap: { model.tap(pad) },
                            onLongPress: { model.longPress(pad) }
                        )
                    }
                }
                .padding(8)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.black.opacity(0.28))
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func vesselLayer(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            for vessel in model.session.vessels {
                var path = Path()
                path.move(to: point(for: vessel.source, size: canvasSize))
                path.addLine(to: point(for: vessel.destination, size: canvasSize))
                let selected = vessel.id == model.selectedVesselID
                context.stroke(
                    path,
                    with: .color(vesselColor(vessel, selected: selected)),
                    style: StrokeStyle(
                        lineWidth: selected ? 8 : 5,
                        lineCap: .round,
                        dash: selected ? [] : [5, 8]
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func point(for pad: PadCoordinate, size: CGSize) -> CGPoint {
        let unit = size.width / 8
        return CGPoint(
            x: (Double(pad.column) + 0.5) * unit,
            y: (Double(pad.row) + 0.5) * unit
        )
    }

    private func state(for pad: PadCoordinate) -> PadState {
        if model.destructiveEffectsViewOpen {
            guard let control = DestructiveEffectControl(padRow: pad.row) else {
                return .editorInactive
            }
            let value = model.destructiveEffects.value(for: control)
            let step = LaunchpadFader.unipolarStep(for: value)
            let column = LaunchpadFader.padColumn(forStep: step)
            return .control(
                hue: pad.row < 4 ? 0.02 : 0.58,
                active: pad.column < column,
                marker: pad.column == column,
                markerBrightness: LaunchpadFader.markerBrightness(forStep: step)
            )
        }
        if model.masterEffectsViewOpen {
            guard let control = MasterEffectControl(padRow: pad.row) else {
                return .editorInactive
            }
            let value = model.masterEffects.value(for: control)
            let step = LaunchpadFader.unipolarStep(for: value)
            let column = LaunchpadFader.padColumn(forStep: step)
            return .control(
                hue: pad.row < 4 ? 0.78 : 0.1,
                active: pad.column < column,
                marker: pad.column == column,
                markerBrightness: LaunchpadFader.markerBrightness(forStep: step)
            )
        }
        if model.globalSceneViewOpen {
            guard let slot = GlobalSceneGrid.slot(for: pad) else { return .editorInactive }
            return .globalScene(
                occupied: model.globalSceneOccupied(slot: slot),
                active: model.activeGlobalSceneSlot == slot,
                confirming: model.globalSceneSaveConfirmationSlot == slot
                    && model.globalSceneSaveConfirmationBright
            )
        }
        if model.projectViewOpen {
            guard let slot = ProjectGrid.slot(for: pad) else { return .editorInactive }
            return .project(
                occupied: model.projectOccupied(slot: slot),
                active: model.activeProjectSlot == slot,
                confirming: model.projectSaveConfirmationSlot == slot
                    && model.projectSaveConfirmationBright
            )
        }
        if let track = model.editingTrack {
            let hue = TrackPalette.hue(forRow: track)
            if pad.row == TrackMixer.volumePadRow {
                let step = LaunchpadFader.unipolarStep(for: model.trackVolumes[track])
                let column = LaunchpadFader.padColumn(forStep: step)
                return .control(
                    hue: hue,
                    active: pad.column < column,
                    marker: pad.column == column,
                    markerBrightness: LaunchpadFader.markerBrightness(forStep: step)
                )
            }
            if pad.row == TrackMixer.panPadRow {
                let pan = model.trackPans[track]
                let step = LaunchpadFader.bipolarStep(for: pan)
                let column = LaunchpadFader.padColumn(forStep: step)
                let active = column <= 3
                    ? (pad.column >= column && pad.column <= 3)
                    : (pad.column >= 4 && pad.column <= column)
                let marker = abs(pan) < 0.000_001
                    ? (pad.column == 3 || pad.column == 4)
                    : pad.column == column
                let markerBrightness = pad.column == column
                    ? LaunchpadFader.markerBrightness(forStep: step)
                    : 0.67
                return .control(
                    hue: hue, active: active, marker: marker,
                    markerBrightness: markerBrightness
                )
            }
            if pad.row == TrackMixer.gatePadRow {
                let gate = model.trackGates[track]
                let step = LaunchpadFader.bipolarStep(for: gate)
                let column = LaunchpadFader.padColumn(forStep: step)
                let active = column <= 3
                    ? (pad.column >= column && pad.column <= 3)
                    : (pad.column >= 4 && pad.column <= column)
                let marker = abs(gate) < 0.000_001
                    ? (pad.column == 3 || pad.column == 4)
                    : pad.column == column
                let markerBrightness = pad.column == column
                    ? LaunchpadFader.markerBrightness(forStep: step)
                    : 0.67
                return .control(
                    hue: hue, active: active, marker: marker,
                    markerBrightness: markerBrightness
                )
            }
            let sends = model.trackSends[track]
            let sendValue: Double? = switch pad.row {
            case TrackMixer.reverbPadRow: sends.reverb
            case TrackMixer.delayPadRow: sends.delay
            case TrackMixer.saturationPadRow: sends.saturation
            case TrackMixer.crusherPadRow: sends.crusher
            default: nil
            }
            if let sendValue {
                let step = LaunchpadFader.unipolarStep(for: sendValue)
                let column = LaunchpadFader.padColumn(forStep: step)
                return .control(
                    hue: hue,
                    active: pad.column < column,
                    marker: pad.column == column,
                    markerBrightness: LaunchpadFader.markerBrightness(forStep: step)
                )
            }
            if let slot = TrackMixer.sceneSlot(for: pad) {
                return .scene(
                    hue: (hue + 0.085).truncatingRemainder(dividingBy: 1),
                    occupied: model.sceneOccupied(track: track, slot: slot),
                    active: model.activeSceneSlots[track] == slot
                )
            }
            return .editorInactive
        }
        if model.awakenedPad == pad { return .awakened }
        if VesselTopology(vessels: model.session.vessels).hubs.contains(pad) {
            return .hub(bright: model.hubPulseBright)
        }
        if let vessel = model.vesselTouching(pad) {
            let selected = vessel.id == model.selectedVesselID
            if model.isTrackBoundary(pad) {
                return .endpoint(hue: TrackPalette.hue(forRow: vessel.source.row), selected: selected)
            }
            if let endpoint = model.chainLockEndpoint(row: pad.row), pad.column <= endpoint {
                return .lockTrail(
                    hue: TrackPalette.hue(forRow: pad.row),
                    endpoint: pad.column == endpoint,
                    shifted: model.shiftHeld
                )
            }
            return .processor(hue: TrackPalette.hue(forRow: vessel.source.row), selected: selected)
        }
        if let endpoint = model.chainLockEndpoint(row: pad.row), pad.column <= endpoint {
            return .lockTrail(
                hue: TrackPalette.hue(forRow: pad.row),
                endpoint: pad.column == endpoint,
                shifted: model.shiftHeld
            )
        }
        return .idle
    }

    private func controlLabel(for pad: PadCoordinate) -> String? {
        if model.destructiveEffectsViewOpen {
            guard pad.column == 0,
                  let control = DestructiveEffectControl(padRow: pad.row) else { return nil }
            return switch control {
            case .saturationDrive: "DRIVE"
            case .saturationCurve: "CURVE"
            case .saturationTone: "TONE"
            case .saturationBody: "BODY"
            case .crusherBits: "BITS"
            case .crusherRate: "RATE"
            case .crusherJitter: "JITTER"
            case .crusherTone: "TONE"
            }
        }
        if model.masterEffectsViewOpen {
            guard pad.column == 0,
                  let control = MasterEffectControl(padRow: pad.row) else { return nil }
            return switch control {
            case .reverbSize: "SIZE"
            case .reverbDecay: "DECAY"
            case .reverbTone: "TONE"
            case .reverbMotion: "MOTION"
            case .delayTime: "TIME"
            case .delayFeedback: "FDBK"
            case .delayTone: "TONE"
            case .delayWidth: "WIDTH"
            }
        }
        if model.globalSceneViewOpen {
            return GlobalSceneGrid.slot(for: pad).map { "G\($0 + 1)" }
        }
        if model.projectViewOpen {
            return ProjectGrid.slot(for: pad).map { "P\($0 + 1)" }
        }
        guard model.editingTrack != nil else { return nil }
        if let slot = TrackMixer.sceneSlot(for: pad) {
            return "S\(slot + 1)"
        }
        guard pad.column == 0 else { return nil }
        return switch pad.row {
        case TrackMixer.reverbPadRow: "REV"
        case TrackMixer.delayPadRow: "DLY"
        case TrackMixer.saturationPadRow: "SAT"
        case TrackMixer.crusherPadRow: "CRUSH"
        case TrackMixer.gatePadRow: "GATE"
        case TrackMixer.panPadRow: "PAN"
        case TrackMixer.volumePadRow: "VOL"
        default: nil
        }
    }

    private func vesselColor(_ vessel: VesselGraph, selected: Bool) -> Color {
        Color(
            hue: TrackPalette.hue(forRow: vessel.source.row),
            saturation: selected ? 0.9 : 0.78,
            brightness: selected ? 0.98 : 0.76
        ).opacity(selected ? 0.95 : 0.72)
    }

    private var footer: some View {
        HStack {
            Circle()
                .fill(model.awakenedPad == nil ? Color.secondary : Color.orange)
                .frame(width: 8, height: 8)
            Text(model.status)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            if model.destructiveEffectsViewOpen {
                Button("TRACKS") { model.toggleDestructiveEffectsView() }
            } else if model.masterEffectsViewOpen {
                Button("TRACKS") { model.toggleMasterEffectsView() }
            } else if model.projectViewOpen {
                Button("TRACKS") { model.toggleProjectView() }
            } else if model.globalSceneViewOpen {
                Button("TRACKS") { model.toggleGlobalSceneView() }
            } else if model.editingTrack != nil {
                Button("TRACKS") { model.closeTrackEditor() }
            } else {
                Button("PROJECTS") { model.toggleProjectView() }
                Button("RETURNS") { model.toggleMasterEffectsView() }
                Button("TEXTURE") { model.toggleDestructiveEffectsView() }
                Button("SCENES") { model.toggleGlobalSceneView() }
                Button("REMOVE") { model.drainSelected() }
            }
            Button("PANIC") { model.panic() }
                .tint(.red.opacity(0.8))
        }
        .buttonStyle(.bordered)
    }
}

private enum PadState: Equatable {
    case idle
    case awakened
    case hub(bright: Bool)
    case processor(hue: Double, selected: Bool)
    case endpoint(hue: Double, selected: Bool)
    case control(hue: Double, active: Bool, marker: Bool, markerBrightness: Double)
    case scene(hue: Double, occupied: Bool, active: Bool)
    case project(occupied: Bool, active: Bool, confirming: Bool)
    case globalScene(occupied: Bool, active: Bool, confirming: Bool)
    case lockTrail(hue: Double, endpoint: Bool, shifted: Bool)
    case editorInactive
}

private struct SurfaceButton: View {
    let label: String
    let color: Color
    let active: Bool
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 9)
                .fill(color.opacity(active ? 0.9 : (enabled ? 0.22 : 0.07)))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(color.opacity(active ? 1 : 0.35), lineWidth: active ? 2 : 1)
                }
                .overlay {
                    Text(label)
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(enabled ? 0.92 : 0.25))
                }
                .shadow(color: active ? color.opacity(0.8) : .clear, radius: 9)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(label)
    }
}

private struct PadView: View {
    let coordinate: PadCoordinate
    let state: PadState
    let generatorLocked: Bool
    let controlLabel: String?
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var pressing = false

    var body: some View {
        RoundedRectangle(cornerRadius: 13)
            .fill(fillColor)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(borderColor, lineWidth: state == .idle ? 1 : 2)
            }
            .overlay(alignment: .bottomTrailing) {
                Text("\(coordinate.index + 1)")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.25))
                    .padding(7)
            }
            .overlay(alignment: .topLeading) {
                if generatorLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .padding(7)
                }
            }
            .overlay {
                if let controlLabel {
                    Text(controlLabel)
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.82))
                }
            }
            .scaleEffect(pressing ? 0.92 : 1)
            .shadow(color: glowColor, radius: state == .idle ? 0 : 9)
            .contentShape(RoundedRectangle(cornerRadius: 13))
            .onTapGesture(perform: onTap)
            .onLongPressGesture(
                minimumDuration: 0.48,
                maximumDistance: 12,
                perform: onLongPress,
                onPressingChanged: { value in
                    withAnimation(.easeOut(duration: 0.12)) { pressing = value }
                }
            )
            .animation(.easeInOut(duration: 0.2), value: state)
            .accessibilityLabel("Pad \(coordinate.index + 1)")
            .accessibilityHint("Long press a track source or endpoint; select a pad to its right")
    }

    private var fillColor: Color {
        switch state {
        case .idle: Color.white.opacity(0.055)
        case .editorInactive: Color.white.opacity(0.025)
        case .awakened: Color.orange.opacity(0.72)
        case .hub(let bright): Color.white.opacity(bright ? 0.96 : 0.18)
        case .processor(let hue, let selected):
            Color(hue: hue, saturation: 0.76, brightness: selected ? 0.68 : 0.42)
        case .endpoint(let hue, let selected):
            Color(hue: hue, saturation: 0.82, brightness: selected ? 1 : 0.9)
        case .control(let hue, let active, let marker, let markerBrightness):
            Color(
                hue: hue,
                saturation: 0.82,
                brightness: marker ? markerBrightness : (active ? 0.62 : 0.12)
            )
        case .scene(let hue, let occupied, let active):
            Color(
                hue: hue,
                saturation: active ? 0.12 : (occupied ? 0.9 : 0.32),
                brightness: active ? 1 : (occupied ? 0.68 : 0.12)
            )
        case .project(let occupied, let active, let confirming):
            confirming
                ? Color.white
                : active
                ? Color(red: 1, green: 0, blue: 0)
                : Color(
                    hue: 0.52,
                    saturation: occupied ? 0.9 : 0.32,
                    brightness: occupied ? 0.68 : 0.12
                )
        case .globalScene(let occupied, let active, let confirming):
            confirming
                ? Color.white
                : Color(
                    hue: active ? 0.13 : 0.82,
                    saturation: active ? 0.9 : (occupied ? 0.86 : 0.3),
                    brightness: active ? 1 : (occupied ? 0.68 : 0.12)
                )
        case .lockTrail(let hue, let endpoint, let shifted):
            Color(
                hue: hue,
                saturation: shifted && endpoint ? 0.08 : 0.72,
                brightness: shifted && endpoint ? 1 : (endpoint ? 0.24 : 0.1)
            )
        }
    }

    private var borderColor: Color {
        switch state {
        case .idle: Color.white.opacity(0.09)
        case .editorInactive: Color.white.opacity(0.045)
        case .awakened: .orange
        case .hub(let bright): Color.white.opacity(bright ? 1 : 0.28)
        case .processor(let hue, let selected):
            Color(hue: hue, saturation: 0.72, brightness: selected ? 0.9 : 0.62)
        case .endpoint(let hue, _):
            Color(hue: hue, saturation: 0.72, brightness: 1)
        case .control(let hue, _, let marker, let markerBrightness):
            Color(hue: hue, saturation: 0.7, brightness: marker ? markerBrightness : 0.48)
        case .scene(let hue, let occupied, let active):
            Color(
                hue: hue,
                saturation: active ? 0.08 : 0.72,
                brightness: active ? 1 : (occupied ? 0.94 : 0.32)
            )
        case .project(let occupied, let active, let confirming):
            confirming
                ? Color.white
                : active
                ? Color(red: 1, green: 0, blue: 0)
                : Color(
                    hue: 0.52,
                    saturation: 0.72,
                    brightness: occupied ? 0.94 : 0.32
                )
        case .globalScene(let occupied, let active, let confirming):
            confirming
                ? Color.white
                : Color(
                    hue: active ? 0.13 : 0.82,
                    saturation: 0.72,
                    brightness: active ? 1 : (occupied ? 0.94 : 0.32)
                )
        case .lockTrail(let hue, let endpoint, let shifted):
            Color(
                hue: hue,
                saturation: shifted && endpoint ? 0.08 : 0.66,
                brightness: shifted && endpoint ? 1 : (endpoint ? 0.42 : 0.2)
            )
        }
    }

    private var glowColor: Color {
        switch state {
        case .idle: .clear
        case .editorInactive: .clear
        case .awakened: .orange.opacity(0.55)
        case .hub(let bright): Color.white.opacity(bright ? 0.82 : 0.18)
        case .processor(let hue, let selected):
            Color(hue: hue, saturation: 0.78, brightness: 0.8)
                .opacity(selected ? 0.48 : 0.24)
        case .endpoint(let hue, let selected):
            Color(hue: hue, saturation: 0.82, brightness: 1)
                .opacity(selected ? 0.72 : 0.48)
        case .control(let hue, _, let marker, _):
            Color(hue: hue, saturation: 0.8, brightness: 1)
                .opacity(marker ? 0.7 : 0.18)
        case .scene(let hue, let occupied, let active):
            Color(hue: hue, saturation: 0.72, brightness: 1)
                .opacity(active ? 0.75 : (occupied ? 0.42 : 0.04))
        case .project(let occupied, let active, let confirming):
            (confirming
                ? Color.white
                : (active ? Color.red : Color(hue: 0.52, saturation: 0.72, brightness: 1)))
                .opacity(confirming ? 1 : (active ? 0.92 : (occupied ? 0.42 : 0.04)))
        case .globalScene(let occupied, let active, let confirming):
            Color(hue: active ? 0.13 : 0.82, saturation: 0.78, brightness: 1)
                .opacity(confirming ? 1 : (active ? 0.78 : (occupied ? 0.42 : 0.04)))
        case .lockTrail(let hue, let endpoint, let shifted):
            Color(hue: hue, saturation: 0.7, brightness: 1)
                .opacity(shifted && endpoint ? 0.72 : (endpoint ? 0.18 : 0.05))
        }
    }
}
