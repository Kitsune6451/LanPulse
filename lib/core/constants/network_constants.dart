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

  /// Dimensione del singolo frammento di pacchetto file (64 KB)
  static const int fileChunkSizeBytes = 64 * 1024;

  /// Numero di frammenti dopo i quali il destinatario invia un ACK di flusso (32 * 64KB = 2 MB)
  static const int ackWindowChunks = 32;

  /// Codici di controllo socket per permessi e frammentazione
  static const int ctrlRejected = 0x00;
  static const int ctrlAccepted = 0x01;
  static const int ctrlChunkWindowAck = 0x02;
  static const int ctrlTransferCompleteAck = 0x03;

  /// Intervallo di invio del beacon di presenza UDP
  static const Duration heartbeatInterval = Duration(seconds: 3);

  /// Tempo massimo prima di considerare un nodo offline
  static const Duration peerStaleTimeout = Duration(seconds: 12);
}
