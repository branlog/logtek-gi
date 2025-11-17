import 'dart:async';

/// Runs a [future] without awaiting it while still surfacing uncaught errors.
void runDetached(Future<void>? future) {
  future?.catchError((error, stackTrace) {
    Zone.current.handleUncaughtError(error, stackTrace);
  });
}
