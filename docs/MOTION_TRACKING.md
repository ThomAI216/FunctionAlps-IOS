# FunctionAlps Motion Tracking System

> **Implementation status (2026-10-02).** Milestone 1 (§47–§48) is in the app: `Sources/MotionKit/`
> (FunctionMotionKit) and `Sources/Features/Motion/`. Apple Vision 2D pose on the camera's video queue →
> `NormalizedPose` → 1€ smoothing + confidence gating → positioning check → `ChestOpenerDetector`
> (wrist separation ÷ shoulder width, hysteresis 1.25 / 1.8, 3-frame confirmation, cadence limits) inside
> `MotionSession` (positioning → hold still → 3·2·1 → GO → count → `MotionSessionResult` with
> `detector_version`). No frame is written or uploaded; the result is not saved yet (§39 phase 7).
> Reached from Settings by a long press on the version line. Rep logic is tested without a camera
> (`Tests/MotionKit/`). Next: on-device validation of the thresholds, then §39 phases 4–8.
>
> **Deviations from the brief, on purpose:** FunctionMotionKit is a folder of the app target, not a
> separate framework (the fastlane lane signs only the `FunctionAlps` target; an extra framework target
> would break release signing). `PoseProvider.detect` is synchronous and runs on the camera's video
> queue (late frames are dropped there) instead of `async`. The camera buffers are rotated upright and
> **not mirrored**, so Vision's "left wrist" is the member's left; only the on-screen preview mirrors.

---

The owner's technical brief follows unchanged.

FunctionAlps Motion Tracking System
Camera-based exercise verification, rep counting, and group challenges
Status: Technical research and implementation brief
Primary platform: iOS / SwiftUI
Recommended first pose engine: Apple Vision
Secondary / fallback engine: MediaPipe Pose Landmarker
Core principle: Process camera frames on-device, do not record or upload video, and store only structured movement results.

1. Product goal
The goal is not to build a highly precise biomechanics laboratory.
The goal is to let a FunctionAlps user put the phone down, perform a short movement or exercise snack, and have the app reliably understand:
	●	Is a person present?
	●	Is enough of the body visible?
	●	Did the person perform the intended movement?
	●	How many complete repetitions were performed?
	●	Was a timed movement held for long enough?
	●	Was the movement approximately complete?
	●	When did the session start and finish?
The system should then save a small structured result such as:
{
  "exercise_id": "pogo_jumps",
  "prescribed_reps": 20,
  "completed_reps": 20,
  "completed": true,
  "duration_seconds": 24,
  "tracking_confidence": 0.92,
  "tracking_mode": "apple_vision_2d"
}
The video itself should not be saved.
This can support:
	●	morning routines
	●	afternoon exercise snacks
	●	group programs
	●	team challenges
	●	weekly movement goals
	●	individual streaks
	●	collective targets
	●	functional capacity trends
	●	verified completion of prescribed movements

2. Recommended architecture
Use the camera as a temporary movement sensor.
AVCaptureSession
      ↓
Camera frames
      ↓
Apple Vision pose detection
      ↓
Body landmarks
      ↓
Landmark confidence filtering
      ↓
Temporal smoothing
      ↓
Normalized movement signals
      ↓
Exercise-specific state machine
      ↓
Rep / hold / completion events
      ↓
MovementSessionResult
      ↓
Supabase
No frame needs to be persisted.
The most important architectural decision is to separate:
	1.	Pose detection
	2.	Signal processing
	3.	Exercise logic
	4.	Session logging
	5.	Challenges / gamification
Do not mix exercise rules directly into the camera code.

3. Why start with Apple Vision
Apple Vision is the best first implementation for the current iOS app because:
	●	it is native to iOS
	●	it requires no external ML model download
	●	it runs on-device
	●	it integrates cleanly with AVFoundation and Swift
	●	it provides normalized body landmarks
	●	Apple already provides examples of exercise and action recognition
	●	Apple provides HumanBodyActionCounter for repetitive movement
	●	Apple Vision also supports 3D body-pose detection on supported systems
Apple’s 2D body-pose detector exposes up to 19 body points including:
	●	wrists
	●	elbows
	●	shoulders
	●	hips
	●	knees
	●	ankles
	●	nose
	●	neck
	●	root / body center
	●	eyes and ears
The important limitation for our use case is that Apple’s standard body pose does not expose detailed foot landmarks such as heel and toe.
This matters especially for calf raises.

4. Keep MediaPipe as the second engine
MediaPipe Pose Landmarker provides 33 landmarks and includes more detailed foot information.
This makes MediaPipe especially attractive for movements where:
	●	ankle motion is small
	●	heel motion matters
	●	toe / foot position matters
	●	we want a richer skeleton
	●	we later want Android support
Do not necessarily switch the entire app to MediaPipe.
A good long-term architecture is:
PoseProvider protocol
    ├── AppleVisionPoseProvider
    └── MediaPipePoseProvider
