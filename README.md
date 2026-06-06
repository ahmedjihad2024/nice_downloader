# Nice Downloader

A clean, extensible file downloader for Flutter — pause / resume / cancel, resume-after-restart persistence, pluggable retry policies, and an **interceptor pipeline** that lets you hook into every step of a download's lifecycle.

https://github.com/user-attachments/assets/e2c462d3-dcfa-4811-9dea-8f729b667fb3

## Features

* ⚡ **Segmented downloads (IDM-style)** — large files are split into up to 8 parallel connections, each downloading its own byte range, for significantly faster transfers
* ⏸️ **Pause / Resume / Cancel** — resumes from the exact byte offset using HTTP range requests (per segment for segmented downloads)
* 💾 **Resume after restart** — download state is persisted (Hive CE by default) and picked up in the next session
* 🔌 **Interceptors** — observe or modify every lifecycle step (create, start, chunk, pause, resume, complete, cancel, error) without touching the engine
* 🔁 **Retry policies** — exponential backoff out of the box; mid-stream connection drops auto-resume from the bytes already on disk
* 🚦 **Speed limiting** — cap a download's total speed (across all its segments) and change it live; no limit set = max speed
* 🛡️ **Integrity verification** — downloaded bytes are checksummed (CRC-32); if the partial file is edited, truncated or corrupted while paused, resume detects it and re-fetches only the damaged range
* 📡 **Pluggable everything** — transport, storage, connectivity check, file writing and retry behavior are all interfaces with sensible defaults
* 📊 **Rich progress** — immutable snapshots with percent, readable sizes (`12.5 MB`) and speed (`1.2 MB/s`)

## Quick start

```dart
final manager = DownloadManager();

final task = await manager.createDownload(
  url: 'https://example.com/video.mp4',
  directory: (await getDownloadsDirectory())!.path,
  fileName: 'my_video', // optional — server-suggested name used otherwise
);

task.progressStream.listen((progress) {
  print('${progress.status.name} ${progress.percent}% '
      '(${progress.readableDownloaded} / ${progress.readableTotal} '
      'at ${progress.readableSpeed ?? '-'})');
});

await task.start();

// Later…
await task.pause();
await task.resume();
await task.cancel(); // deletes the partial file + persisted state

// Speed control — applies instantly, even mid-download:
task.speedLimit = 1024 * 1024; // cap at 1 MB/s
task.speedLimit = null;        // back to max speed (the default)
```

## Configuration

Everything is configured once on the manager and applies to all downloads it creates:

```dart
final manager = DownloadManager(
  config: DownloadConfig(
    interceptors: [LoggingInterceptor()],
    retryPolicy: ExponentialBackoffRetryPolicy(maxRetries: 5),
    waitForConnection: true,           // block until online instead of failing
    progressInterval: Duration(milliseconds: 250),
    segmentPlanner: DefaultSegmentPlanner(maxSegments: 8), // parallel connections
    // segmentPlanner: NoSegmentationPlanner(),   // force single-stream
    // speedLimit: 2 * 1024 * 1024,               // cap at 2 MB/s (default: max)
    // repository: InMemoryDownloadRepository(),  // disable persistence
    // client: MyCustomDownloadClient(),          // custom transport
    // connectivityChecker: MyChecker(),          // e.g. connectivity_plus
  ),
);
```

## Segmented downloads — how the speed comes from

When the server supports HTTP range requests (`206 Partial Content`) and the file is large enough, the download is automatically split — exactly like IDM on Windows:

```
File: 100 MB → 4 segments

Connection 1 ──▶ bytes 0–25 MB    ──┐
Connection 2 ──▶ bytes 25–50 MB   ──┤── all write into ONE pre-allocated
Connection 3 ──▶ bytes 50–75 MB   ──┤   file, each at its own offset
Connection 4 ──▶ bytes 75–100 MB  ──┘   (no merge step needed)
```

* Falls back to a single stream automatically when the server lacks range support, the size is unknown, or the file is smaller than `2 × minSegmentSize`.
* Each segment retries and resumes **independently** — a dropped connection re-attaches at its own offset.
* Per-segment progress is persisted (≤ 1 s behind), so even a killed app resumes every segment where it stopped.
* Your code doesn't change: same `task.start()/pause()/resume()/cancel()`, same aggregated progress stream.

## Interceptors — hook into every step

Extend `DownloadInterceptor` and override only what you need. Interceptors run in registration order; `onCreate` can rewrite the request before the download is built:

```dart
class AuthInterceptor extends DownloadInterceptor {
  @override
  Future<DownloadRequest> onCreate(DownloadRequest request) async {
    return request.copyWith(
      headers: {...request.headers, 'Authorization': 'Bearer $token'},
    );
  }

  @override
  Future<void> onComplete(DownloadTask task) async {
    // e.g. verify checksum, fire a local notification, log analytics…
  }

  @override
  Future<void> onError(DownloadTask task, Object error, StackTrace st) async {
    // report to Sentry / Crashlytics
  }
}
```

A throwing interceptor never breaks a download — lifecycle notifications are isolated.

## Resuming after an app restart

```dart
// Rebuild your downloads screen from persisted state:
final records = await manager.persistedDownloads();
for (final record in records) {
  final task = await manager.createDownload(
    url: record.url,
    directory: File(record.filePath).parent.path,
  );
  await task.start(); // continues from the last written byte
}
```

## Architecture

```
DownloadManager (Facade)
 └─ DownloadTask (state machine: idle → connecting → downloading → completed/paused/failed/canceled)
     ├─ DownloadClient        (Strategy)  — transport, default: package:http
     ├─ DownloadRepository    (Repository) — persistence, default: Hive CE
     ├─ ConnectivityChecker   (Strategy)  — default: DNS lookup
     ├─ RetryPolicy           (Strategy)  — default: exponential backoff
     ├─ SegmentPlanner        (Strategy)  — default: ≤8 parts of ≥2 MB
     ├─ DownloadFileWriter    (Strategy)  — default: RandomAccessFile
     ├─ InterceptorChain      (Chain of Responsibility) — your hooks
     └─ SegmentDownloader × N — one per parallel connection
```

Every collaborator is an abstraction injected through `DownloadConfig`, so the package is extended by *adding* implementations — never by editing the engine.

## Statuses

| Status | Meaning |
|---|---|
| `idle` | Created, not started |
| `connecting` | Checking connectivity / opening the connection |
| `downloading` | Bytes are being written |
| `paused` | Stopped by the user; resumable |
| `completed` | All bytes written |
| `failed` | Unrecoverable error (`progress.error` holds it) |
| `canceled` | Canceled; partial file and state removed |
