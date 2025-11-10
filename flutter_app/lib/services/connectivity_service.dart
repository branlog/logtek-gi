import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool get isOnline => _isOnline;

  Stream<bool> get onStatusChange => _controller.stream;

  Future<void> init() async {
    final initial = await _connectivity.checkConnectivity();
    _updateStatus(_hasNetwork(initial));

    await _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _updateStatus(_hasNetwork(results));
    });
  }

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }

  void _updateStatus(bool online) {
    if (_isOnline == online) return;
    _isOnline = online;
    _controller.add(_isOnline);
  }

  bool _hasNetwork(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((result) =>
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.ethernet ||
        result == ConnectivityResult.vpn);
  }
}
