import SwiftUI
import UIKit

/// A camera-counted exercise (docs/MOTION_TRACKING.md §44): finding you → positioning → stay still →
/// 3 · 2 · 1 · GO → "7 / 10" → Complete. The member sees one short line at a time; the skeleton and the
/// signal values appear only behind the details toggle (development and calibration).
struct MotionTrackingView: View {
    let exercise: MotionExercise
    @State private var model: MotionTrackingViewModel?
    @State private var showsDetails = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    init(exercise: MotionExercise = .chestOpener()) {
        self.exercise = exercise
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model { screen(model) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // Created here, not in init: a view's init runs on every parent render, a camera must not.
            if model == nil { model = MotionTrackingViewModel(exercise: exercise) }
            await model?.start()
        }
        .onDisappear { model?.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model?.start() }
            } else {
                model?.stop()
            }
        }
    }

    // MARK: - Layout

    private func screen(_ model: MotionTrackingViewModel) -> some View {
        VStack(spacing: 0) {
            header(model)
            ZStack {
                switch model.camera {
                case .unauthorized: card { permission }
                case .unavailable:
                    card {
                        FAEmptyState(title: String(localized: "motion.camera.unavailable.title", defaultValue: "No camera available"),
                                     message: String(localized: "motion.camera.unavailable.body", defaultValue: "Movement tracking needs an iPhone camera."),
                                     systemImage: "video.slash")
                    }
                case .failed:
                    card {
                        FAErrorState(title: String(localized: "motion.camera.failed.title", defaultValue: "The camera could not start"),
                                     message: String(localized: "motion.camera.failed.body", defaultValue: "Close other apps using the camera and try again."),
                                     retry: { Task { await model.start() } })
                        .fixedSize(horizontal: false, vertical: true)
                    }
                case .idle, .starting, .running:
                    live(model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            panel(model)
        }
    }

    private func header(_ model: MotionTrackingViewModel) -> some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .medium))
                    .frame(width: 44, height: 44, alignment: .leading).contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "action.back", defaultValue: "Go back"))
            Text(exercise.title)
                .font(FATypography.display(20, relativeTo: .title3))
                .frame(maxWidth: .infinity)
                .lineLimit(1)
            Button { showsDetails.toggle() } label: {
                Image(systemName: showsDetails ? "info.circle.fill" : "info.circle")
                    .font(.system(size: 18, weight: .medium)).frame(width: 36, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "motion.details.toggle", defaultValue: "Show tracking details"))
            .accessibilityAddTraits(showsDetails ? .isSelected : [])
            Button { Task { await model.switchCamera() } } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 18, weight: .medium)).frame(width: 36, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "motion.camera.switch", defaultValue: "Switch camera"))
            .disabled(model.result != nil)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
    }

    /// The camera image with the big status on top of it (and the skeleton when details are on).
    private func live(_ model: MotionTrackingViewModel) -> some View {
        ZStack {
            CameraPreview(session: model.captureSession)
            if showsDetails, let pose = model.pose {
                SkeletonOverlay(pose: pose, mirrored: model.usesFrontCamera)
                    .accessibilityHidden(true)
            }
            if model.camera == .starting || model.camera == .idle && model.result == nil {
                ProgressView().tint(.white)
                    .accessibilityLabel(String(localized: "motion.camera.starting", defaultValue: "Starting the camera…"))
            } else if model.result == nil {
                BigStatus(state: model.state, target: exercise.prescribedReps)
            }
            if showsDetails {
                VStack { Spacer(); DetailsReadout(model: model) }
            }
        }
    }

    private func panel(_ model: MotionTrackingViewModel) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 12) {
                if let result = model.result {
                    ResultSummary(result: result)
                    HStack(spacing: 10) {
                        FAButton(title: String(localized: "motion.again", defaultValue: "Again"), style: .secondary) {
                            Task { await model.restart() }
                        }
                        FAButton(title: String(localized: "motion.done", defaultValue: "Done")) { dismiss() }
                    }
                } else {
                    StatusLine(state: model.state, region: model.region, target: exercise.prescribedReps)
                    Text(exercise.how)
                        .font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.isCounting {
                        FAButton(title: String(localized: "motion.finish", defaultValue: "Finish"), style: .secondary) { model.finish() }
                    }
                }
                Label(String(localized: "motion.privacy", defaultValue: "Processed on your iPhone. No image or video is saved or sent."), systemImage: "lock")
                    .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var permission: some View {
        VStack(spacing: FASpacing.md) {
            FAEmptyState(title: String(localized: "motion.camera.denied.title", defaultValue: "Camera access is off"),
                         message: String(localized: "motion.camera.denied.body", defaultValue: "To count your repetitions, allow FunctionAlps to use the camera in Settings."),
                         systemImage: "video.slash")
            FAButton(title: String(localized: "motion.camera.openSettings", defaultValue: "Open Settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        FACard { content() }.padding(.horizontal, 14)
    }
}

private extension MotionTrackingViewModel {
    var isCounting: Bool {
        switch state {
        case .active, .trackingLost: true
        default: false
        }
    }
}

// MARK: - Status

/// The countdown, GO, or the count — large, over the camera image.
private struct BigStatus: View {
    let state: MotionSessionState
    let target: Int

    var body: some View {
        Group {
            switch state {
            case .countdown(let n): text("\(n)")
            case .active(_, true): text(String(localized: "motion.go", defaultValue: "GO"))
            case .active(let reps, false), .trackingLost(let reps): text("\(reps) / \(target)")
                .accessibilityLabel(MotionTrackingViewModel.countLabel(reps, of: target))
            default: EmptyView()
            }
        }
        .animation(.snappy, value: state)
    }

    private func text(_ value: String) -> some View {
        Text(value)
            .font(FATypography.display(72, relativeTo: .largeTitle))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 8)
            .contentTransition(.numericText())
    }
}

/// One line under the camera: what to do now, with an icon so the state never depends on colour.
private struct StatusLine: View {
    let state: MotionSessionState
    let region: BodyRegion
    let target: Int

    var body: some View {
        Label {
            Text(text).font(FATypography.headline).foregroundStyle(FAColor.ink)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        switch state {
        case .positioning(let hint): Self.hint(hint)
        case .holdingStill:
            region == .fullBody
                ? String(localized: "motion.visible.fullBody", defaultValue: "Full body visible – stay still for a moment…")
                : String(localized: "motion.visible.upperBody", defaultValue: "Upper body visible – stay still for a moment…")
        case .countdown: String(localized: "motion.getReady", defaultValue: "Get ready")
        case .active(let reps, _): MotionTrackingViewModel.countLabel(reps, of: target)
        case .trackingLost: String(localized: "motion.trackingLost", defaultValue: "Tracking paused – step back into view")
        case .completed: ""
        }
    }

    private var symbol: String {
        switch state {
        case .positioning(.findingYou): "person.fill.viewfinder"
        case .positioning: "arrow.up.and.down.and.arrow.left.and.right"
        case .holdingStill, .countdown: "checkmark.circle"
        case .active: "dot.radiowaves.left.and.right"
        case .trackingLost: "pause.circle"
        case .completed: "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .positioning, .trackingLost: FAColor.warning
        default: FAColor.success
        }
    }

    static func hint(_ hint: PositioningHint) -> String {
        switch hint {
        case .findingYou: String(localized: "motion.hint.findingYou", defaultValue: "Finding you… place your phone upright and step back.")
        case .showUpperBody: String(localized: "motion.hint.showUpperBody", defaultValue: "Keep your arms and hands in the frame")
        case .showFullBody: String(localized: "motion.hint.showFullBody", defaultValue: "Keep your feet in the frame")
        case .moveBack: String(localized: "motion.hint.moveBack", defaultValue: "Move further back")
        case .moveCloser: String(localized: "motion.hint.moveCloser", defaultValue: "Move slightly closer")
        case .good: String(localized: "motion.hint.good", defaultValue: "Great – stay there")
        }
    }
}

private struct ResultSummary: View {
    let result: MotionSessionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(result.completed
                     ? String(localized: "motion.complete", defaultValue: "Complete")
                     : String(localized: "motion.ended", defaultValue: "Session ended"))
                    .font(FATypography.title).foregroundStyle(FAColor.ink)
            } icon: {
                Image(systemName: result.completed ? "checkmark.circle.fill" : "stop.circle")
                    .foregroundStyle(result.completed ? FAColor.success : FAColor.inkSecondary)
            }
            Text(MotionTrackingViewModel.countLabel(result.completedReps, of: result.prescribedReps))
                .font(FATypography.headline).foregroundStyle(FAColor.ink)
            Text(Duration.seconds(result.durationSeconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))
                .font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Development details

/// The live signal behind the count: the values a threshold is tuned with.
private struct DetailsReadout: View {
    let model: MotionTrackingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let r = model.readout {
                line("\(r.signalName): \(r.value.map { String(format: "%.2f", $0) } ?? "—")  [<\(fmt(r.exitThreshold)) · >\(fmt(r.enterThreshold))]")
                line("phase: \(r.phase) · reps: \(model.reps)")
            }
            line("state: \(String(describing: model.state))")
            line(String(format: "%.0f fps · %@", model.framesPerSecond, model.usesFrontCamera ? "front" : "back"))
            if let result = model.result {
                line("\(result.detectorVersion) · \(result.trackingMode) · confidence \(fmt(result.trackingConfidence))")
            }
        }
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .padding(10)
    }

    private func line(_ s: String) -> some View { Text(s).lineLimit(1).minimumScaleFactor(0.6) }
    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }
}

