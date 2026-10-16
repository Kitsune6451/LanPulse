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

  /// Dimensione blocco ottimizzata per file da 100MB+ (2 MB per velocità massima)
  static const int fileChunkSizeBytes = 2 * 1024 * 1024;

  /// Flush del socket TCP ogni 4 blocchi (8 MB)
  static const int socketFlushEveryChunks = 4;

  /// Codici di controllo socket
  static const int ctrlRejected = 0x00;
  static const int ctrlAccepted = 0x01;
  static const int ctrlTransferCompleteAck = 0x03;

  /// Frame e segnali di controllo stato trasferimento (Pausa / Riprendi / Annulla)
  static const int frameDataChunk = 0x01;
  static const int frameEof = 0x02;
  static const int ctrlPause = 0x10;
  static const int ctrlResume = 0x11;
  static const int ctrlCancel = 0x12;

  /// Intervallo di invio del beacon di presenza UDP
  static const Duration heartbeatInterval = Duration(seconds: 3);

  /// Tempo massimo prima di considerare un nodo offline
  static const Duration peerStaleTimeout = Duration(seconds: 12);
}