Then the exercise engine consumes our own normalized landmark format and does not care which detector produced the data.
That gives FunctionAlps freedom to use Apple Vision for most movements and MediaPipe for movements where Apple’s landmarks are insufficient.

5. Do not build every exercise using joint angles
For this product, most exercises can be recognized using relative positions and temporal movement patterns rather than exact joint angles.
Examples:
	●	wrist above shoulder
	●	wrist distance greater than shoulder width
	●	body center moved upward
	●	hips moved downward then returned
	●	ankle / body center oscillated vertically
	●	hands moved from front/closed to wide/open
	●	left and right wrists moved in sequence
	●	person returned to a neutral pose
This is easier to tune and is usually enough for completion verification.
Joint angles can still be calculated when useful, but they should not be the conceptual foundation of the first version.

6. The key abstraction: Movement Signature
Each exercise should have a Movement Signature.
A movement signature defines:
Required joints
Camera orientation
Starting state
Movement phases
Signals to monitor
Minimum movement amplitude
Minimum confidence
Minimum phase duration
Completion transition
Cooldown
Optional anti-cheat conditions
Example:
exercise: chest_opener
required_joints:
  - left_wrist
  - right_wrist
  - left_shoulder
  - right_shoulder

signal:
  type: normalized_wrist_separation

states:
  - CLOSED
  - OPEN

transition:
  CLOSED -> OPEN:
    wrist_distance_ratio > 1.8

  OPEN -> CLOSED:
    wrist_distance_ratio < 1.25
    count_rep: true
This is much easier to maintain than hard-coding every exercise inside one giant detector.

7. Normalize everything to the person’s body
Never rely directly on pixel distances.
A person may be:
	●	1.5 metres from the camera
	●	3 metres from the camera
	●	tall
	●	short
	●	using portrait or landscape mode
Use body measurements as scale references.
Useful scale values:
shoulderWidth
hipWidth
torsoLength
bodyHeightEstimate
Then compute signals such as:
wristSeparation / shoulderWidth

verticalHipMovement / torsoLength

wristHeightRelativeToShoulder / torsoLength
This makes thresholds much more portable between users.

8. Anti-jitter strategy
Camera jitter and landmark jitter must be handled at several levels.
8.1 Confidence gating
Ignore a landmark if confidence is too low.
Example:
guard point.confidence > minimumConfidence else {
    return .unreliableFrame
}
Do not invent missing positions.

8.2 Temporal smoothing
Use a One Euro Filter per tracked coordinate.
The One Euro Filter is particularly suitable because:
	●	when the user is almost still, it smooths aggressively
	●	when the user moves quickly, it becomes more responsive
	●	it introduces less perceived lag than a heavy moving average
MediaPipe itself uses One Euro style landmark smoothing internally in parts of its pose stack.
Start with a simple implementation that smooths x and y independently for each required joint.

8.3 Hysteresis
Never use a single threshold to decide both entry and exit.
Bad:
OPEN if wrist distance > 1.5
CLOSED if wrist distance < 1.5
The signal may oscillate around 1.5 and generate multiple reps.
Better:
OPEN when ratio > 1.7
CLOSED when ratio < 1.3
The gap is deliberate.

8.4 Consecutive-frame confirmation
Require a condition to be true for several frames before changing state.
Example:
candidate OPEN
candidate OPEN
candidate OPEN
candidate OPEN
→ confirmed OPEN
For slower movements, 3-5 frames can work well.
For fast pogo jumps, use fewer frames and rely more on velocity / direction changes.

8.5 Minimum time between reps
Every exercise should have a plausible cadence range.
Example:
minimumRepDuration = 0.35 seconds
maximumRepDuration = 8 seconds
Ignore physically implausible duplicate events.

8.6 Reset after tracking loss
If the person disappears or important landmarks are unavailable for too long:
do not count
freeze state briefly
then reset to WAITING_FOR_USER if tracking loss persists
Never count a transition created by the detector reacquiring the body.

9. Exercise 1: Pogo jumps
Feasibility
Feasible with Apple Vision.
Pogo jumps are fast, relatively small vertical movements in which the body rises and lands repeatedly with limited knee flexion.
The most useful signal is not necessarily the ankle joint itself.
Use:
	●	midpoint between left/right hips
	●	root / body center when available
	●	shoulder midpoint as secondary confirmation
	●	ankle midpoint as optional confirmation
Suggested signal
During a short calibration window, estimate standing baseline:
baselineHipY
baselineShoulderY
Normalize vertical displacement by torso length:
verticalRise =
    (baselineHipY - currentHipY) / torsoLength
Remember that image-coordinate orientation may need conversion depending on the API.
State machine
GROUND
  ↓ body center rises above threshold
AIR
  ↓ body center falls toward baseline
LANDING
  ↓ stable near baseline
GROUND + rep
Simpler version:
LOW -> HIGH -> LOW = 1 rep
with:
	●	hysteresis
	●	minimum amplitude
	●	velocity direction change
	●	minimum rep duration