/// The smoothed skeleton over the letterboxed preview.
private struct SkeletonOverlay: View {
    let pose: NormalizedPose
    let mirrored: Bool

    private static let bones: [(BodyJoint, BodyJoint)] = [
        (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist), (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.neck, .nose),
    ]

    var body: some View {
        Canvas { context, size in
            let frame = Self.imageRect(in: size, aspect: pose.imageAspect)
            func place(_ p: PosePoint) -> CGPoint {
                CGPoint(x: frame.minX + (mirrored ? 1 - p.x : p.x) * frame.width, y: frame.minY + p.y * frame.height)
            }
            var path = Path()
            for (a, b) in Self.bones {
                guard let pa = pose[a], let pb = pose[b] else { continue }
                path.move(to: place(pa))
                path.addLine(to: place(pb))
            }
            context.stroke(path, with: .color(.white.opacity(0.8)), lineWidth: 3)
            for point in pose.points.values {
                let c = place(point)
                context.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)),
                             with: .color(point.confidence >= 0.5 ? FAColor.forestMist : FAColor.warning))
            }
        }
    }

    /// Where a frame of `aspect` (w/h) sits inside `size` when letterboxed.
    static func imageRect(in size: CGSize, aspect: Double) -> CGRect {
        guard size.width > 0, size.height > 0, aspect > 0 else { return CGRect(origin: .zero, size: size) }
        if size.width / size.height > aspect {
            let w = size.height * aspect
            return CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
        }
        let h = size.width / aspect
        return CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
    }
}
