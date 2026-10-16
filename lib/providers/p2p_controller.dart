Future<void> _initializeApp() async {
    await _loadSavedSettingsAndData();

    _discoveryService.updateIdentity(
      newNodeId: localNodeId,
      newAlias: _localAlias,
    );
    _transferService.localNodeId = localNodeId;
    _transferService.localAlias = _localAlias;

    if (Platform.isAndroid) {
      try {
        await [
          Permission.nearbyWifiDevices,
          Permission.locationWhenInUse,
          Permission.notification,
          Permission.ignoreBatteryOptimizations,
        ].request();
      } catch (_) {}
    }

    await _notifService.initialize(
      onDecision: (transferId, accepted) {
        PendingRequestItem? match;
        for (final item in _pendingFileRequests) {
          if (item.request.transferId == transferId) {
            match = item;
            break;
          }
        }
        if (match != null) {
          respondToFileRequest(match, accept: accepted);
        }
      },
      onStopApp: () {
        // Ferma il server e chiude l'app quando tocchi "Chiudi App" dalla notifica
        _transferService.stopServer();
        _discoveryService.stopDiscovery();
        exit(0);
      },
    );

    await _initializeNetworking();
  }