Important
Do not try to detect the exact instant the foot leaves the floor in v1.
The camera does not need to prove biomechanical flight time.
It only needs to identify a repeated whole-body vertical bounce consistent with the prescribed pogo movement.
Recommended constraints
	●	full body visible
	●	camera reasonably stable
	●	phone placed on fixed support
	●	user starts from a stable standing position
	●	1 second calibration before counting
Difficulty
Medium
Main challenge:
	●	movement amplitude can be small
	●	user cadence can be fast
	●	excessive smoothing can erase the signal
This exercise should use lighter smoothing than slow exercises.

10. Exercise 2: Calf raises
Feasibility with Apple Vision
Possible, but this is one of the exercises that should be used to benchmark Apple Vision against MediaPipe.
A calf raise may produce only a small change in the Apple ankle landmark.
Apple’s standard pose skeleton does not provide heel and toe points.
Therefore the best Apple Vision signal is likely:
	●	hip midpoint vertical rise
	●	shoulder midpoint vertical rise
	●	minimal knee movement
	●	optional ankle trajectory
State machine
DOWN
  ↓ body center rises enough
UP
  ↓ body center returns near baseline
DOWN + rep
Additional guards:
knees approximately stable
torso approximately vertical
left/right body rise synchronized
No exact angle analysis is required.
Calibration
Before the first rep:
measure 0.5-1.0 sec of standing baseline
Estimate:
baselineHipY
baselineShoulderY
signalNoise
Set the movement threshold above observed idle noise.
For example:
riseThreshold =
    max(defaultRiseThreshold,
        idleNoise * multiplier)
This is much better than using exactly the same threshold for every phone/camera/distance combination.
MediaPipe advantage
MediaPipe exposes detailed foot landmarks including heel / foot indices.
If Apple Vision struggles with calf raises in testing, route this exercise to MediaPipe rather than redesigning the whole app.
Difficulty
Medium to difficult using Apple only
Medium using MediaPipe
This should be one of the earliest validation exercises.

11. Exercise 3: Chest opener
Assumption: the exercise consists of opening the arms/chest from a more closed/front position into a wide position and returning.
Feasibility
Very easy relative to the other requested exercises.
Use:
	●	left wrist
	●	right wrist
	●	shoulders
	●	elbows optionally
Compute:
wristSeparationRatio =
    distance(leftWrist, rightWrist) / shoulderWidth
Optional signal:
elbowSeparationRatio
State machine
CLOSED
  ↓ wrists separate beyond OPEN threshold
OPEN
  ↓ wrists return below CLOSED threshold
CLOSED + rep
The app can tolerate many different arm shapes.
It does not need to demand a specific shoulder angle.
Difficulty
Easy
This should be in the first prototype.

12. Exercise 4: “The wave”
This needs a final exercise definition before production because “wave” can describe different motions.
However, a standardized FunctionAlps wave can still be tracked.
For example, if the movement is:
left arm rises
→ both arms overhead
→ right arm lowers
→ return
or a sequential arm wave, define it as ordered temporal states.
Example:
START
→ LEFT_HIGH
→ BOTH_HIGH
→ RIGHT_HIGH
→ START
Signals:
	●	wrist relative to shoulder height
	●	left/right wrist velocity
	●	wrist separation
	●	sequence timing
For a fixed exercise, a deterministic state machine is preferable.
If the wave is intentionally free-form and has many valid styles, Apple’s action classifier or a custom temporal classifier becomes more appropriate later.
Difficulty
Easy to medium if the movement is standardized
Medium to difficult if many variations must count as valid

13. Exercise 5: Squat to overhead
Feasibility
Very good with Apple Vision.
This is a useful example of a compound movement.
The app should not simply count a squat and an arm raise independently.
Instead define one complete sequence.
Possible states:
READY
→ SQUAT
→ RISING
→ OVERHEAD
→ READY
Signals:
Squat signal
Use hip / root vertical displacement:
hipDrop / torsoLength
Knee position can be a secondary signal.
Overhead signal
leftWrist above leftShoulder
AND
rightWrist above rightShoulder
or, for an easier version:
mean wrist Y sufficiently above mean shoulder Y
Rep completion
One rep should count only after:
user entered SQUAT
AND
returned upward
AND
reached OVERHEAD
AND
returned to READY
This prevents a random arm raise from counting.
Difficulty
Easy to medium
Excellent first compound exercise.

14. Other exercises that should be easy to add
The same architecture can support:
Arm circles
Use wrist trajectory around shoulder position.
Shoulder raises
Use wrist vertical position relative to shoulders.
Standing knee raises
Use knee height relative to hip.
Marching
Alternate left/right knee raises.
Sit-to-stand
Use hip vertical displacement + knee state.
Side steps
Track lateral ankle / hip displacement.
Side reaches
Track wrist lateral distance relative to shoulder.
Lunges
Use vertical hip drop + front/back leg configuration.
Jumping jacks
Use:
	●	arms up/down
	●	feet apart/together
	●	vertical body bounce
