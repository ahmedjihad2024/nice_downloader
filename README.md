# Nice Downloader

[![pub package](https://img.shields.io/pub/v/nice_downloader.svg)](https://pub.dev/packages/nice_downloader)

A powerful, easy-to-use file downloader for Flutter — downloads files **fast** using multiple parallel connections (like IDM), with pause/resume, speed limiting, and automatic recovery from network drops.

## ✨ What it can do

| | |
|---|---|
| ⚡ **Fast downloads** | Big files are split into up to 8 parallel connections automatically |
| ⏸️ **Pause & Resume** | Continue from the exact byte — even after closing the app |
| 🚦 **Speed limit** | Cap the download speed, change it live, or leave it at max |
| 🔁 **Auto retry** | Network dropped? It reconnects and continues by itself |
| 🛡️ **Data safety** | If the partial file gets damaged, it detects and re-downloads only the broken part |
| 🔌 **Interceptors** | Hook into every step (start, progress, complete, error…) for logging, analytics, etc. |

---

## 📦 Install

```yaml
dependencies:
  nice_downloader: ^1.3.0
```

---

## 🚀 Quick start (3 steps)

```dart
import 'package:nice_downloader/nice_downloader.dart';

// 1. Create ONE manager for your whole app
final manager = DownloadManager();

// 2. Create a download task
final task = await manager.createDownload(
  url: 'https://example.com/video.mp4',
  directory: '/storage/emulated/0/Download', // where to save
);

// 3. Listen to progress and start
task.progressStream.listen((progress) {
  print('${progress.percent}%  •  ${progress.readableSpeed ?? ''}');
});
await task.start();
```

That's it! The file name is taken from the server or the URL automatically (you can also pass `fileName:` yourself).

---

## 📊 Showing progress

Every event on `progressStream` is a `DownloadProgress` with everything your UI needs:

```dart
task.progressStream.listen((progress) {
  progress.status;              // downloading, paused, completed...
  progress.percent;             // 0.0 .. 100.0
  progress.downloadedBytes;     // 5242880
  progress.totalBytes;          // 104857600
  progress.readableDownloaded;  // "5.0 MB"   (nice for UI)
  progress.readableTotal;       // "100.0 MB"
  progress.readableSpeed;       // "2.3 MB/s" (null when not downloading)
  progress.error;               // the exception, when status == failed
});
```

You can also read the latest snapshot any time with `task.progress` (no stream needed).

### Statuses

| Status | Meaning |
|---|---|
| `idle` | Created, not started yet |
| `connecting` | Opening the connection |
| `downloading` | Receiving bytes |
| `paused` | Stopped by you — resumable |
| `completed` | Finished successfully ✅ |
| `failed` | Error after all retries (see `progress.error`) |
| `canceled` | Canceled — file and saved state removed |

Handy helpers: `status.isActive`, `status.isFinished`, `status.canStart`.

---

## ⏯️ Pause, Resume, Cancel

```dart
await task.pause();    // stop, keep the partial file
await task.resume();   // continue from the same byte
await task.start();    // same as resume (also retries a failed download)
await task.cancel();   // stop + delete the partial file
```

Invalid calls are safe — pausing an idle task or starting a running one simply does nothing.

---

## 🚦 Speed limit

**If you don't set anything, downloads run at max speed.** Three ways to limit:

```dart
// 1. For all downloads:
DownloadManager(config: DownloadConfig(speedLimit: 2 * 1024 * 1024)); // 2 MB/s

// 2. For one download:
manager.createDownload(url: ..., directory: ..., speedLimit: 512 * 1024);

// 3. Change it WHILE downloading:
task.speedLimit = 1024 * 1024;  // 1 MB/s
task.speedLimit = null;         // back to max speed
```

The limit is the **total** speed — all parallel connections share it.

---

## 🔄 Restore downloads after app restart

Progress is saved automatically (using Hive). When your app starts:

```dart
final tasks = await manager.restorePersistedDownloads();
// completed ones show as completed, partial ones as paused
for (final task in tasks) {
  // show in your UI; call task.start() to continue a paused one
}
```

A resumed download continues from where it stopped — even segmented ones continue every connection from its own offset.

---

## 🔐 Downloads that need login (headers)

```dart
manager.createDownload(
  url: 'https://api.example.com/files/report.pdf',
  directory: dir,
  headers: {'Authorization': 'Bearer $token'},
);
```

---

## ⚙️ Configuration (all optional!)

Everything has a sensible default — only set what you want to change:

```dart
final manager = DownloadManager(
  config: DownloadConfig(
    // hook into download lifecycle (logging, analytics...)
    interceptors: [LoggingInterceptor()],

    // wait for internet instead of failing when offline
    waitForConnection: true,

    // how failed attempts retry (default: 3 retries, exponential backoff)
    retryPolicy: ExponentialBackoffRetryPolicy(maxRetries: 5),

    // parallel connections (default: up to 8, only for files >= 4 MB)
    segmentPlanner: DefaultSegmentPlanner(maxSegments: 4),
    // segmentPlanner: NoSegmentationPlanner(),  // always 1 connection

    // default speed cap in bytes/sec (default: null = max speed)
    speedLimit: null,

    // verify saved data before resuming (default: true)
    verifyOnResume: true,

    // how often progress events are emitted (default: 100 ms)
    progressInterval: Duration(milliseconds: 250),

    // don't save progress to disk (e.g. for tests)
    // repository: InMemoryDownloadRepository(),
  ),
);
```

---

## ⚡ How the speed comes from (segmented downloads)

When the server supports it, big files are downloaded like IDM does:

```
File: 100 MB → 4 parallel connections

Connection 1 ──▶ bytes 0–25 MB    ──┐
Connection 2 ──▶ bytes 25–50 MB   ──┤── all write into ONE file,
Connection 3 ──▶ bytes 50–75 MB   ──┤   each at its own position
Connection 4 ──▶ bytes 75–100 MB  ──┘   (no merging needed)
```

You don't have to do anything — it's automatic, and it silently falls back to a normal single connection when:
- the server doesn't support range requests, or
- the file is small (< 4 MB by default)

If a server complains about too many connections (HTTP 429), the downloader automatically reduces them (8 → 4 → 2 → 1) and keeps going.

---

## 🔌 Interceptors — hook into every step

Want logging, notifications, analytics, or to modify requests? Extend `DownloadInterceptor` and override only what you need:

```dart
class MyInterceptor extends DownloadInterceptor {
  @override
  Future<DownloadRequest> onCreate(DownloadRequest request) async {
    // runs BEFORE the download is built — you can modify the request!
    return request.copyWith(
      headers: {...request.headers, 'Authorization': 'Bearer ...'},
    );
  }

  @override
  Future<void> onComplete(DownloadTask task) async {
    print('Saved to ${task.filePath}');  // show a notification, etc.
  }

  @override
  Future<void> onError(DownloadTask task, Object error, StackTrace st) async {
    // report to Crashlytics / Sentry
  }

  // also available: onStart, onResume, onPause, onCancel, onChunk
}
```

Register it once: `DownloadConfig(interceptors: [MyInterceptor()])`. A throwing interceptor never breaks a download.

---

## ❗ Error handling

All errors are typed and arrive in `progress.error` when `status == failed`:

```dart
if (progress.status == DownloadStatus.failed) {
  final message = switch (progress.error) {
    NoConnectionException() => 'No internet connection',
    ServerException(statusCode: 403) => 'Access denied by the server',
    ServerException(statusCode: 429) => 'Too many requests — try later',
    ServerException(statusCode: final code) => 'Server error ($code)',
    _ => 'Download failed',
  };
}
```

Call `task.start()` to retry a failed download — it continues from the saved bytes.

---

## 🧰 Advanced: swap any part

Every piece is an interface you can replace via `DownloadConfig` — no core code changes needed:

| Interface | Default | Replace it to… |
|---|---|---|
| `DownloadClient` | `package:http` | use Dio, a proxy, mock in tests |
| `DownloadRepository` | Hive CE | store state in SQLite, memory, … |
| `ConnectivityChecker` | DNS lookup | use `connectivity_plus` |
| `RetryPolicy` | exponential backoff | custom retry rules |
| `SegmentPlanner` | ≤ 8 parts of ≥ 2 MB | custom splitting logic |
| `DownloadFileWriter` | `RandomAccessFile` | encrypted storage, … |

---

## 🛟 Troubleshooting

**The download fails with 403** — some sites (e.g. behind Cloudflare's "Just a moment…" page) block all download managers and require a real browser. Not fixable from any downloader. For sites you're logged into, pass your browser's cookies via `headers: {'Cookie': '...'}`.

**The download fails with 429** — the server limits connections/requests per IP. The downloader adapts automatically; if it still fails, lower `maxSegments` or wait a bit.

**Good links for testing:**
```
https://proof.ovh.net/files/100Mb.dat
https://ash-speed.hetzner.com/100MB.bin
http://ipv4.download.thinkbroadband.com/50MB.zip
```

---

## 📱 Full example

The [example app](example/) is a complete mini download manager (URL input, progress cards, pause/continue, speed controls, restore on startup) — a great starting point for your own UI.

## 📄 License

[MIT](LICENSE)
