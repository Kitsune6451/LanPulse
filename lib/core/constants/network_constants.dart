class NetworkConstants {
  NetworkConstants._();

  /// Identificativo del protocollo per scartare pacchetti estranei sulla LAN
  static const String protocolMagic = 'LANPULSE_V1';

  /// Servizio mDNS standard (RFC 6762 / RFC 6763)
  static const String mdnsServiceType = '_lanpulse._tcp';

  /// Porta UDP per il Discovery Broadcast e Multicast fallback
  static const int udpDiscoveryPort = 45454;

  /// Porta TCP di default per il ServerSocket di scambio messaggi e file
  static const int tcpTransferPort = 45455;

  /// Indirizzo Multicast IPv4 locale per reti in cui 255.255.255.255 è filtrato
  static const String multicastGroupIp = '239.255.45.45';

  /// Dimensione chunk di lettura/scrittura file (64 KB ottimizza il throughput TCP)
  static const int fileChunkSizeBytes = 64 * 1024;

  /// Intervallo di invio del beacon di presenza UDP
  static const Duration heartbeatInterval = Duration(seconds: 3);

  /// Tempo massimo prima di considerare un nodo offline
  static const Duration peerStaleTimeout = Duration(seconds: 12);
}