Dead bug
Possible, but camera positioning becomes more important.
Bird dog
Possible with side view and slower movement.
Wall push-ups
Track upper-body distance/arm cycle.
Regular push-ups
Standard pose-counter pattern.
Plank
Timed hold rather than rep count.

15. Rep counting architecture
Each exercise should return one of:
enum MovementUpdate {
    case waiting
    case positioning
    case tracking
    case rep(Int)
    case hold(TimeInterval)
    case completed
    case trackingLost
}
The UI should not need to understand the underlying exercise rules.

16. Suggested Swift data model
struct PosePoint {
    let x: Double
    let y: Double
    let confidence: Double
}

enum BodyJoint: Hashable {
    case leftWrist
    case rightWrist
    case leftElbow
    case rightElbow
    case leftShoulder
    case rightShoulder
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
    case neck
    case root
}

struct NormalizedPose {
    let timestamp: TimeInterval
    let points: [BodyJoint: PosePoint]
}

protocol PoseProvider {
    func process(
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval
    ) async throws -> NormalizedPose?
}

protocol MovementDetector {
    mutating func process(
        pose: NormalizedPose
    ) -> MovementUpdate

    mutating func reset()
}
This abstraction is important.
The movement detectors should never import Apple Vision directly.

17. Suggested internal module
FunctionMotionKit/
│
├── Camera/
│   ├── CameraSessionManager.swift
│   └── CameraPreviewView.swift
│
├── Pose/
│   ├── PoseProvider.swift
│   ├── AppleVisionPoseProvider.swift
│   ├── NormalizedPose.swift
│   └── PoseQualityEvaluator.swift
│
├── Filtering/
│   ├── OneEuroFilter.swift
│   ├── PoseSmoother.swift
│   └── SignalDebouncer.swift
│
├── Signals/
│   ├── PoseMetrics.swift
│   ├── BodyScaleNormalizer.swift
│   └── VelocityEstimator.swift
│
├── Exercises/
│   ├── MovementDetector.swift
│   ├── PogoJumpDetector.swift
│   ├── CalfRaiseDetector.swift
│   ├── ChestOpenerDetector.swift
│   ├── WaveDetector.swift
│   ├── SquatOverheadDetector.swift
│   └── ...
│
├── Session/
│   ├── MotionSession.swift
│   ├── MotionSessionResult.swift
│   └── MotionSessionCoordinator.swift
│
└── UI/
    ├── BodyPositioningOverlay.swift
    ├── RepCounterOverlay.swift
    └── MotionTrackingView.swift

18. Do not require a skeleton overlay in production
A skeleton is useful for:
	●	development
	●	debugging
	●	calibration
	●	internal testing
But the user-facing product can remain extremely simple:
Move back a little

✓ Full body detected

Ready

3
2
1

GO

12 / 20
Optional visual feedback:
● Tracking
or a minimal body outline.
This avoids making the experience feel like surveillance.

19. Privacy design
The ideal privacy model is:
Camera permission
↓
Frames processed in RAM
↓
Pose coordinates extracted
↓
Frames discarded immediately
↓
Only movement events stored
Do not persist:
	●	photos
	●	raw camera frames
	●	videos
	●	face crops
Unless a completely separate future feature explicitly requires it and the user gives specific consent.
The server should receive only structured events.
Example:
{
  "movement_session_id": "...",
  "user_id": "...",
  "exercise_id": "chest_opener",
  "started_at": "...",
  "ended_at": "...",
  "prescribed_reps": 10,
  "verified_reps": 10,
  "completion": true,
  "confidence": 0.95,
  "pose_engine": "apple_vision"
}

20. Positioning flow before each exercise
A major source of tracking failure is poor camera setup.
Do not start counting immediately.
Use a positioning phase:
1. Find person
2. Check required joints
3. Check body size in frame
4. Check that required body region is visible
5. Require stable tracking for ~0.5-1 sec
6. Calibrate baseline
7. Countdown
8. Start exercise
User feedback can be:
Move further back

Move slightly closer

Keep your feet in the frame

Turn sideways

Great - stay there
Each exercise can specify its preferred camera orientation:
enum CameraViewRequirement {
    case front
    case side
    case either
}

21. Dynamic calibration
For subtle movements, calibration is important.
At session start, collect a short baseline.
Example:
30 frames of quiet standing
Calculate:
mean signal
standard deviation / noise
body scale
Then derive exercise thresholds relative to the user.
Instead of:
vertical rise must be exactly 0.04
use:
requiredRise =
    max(minimumBiomechanicalThreshold,
        baselineNoise * 4)
This reduces false counts from:
	●	camera shake
	●	breathing
	●	minor posture sway
	●	landmark noise

22. State-machine design
Use finite state machines (FSMs).
Do not write logic like:
if signal > threshold {
    reps += 1
}
Correct pattern:
WAITING
→ READY
→ ACTIVE_PHASE
→ RETURN_PHASE
→ READY + REP
Each exercise has its own state machine.
Example generic two-phase rep:
enum RepState {
    case neutral
    case active
}

