## 1.3.1

* Rewrote the README as a friendly step-by-step usage guide.

## 1.3.0

### Added
* **Rate-limit friendliness (HTTP 429)** — the `Retry-After` header is parsed into `ServerException.retryAfter` and honored by `ExponentialBackoffRetryPolicy`; segment connections now open staggered (`DownloadConfig.connectionStagger`, 200 ms default) instead of all at once.
* **Adaptive concurrency (IDM-style)** — when a segmented download keeps hitting 429, the number of parallel connections is automatically halved (8 → 4 → 2 → 1) with a cooldown between rounds, instead of failing. The learned limit sticks for the task's lifetime.
* **Better file names** — when the server sends no `Content-Disposition`, the URL's last path segment is used (e.g. `100MB.bin`) before falling back to a timestamp; generic MIME types (`application/octet-stream` etc.) are no longer mistaken for file extensions.
* **Integrity verification on resume** (`DownloadConfig.verifyOnResume`, default on) — every written byte is checksummed (CRC-32) and persisted with the progress. On resume, the on-disk data is re-verified: bytes that were modified, truncated or deleted while paused are detected, and only the damaged range is downloaded again (per segment for segmented downloads; single-stream restarts from zero). Fully client-side — works with any server; partial re-fetching needs only the same range support resume already uses.

### Changed
* `DownloadRecord` format v3 (adds verified byte count + checksums); v1/v2 records remain readable — their data is adopted on first resume and verified from then on.
* `DownloadFileWriter` gained a `read()` method (used for verification).

## 1.2.0

### Added
* **Speed limiting** — `DownloadConfig.speedLimit`, a per-download override in `createDownload(speedLimit: …)`, and a live-mutable `DownloadTask.speedLimit`. The limit caps the *total* speed across all segments (token-bucket `BandwidthThrottle`); `null` (default) means unlimited/max speed.
* Example app rebuilt as a full download-manager UI: URL field, download list with progress/speed/status, pause/continue/retry, global + per-download speed limit controls.
* **Restore after restart** — `DownloadTask.restoreState()` hydrates progress from storage without touching the network, and `DownloadManager.restorePersistedDownloads()` rebuilds the whole task list in one call; the example app now shows previous downloads on startup.

## 1.1.0

### Added
* **IDM-style segmented downloads** — large files are automatically split into up to 8 parallel range connections, each writing at its own offset in a pre-allocated file. No merge step, no API change.
* `SegmentPlanner` strategy (`DefaultSegmentPlanner`, `NoSegmentationPlanner`) configurable via `DownloadConfig.segmentPlanner`.
* Per-segment resume: pause/cancel/crash recovery continues each segment from its own byte offset, persisted at most 1 s behind the transfer.
* Per-segment retries — a dropped connection resumes that segment alone without disturbing the others.
* Automatic fallback to single-stream when the server lacks range support, the size is unknown, or the file is too small to be worth splitting.
* `DownloadFileWriter.openAt` / `allocate` for positional writes.

### Changed
* `DownloadRecord` persistence format v2 (adds segment state); v1 records remain readable.

## 1.0.0

Complete architectural rewrite. **Breaking release.**

### Added
* Interceptor pipeline (`DownloadInterceptor`) — hook into create / start / chunk / pause / resume / complete / cancel / error; `LoggingInterceptor` included.
* Retry policies (`RetryPolicy`) with `ExponentialBackoffRetryPolicy` default; mid-stream drops automatically resume from the bytes already on disk.
* Repository abstraction (`DownloadRepository`) with Hive CE (`HiveDownloadRepository`) and `InMemoryDownloadRepository` implementations.
* Pluggable transport (`DownloadClient`), connectivity checking (`ConnectivityChecker`) and file writing (`DownloadFileWriter`).
* Typed exceptions (`NiceDownloaderException` hierarchy) surfaced on `DownloadProgress.error`.
* `DownloadManager.persistedDownloads()` to rebuild download lists after an app restart.
* Full unit test suite.

### Changed
* `Downloader` → `DownloadTask` with a proper state machine; invalid calls are safe no-ops.
* `DownloaderData` → immutable `DownloadProgress` (real `copyWith`, readable size/speed helpers).
* `DOWNLOAD_STATUS` → `DownloadStatus` (lowerCamelCase, with `isActive` / `isFinished` helpers).
* Migrated from discontinued `hive` to `hive_ce`.
* Cross-platform paths via `package:path` (previously Windows-only separators).

### Fixed
* Speed calculation used milliseconds where microseconds were intended.
* Hive adapter was re-registered on every box access.
* Hive box was misnamed `authentication-box`.
* Connectivity check no longer hammers a hard-coded web page in an infinite loop.

## 0.0.1

* Initial release: pause, cancel and resume downloads.
