import '../core/exceptions.dart';

/// Strategy deciding whether (and when) a failed attempt should be retried.
abstract class RetryPolicy {
  const RetryPolicy();

  /// Called after attempt number [attempt] (1-based) failed with [error].
  ///
  /// Return the delay to wait before retrying, or `null` to give up and let
  /// the download fail.
  Duration? delayBeforeRetry(int attempt, Object error);
}

/// Never retries; the first error fails the download.
class NoRetryPolicy extends RetryPolicy {
  const NoRetryPolicy();

  @override
  Duration? delayBeforeRetry(int attempt, Object error) => null;
}

/// Retries up to [maxRetries] times with exponentially growing delays:
/// `baseDelay * multiplier^(attempt - 1)`.
///
/// When the server sent a `Retry-After` (429 "Too Many Requests" / 503), the
/// requested wait is honored whenever it is longer than the computed backoff.
class ExponentialBackoffRetryPolicy extends RetryPolicy {
  const ExponentialBackoffRetryPolicy({
    this.maxRetries = 3,
    this.baseDelay = const Duration(seconds: 1),
    this.multiplier = 2,
  });

  /// Maximum number of retries before giving up.
  final int maxRetries;

  /// Delay before the first retry.
  final Duration baseDelay;

  /// Factor the delay grows by on every subsequent retry.
  final double multiplier;

  @override
  Duration? delayBeforeRetry(int attempt, Object error) {
    if (attempt > maxRetries) return null;
    final factor = _pow(multiplier, attempt - 1);
    final backoff =
        Duration(microseconds: (baseDelay.inMicroseconds * factor).round());
    // A rate-limiting server tells us how long to back off — respect it.
    if (error is ServerException) {
      final retryAfter = error.retryAfter;
      if (retryAfter != null && retryAfter > backoff) return retryAfter;
    }
    return backoff;
  }

  double _pow(double base, int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= base;
    }
    return result;
  }
}