if state == .neutral && signal > enterThreshold {
    activeFrameCount += 1

    if activeFrameCount >= requiredFrames {
        state = .active
        activeFrameCount = 0
    }
}

if state == .active && signal < exitThreshold {
    returnFrameCount += 1

    if returnFrameCount >= requiredFrames {
        state = .neutral
        reps += 1
        returnFrameCount = 0
    }
}

23. Compound-movement state machines
For squat-to-overhead:
READY
  |
  | hip drops
  v
SQUAT
  |
  | hip rises
  v
RISING
  |
  | wrists above shoulders
  v
OVERHEAD
  |
  | wrists return + body stable
  v
READY -> +1 REP
If a user only performs the squat:
no rep
If a user only raises the arms:
no rep
This is exactly why a temporal state machine is more useful than a single angle threshold.

24. Fast-movement detector for pogo jumps
Pogo jumps should probably use a signal-cycle detector rather than a heavily debounced slow-state detector.
Example signal:
centerY(t)
Filter lightly.
Calculate vertical velocity:
velocityY(t) =
    (centerY(t) - centerY(t-1)) / dt
Look for:
rise
→ peak
→ fall
→ baseline
A rep requires:
minimum peak amplitude
minimum time since previous peak
return toward baseline
Pseudo logic:
switch state {

case .ground:
    if rise > takeoffThreshold && velocity < -velocityThreshold {
        state = .rising
    }

case .rising:
    if velocity >= 0 {
        state = .falling
    }

case .falling:
    if nearBaseline && minimumCycleTimeReached {
        reps += 1
        state = .ground
    }
}
Coordinate direction must be adjusted to the actual normalized coordinate system.

25. Adaptive exercise definitions
Eventually, exercise rules can be stored as data.
Example:
{
  "id": "chest_opener",
  "tracking_type": "state_machine",
  "camera_view": "front",
  "required_joints": [
    "left_wrist",
    "right_wrist",
    "left_shoulder",
    "right_shoulder"
  ],
  "signal": {
    "type": "distance_ratio",
    "point_a": "left_wrist",
    "point_b": "right_wrist",
    "scale": "shoulder_width"
  },
  "states": {
    "closed": {
      "max": 1.3
    },
    "open": {
      "min": 1.7
    }
  }
}
Not every detector needs to be fully data-driven in v1.
But the data model should allow this later.

26. Apple’s HumanBodyActionCounter
Apple provides HumanBodyActionCounter, which consumes windows of body poses and produces cumulative repetition counts for repetitive / periodic body movement.
This is useful as:
	●	a reference implementation
	●	an experiment
	●	a generic fallback for strongly periodic exercises
	●	a benchmark against our custom counters
However, for FunctionAlps, custom movement detectors have several advantages:
	●	we know which exercise the user is supposed to perform
	●	we can use exercise-specific signals
	●	we can control false positives
	●	we can support unusual movement snacks
	●	we can explain why a rep was or was not counted
	●	we can tune movement-specific camera requirements
Therefore:
Use Apple Vision as the pose engine.
Use FunctionMotionKit as the movement engine.

27. Apple’s Action Classifier
Apple also supports action classification from body-pose sequences.
This becomes useful later when we want to answer:
What movement is this person doing?
instead of:
Did this person complete the specific movement we already prescribed?
For FunctionAlps v1, action classification is unnecessary complexity.
The prescribed-exercise context makes deterministic detectors much easier.
Potential future use cases:
	●	automatically identify which exercise is being performed
	●	recognize free-form movement patterns
	●	classify complex sequences
	●	distinguish similar exercise variants

28. Group challenges
The movement engine opens a strong group-program feature.
Examples:
TEAM ALPINE
Goal: 2,000 verified squats this week
Current: 1,437
or:
Today's group goal:
500 pogo jumps

318 completed
182 remaining
or:
Women 40-60 Group
vs.
Men 40-60 Group

Weekly Movement Challenge

29. Recommended challenge design
Avoid encouraging unlimited volume.
Especially in a health program, the challenge mechanic should reward adherence and participation rather than who can perform the most repetitions indefinitely.
Better mechanics:
Capped individual contribution
Maximum challenge contribution:
50 squats / person / day
A person can exercise more, but extra reps do not increase the team score.
Completion points
Morning routine completed = 5 points
Afternoon snack completed = 5 points
Group session attended = 10 points
Collective progress
If the entire group reaches 90% weekly adherence:
everyone unlocks the reward
Team consistency
Every participant completes at least
4 movement snacks this week
This avoids one highly active person carrying the whole group.

30. Possible rewards
Examples discussed for FunctionAlps:
	●	supplement sample
	●	discount
	●	voucher
	●	partner reward
	●	wellness experience
	●	bonus workshop
	●	group experience
	●	app badge / unlock
If using physical rewards, create eligibility rules around safe participation rather than extreme exercise volume.

