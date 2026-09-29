# Worked decomposition

One shape among many. Follow the project's own seams: by subsystem (below), by
platform against a shared wire contract, by layer in sequence, or by file batch for
mechanical sweeps. The repository decides the track count and the commands.

**Task:** add local recording, a persistent upload queue and a status UI to an app.

## Step 1: contract track, alone, accepted before anything else starts

One `worker-opus` owns `Contracts/*` and writes compilable types, including every
type they mention:

```swift
enum RecorderPhase: Sendable { case idle, recording, stopping, failed(RecorderError) }
struct StatusBoard: Sendable {
    let freeBytes: Int64
    let batteryPercent: Int
    let phase: RecorderPhase
    let queuedUploads: Int
}
protocol Recorder: AnyObject {
    var status: AsyncStream<StatusBoard> { get }   // replays the latest value to new subscribers
    func start() async throws
    func requestStop() async                       // never throws; failures surface via status
}
// plus: SegmentManifest (version, paths, atomic write, recovery), UploadQueue (idempotent enqueue, retry, cancel)
```

```
DO NOT CHANGE (deliberate): writer error -11810 is success (the OS reports it on a
clean stop); failed segments over 64 KiB are kept for recovery; requestStop() never throws.
```

## Step 2: consumers, dispatched together

| Track | Agent | Owns | Must not touch | Verify |
|---|---|---|---|---|
| Recording engine | worker-opus (concurrent lifecycle) | `Recording/Engine/*` and its tests | everything else | `xcodebuild test -scheme App -only-testing RecordingEngineTests -derivedDataPath /tmp/dd-engine` exits 0; status emits on every phase change |
| Storage and upload | worker-opus (shared data lifecycle) | `Storage/*`, `Upload/*` and tests | everything else | own tests exit 0 with `/tmp/dd-upload`; cold recovery, duplicate enqueue and network drop covered |
| Status UI | worker-sonnet (frozen state, observable result) | `UI/Status/*` and tests | everything else | every `RecorderPhase` renders; previews compile with `/tmp/dd-ui` |

Storage and upload stay in one track because their shared persistence interface is
not an existing seam. Split them only when a settled contract already separates them.

## Step 3: what waits

- **Strings and assets** start after the UI track is accepted, since its strings are
  their input. One `worker-sonnet`, if the sweep is large enough to brief.
- **App wiring and project file:** the orchestrator, or one integration worker that
  owns `App/` and `*.xcodeproj`.

## Step 4: review and finish

One reviewer on lifecycle, data correctness and the integrated behaviour (stakes:
evidence software, a silent recording failure is catastrophic). Fixes count against
each track's two rounds. After the last fix, the full suite and repository gates run
again. On-device acceptance is the user's step.
