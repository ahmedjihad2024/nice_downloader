import 'dart:io';

/// Strategy for answering "is the device online?".
///
/// Replace the default with your own implementation (e.g. one backed by
/// `connectivity_plus`) via [DownloadConfig.connectivityChecker].
abstract class ConnectivityChecker {
  const ConnectivityChecker();

  /// Whether the device currently has internet access.
  Future<bool> hasConnection();

  /// Completes once [hasConnection] returns `true`, polling every
  /// [pollInterval].
  Future<void> waitForConnection(
      {Duration pollInterval = const Duration(seconds: 2)}) async {
    while (!await hasConnection()) {
      await Future<void>.delayed(pollInterval);
    }
  }
}

/// Default checker: a cheap DNS lookup with a timeout — no HTTP request, no
/// hard-coded web page.
class DnsConnectivityChecker extends ConnectivityChecker {
  const DnsConnectivityChecker({
    this.host = 'one.one.one.one',
    this.timeout = const Duration(seconds: 5),
  });

  /// Host name resolved to probe connectivity.
  final String host;

  /// How long a single probe may take before being treated as offline.
  final Duration timeout;

  @override
  Future<bool> hasConnection() async {
    try {
      final result = await InternetAddress.lookup(host).timeout(timeout);
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

/// A checker that always reports "online" — useful for tests or when
/// connectivity is handled elsewhere.
class AlwaysOnlineConnectivityChecker extends ConnectivityChecker {
  const AlwaysOnlineConnectivityChecker();

  @override
  Future<bool> hasConnection() async => true;
}