31. Challenge database model
Suggested Supabase tables:
movement_sessions
challenge_definitions
challenge_memberships
challenge_contributions
challenge_team_totals
Example movement_sessions:
id
user_id
exercise_id
started_at
completed_at
prescribed_reps
verified_reps
duration_seconds
completion_status
tracking_confidence
tracking_engine
app_version
detector_version
Example challenge_contributions:
id
challenge_id
user_id
movement_session_id
raw_value
credited_value
created_at
Store both:
raw_value = 80 squats
credited_value = 50
if the daily challenge cap is 50.
This keeps scoring rules auditable.

32. Detector versioning
Every saved movement session should include:
detector_version
Example:
chest_opener_v1.2
This is important because thresholds will change over time.
Without detector versioning, historical data can become difficult to interpret.

33. Confidence model
Do not pretend the system knows more than it does.
A simple session confidence can combine:
landmark availability
landmark confidence
percentage of frames tracked
camera stability
signal amplitude relative to noise
number of interrupted frames
Example:
trackingConfidence = 0.94
This is not a clinical movement-quality score.
It means:
How confident are we that the camera reliably observed the exercise?

34. Anti-cheat without becoming intrusive
The goal is not to create a surveillance system.
Simple safeguards are enough:
	●	full required body region visible
	●	plausible movement cadence
	●	complete state transition
	●	minimum signal amplitude
	●	stable person tracking
	●	ignore sessions with severe tracking loss
	●	challenge contribution caps
Do not build identity recognition or facial verification for this feature.

35. Testing strategy
Rep counting should be testable without a camera.
This is very important.
Each detector should consume plain normalized pose / movement signals.
Then unit tests can feed synthetic sequences.
Example:
CLOSED
CLOSED
TRANSITION
OPEN
OPEN
TRANSITION
CLOSED
Expected:
1 rep
Test:
	●	correct rep
	●	incomplete rep
	●	pause at top
	●	pause at bottom
	●	jitter around threshold
	●	tracking loss
	●	fast movement
	●	slow movement
	●	partial range
	●	random unrelated movement
	●	person leaves frame
	●	pose reacquired
Several open-source projects use exactly this separation between pose extraction and state-machine logic.

36. Real-world validation dataset
Create an internal validation set.
For each exercise, record test clips from consenting testers solely for development.
Test diversity:
	●	different heights
	●	different body shapes
	●	loose clothing
	●	dark clothing
	●	bright room
	●	darker room
	●	near camera
	●	further camera
	●	slightly diagonal camera
	●	fast reps
	●	slow reps
	●	imperfect reps
Manually label true rep counts.
Then calculate:
count error
false positives
missed reps
tracking-loss percentage
The production app still does not need to store video.
Development clips can be handled separately with explicit tester consent.

37. First prototype exercises
Recommended prototype set:
1. Chest opener
Why:
	●	simple
	●	low ambiguity
	●	excellent first test of state-machine architecture
2. Squat to overhead
Why:
	●	compound movement
	●	tests multi-phase logic
	●	obvious visual movement
3. Pogo jumps
Why:
	●	fast movement
	●	tests temporal smoothing / velocity logic
4. Calf raises
Why:
	●	subtle movement
	●	intentionally tests Apple Vision’s limits
These four together are a very strong technical benchmark.
If they work reliably, most FunctionAlps exercise snacks become straightforward.

38. Prototype acceptance criteria
For each movement:
Functional
	●	detects person
	●	guides user into camera position
	●	begins after stable pose
	●	counts complete reps
	●	rejects obvious incomplete cycles
	●	survives small tracking interruptions
	●	resets safely after large tracking interruption
Privacy
	●	no frame written to disk
	●	no video uploaded
	●	no image transmitted to Supabase
	●	only structured movement result stored
Performance
Target:
	●	live preview remains smooth
	●	pose inference is performed off the main UI thread
	●	counting feedback feels effectively immediate
	●	battery / thermal behavior acceptable during short sessions

39. Development phases
Phase 1 - Skeleton
Build:
AVCaptureSession
→ VNDetectHumanBodyPoseRequest
→ normalized landmarks
→ debug skeleton overlay
Goal:
stable live body tracking.

Phase 2 - Motion signals
Build:
body scale
wrist distance
hip midpoint
shoulder midpoint
vertical velocity
One Euro smoothing
confidence gating
Display development values on-screen.

Phase 3 - First detector
Implement:
ChestOpenerDetector
This validates the entire architecture.

Phase 4 - Compound detector
Implement:
SquatOverheadDetector

Phase 5 - Fast detector
Implement:
PogoJumpDetector

Phase 6 - Subtle-motion benchmark
Implement:
CalfRaiseDetector
Compare Apple Vision results against MediaPipe if necessary.

Phase 7 - Session integration
Connect:
MovementSession
→ existing exercise card
→ Supabase movement_sessions

Phase 8 - Challenges
Build group challenge aggregation only after verified session logging is reliable.

