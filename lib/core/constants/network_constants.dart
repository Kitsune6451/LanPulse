class NetworkConstants {
  NetworkConstants._();

  static const String protocolMagic = 'LANPULSE_V1';
  static const String mdnsServiceType = '_lanpulse._tcp';
  static const int udpDiscoveryPort = 45454;
  static const int tcpTransferPort = 45455;
  static const String multicastGroupIp = '239.255.45.45';

  static const int fileChunkSizeBytes = 512 * 1024;
  static const int socketFlushEveryChunks = 16;

  static const int ctrlRejected = 0x00;
  static const int ctrlAccepted = 0x01;
  static const int ctrlTransferCompleteAck = 0x03;

  static const int frameDataChunk = 0x01;
  static const int frameEof = 0x02;
  static const int ctrlPause = 0x10;
  static const int ctrlResume = 0x11;
  static const int ctrlCancel = 0x12;

  static const Duration heartbeatInterval = Duration(seconds: 3);
  static const Duration peerStaleTimeout = Duration(seconds: 12);
}