40. Useful open-source projects
RepCounterSDK
GitHub:
https://github.com/NazarKozak/RepCounterSDK
Why it matters:
	●	native Swift / Apple Vision
	●	on-device
	●	rep counter architecture
	●	hysteresis
	●	custom exercise DSL
	●	SwiftUI demo
	●	MIT license
	●	separates landmarks and counting logic
Particularly relevant files / concepts:
VisionPoseSource
PoseLandmarks
ThresholdCounter
ThresholdTimer
ExerciseSpec
RepDetector
This is the strongest direct starting reference for the iOS implementation.

CondadosAI pose-rep-counting
GitHub:
https://github.com/CondadosAI/pose-rep-counting
Why it matters:
	●	explicitly investigates rep-counting failure modes
	●	compares EMA, One Euro, and Kalman-style filtering
	●	demonstrates how jitter can cause false reps
	●	separates:
	●	landmark extraction
	●	signals
	●	filters
	●	finite state machine
	●	contains tests and experiments
It is Python / MediaPipe based rather than native Swift, but the architecture is excellent reference material.

MediaPipe jumping-jack counter
GitHub:
https://github.com/muhadkprsnl/repsCount
Why it matters:
	●	scale-normalized movement signals
	●	explicit state machine
	●	consecutive-frame confirmation
	●	confidence handling
	●	jump detection using hip vertical movement
	●	handles phase timing mismatch
	●	unit-tests the movement logic separately from pose extraction
The jump-detection approach is particularly relevant to FunctionAlps pogo jumps.

AI Sport mobile
GitHub:
https://github.com/Gakiwoo/ai-sport-mobile
Why it matters:
	●	mobile camera exercise tracking
	●	MediaPipe Pose
	●	jump rope
	●	jumping jacks
	●	vertical jump
	●	state machines
	●	Kalman filtering
	●	adaptive calibration
Useful reference for fast vertical movement.

AI Gym Coach
GitHub:
https://github.com/Feki-Tech/ai-gym-coach
Why it matters:
	●	pose estimation
	●	One Euro smoothing
	●	per-exercise finite state machines
	●	rep counting
	●	tempo
	●	form rules
	●	JSON workout logs
	●	includes a native SwiftUI / Apple Vision implementation
The architecture:
camera
→ pose
→ smoothing
→ movement signal
→ FSM
→ feedback
→ structured log
is very close to the recommended FunctionAlps architecture.

One Euro Filter reference
Official / reference implementations:
https://github.com/casiez/OneEuroFilter
Swift implementation example:
https://github.com/masterchef8/OneEuroFilter
Use this as a reference rather than blindly importing an old package.
The filter itself is small enough that we can own a clean, tested Swift implementation inside FunctionMotionKit.

QuickPose
GitHub:
https://github.com/quickpose/quickpose-ios-sdk
Website:
https://quickpose.ai/
QuickPose is a commercial / production-oriented pose-estimation SDK built for mobile fitness.
It provides:
	●	pose estimation
	●	rep counting
	●	range of motion
	●	fitness-oriented features
It may be useful as:
	●	competitive reference
	●	rapid prototype benchmark
	●	fallback if maintaining our own biomechanics layer becomes expensive
However, FunctionAlps can build the first version without it.

41. Apple references
Vision body pose detection
https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest
Apple detects body poses and exposes recognized joints with confidence values.

Apple body landmarks
https://developer.apple.com/documentation/vision/body-landmarks
Apple’s standard body pose exposes up to 19 body points.

3D body pose
https://developer.apple.com/documentation/vision/identifying-3d-human-body-poses-in-images
Apple supports 3D pose detection and exposes 17 major joints in 3D.
This can be explored later, but is not required for v1.

Create ML Components repetition counting
Search Apple Developer documentation for:
HumanBodyActionCounter
Counting human body action repetitions in a live video feed
Apple demonstrates:
camera
→ pose extraction
→ pose selection
→ sliding time windows
→ HumanBodyActionCounter
→ cumulative rep count

Live action classification
https://developer.apple.com/documentation/createml/detecting-human-actions-in-a-live-video-feed
Apple’s sample recognizes actions such as:
	●	jumping jacks
	●	lunges
	●	burpees
using pose sequences over time.

42. Recommended engineering decision
v1
Apple Vision
+
our own FunctionMotionKit
+
exercise-specific finite state machines
+
One Euro smoothing
+
dynamic calibration
v1.5
Add:
MediaPipePoseProvider
only if required by subtle-foot movements or Android.
v2
Consider:
Action Classifier
for recognizing free-form or unknown movements.

43. Initial FunctionAlps exercise schema
The existing exercise library can gain tracking metadata.
Example:
{
  "id": "pogo_jumps",
  "name": "Pogo Jumps",
  "tracking": {
    "enabled": true,
    "detector": "pogo_jump_v1",
    "mode": "repetitions",
    "camera_view": "front",
    "required_body_region": "full_body",
    "preferred_pose_engine": "apple_vision",
    "target": 20
  }
}
Calf raise could later say:
{
  "tracking": {
    "preferred_pose_engine": "mediapipe"
  }
}
without changing the rest of the product.

44. Suggested session UX
Pogo Jumps

20 repetitions

[ Start ]
Then:
Camera opens

Finding you...
Then:
Move slightly further back
Then:
✓ Full body visible

Stay still for a moment...
Then:
3
2
1
GO
Then:
7 / 20
At completion:
20 / 20

Complete ✓
Then the camera closes immediately.

45. Suggested challenge UX
THIS WEEK

Mountain Team Challenge

Goal
2,000 verified movement reps

██████████████░░░
1,643 / 2,000

357 to go
Individual contribution:
Your contribution
145 reps

Daily scoring cap
50 reps / exercise
Group activity can show:
8 / 10 members completed
today's movement snack
Avoid public health / performance rankings unless the participant explicitly opts into that social feature.

46. Important product distinction
There are three different things the system could measure:
Completion
Did the user perform the movement?
Quantity
How many repetitions / seconds?
Quality
How technically good was the movement?
For v1, focus on:
Completion + Quantity
Do not overpromise movement-quality assessment.
Later, selected exercises can gain:
	●	approximate range
	●	tempo
	●	symmetry
	●	consistency

47. Recommended first coding-agent task
Give the coding agent this scope:
> Build a standalone `FunctionMotionKit` Swift module for the existing iOS app. Use `AVCaptureSession` and Apple Vision `VNDetectHumanBodyPoseRequest` to process live camera frames on-device. Do not save or upload frames. Convert Vision landmarks into a framework-independent `NormalizedPose` type. Add confidence gating, a One Euro smoother, body-scale normalization, and an exercise-independent state-machine interface. Implement a debug screen showing the live skeleton and tracked signal values. Then implement `ChestOpenerDetector` as the first exercise using wrist separation normalized by shoulder width with hysteresis and consecutive-frame confirmation. Add unit tests that feed synthetic `NormalizedPose` sequences into the detector without using the camera.
After that works:
> Add `SquatOverheadDetector` using a multi-phase state machine.
Then:
> Add `PogoJumpDetector` using calibrated vertical hip / shoulder displacement and vertical velocity.
Then:
> Add `CalfRaiseDetector`, test it on real devices, and compare the Apple Vision signal against MediaPipe Pose Landmarker if reliability is insufficient.

48. Definition of done for the first milestone
The first milestone is complete when:
	1.	User opens a chest-opener exercise.
	2.	Camera permission is handled.
	3.	App finds the body.
	4.	App tells user when positioning is acceptable.
	5.	No camera frame is written to disk.
	6.	Wrist and shoulder landmarks are detected.
	7.	Landmarks are smoothed.
	8.	A full close → open → close cycle counts exactly once.
	9.	Jitter while holding the open position does not add reps.
	10.	Tracking loss does not add reps.
	11.	The session returns a structured MotionSessionResult.
	12.	A unit test can reproduce all rep logic without opening a camera.
	13.	The detector version is saved with the result.

49. Strategic recommendation
Do not begin by building “AI exercise recognition.”
Build a reliable movement sensor.
The user already selected the exercise.
That dramatically reduces the problem.
The first FunctionAlps motion system only needs to know:
The app prescribed movement X.

Is the person's live body-pose sequence sufficiently consistent
with movement X to count a repetition or completion?
This can be implemented with deterministic geometry, temporal filtering, and small finite state machines.
Machine-learning action recognition can be added later where it genuinely improves the product.

50. Research summary
The most reusable lessons from the existing projects are:
	1.	Pose estimation is not the hard part.
The important engineering work is turning noisy landmarks into stable movement events.
	2.	Separate pose detection from rep logic.
This allows unit testing and allows Apple Vision / MediaPipe to be swapped.
	3.	Normalize movement to the user’s body size.
Do not use raw pixels.
	4.	Use temporal filtering.
One Euro filtering is particularly appropriate for interactive motion tracking.
	5.	Use hysteresis.
A single threshold is a common source of duplicate reps.
	6.	Use finite state machines.
A full movement cycle should be required before a rep counts.
	7.	Use dynamic calibration for small movements.
This is especially important for pogo jumps and calf raises.
	8.	Treat subtle foot exercises as an Apple Vision benchmark.
MediaPipe can be selectively introduced if its additional foot landmarks materially improve reliability.
	9.	Store movement results, not camera footage.
The privacy architecture can be a product advantage.
	10.	Build challenges on verified sessions, not raw camera data.
The social layer should remain entirely separate from computer vision.

51. Immediate build order
1. Apple Vision camera skeleton
2. Framework-independent NormalizedPose
3. Pose confidence evaluator
4. One Euro smoothing
5. Body-scale normalization
6. Generic detector interface
7. Chest opener
8. Squat to overhead
9. Pogo jumps
10. Calf raises
11. Session persistence
12. Group challenge engine
13. MediaPipe comparison only where needed
This is the recommended path for FunctionAlps.
