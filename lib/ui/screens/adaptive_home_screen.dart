import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../models/p2p_packet.dart';
import '../../models/peer_node.dart';
import '../../providers/p2p_controller.dart';

enum AppSection { radar, chats, vault, style }

class AdaptiveHomeScreen extends StatefulWidget {
  const AdaptiveHomeScreen({super.key});

  @override
  State<AdaptiveHomeScreen> createState() => _AdaptiveHomeScreenState();
}

class _AdaptiveHomeScreenState extends State<AdaptiveHomeScreen> {
  AppSection _section = AppSection.radar;
  bool _onlyTrustedFilter = false;
  String _vaultFilter = 'all'; // 'all', 'sent', 'received'
  final TextEditingController _msgController = TextEditingController();

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }

  bool _isImageFile(String name) {
    final ext = name.toLowerCase();
    return ext.endsWith('.jpg') ||
        ext.endsWith('.jpeg') ||
        ext.endsWith('.png') ||
        ext.endsWith('.gif') ||
        ext.endsWith('.webp') ||
        ext.endsWith('.bmp');
  }

  bool _isAudioFile(String name) {
    final ext = name.toLowerCase();
    return ext.endsWith('.mp3') ||
        ext.endsWith('.wav') ||
        ext.endsWith('.ogg') ||
        ext.endsWith('.m4a') ||
        ext.endsWith('.aac') ||
        ext.endsWith('.flac');
  }

  bool _isVideoFile(String name) {
    final ext = name.toLowerCase();
    return ext.endsWith('.mp4') ||
        ext.endsWith('.mov') ||
        ext.endsWith('.mkv') ||
        ext.endsWith('.webm') ||
        ext.endsWith('.avi');
  }

  bool _isTextFile(String name) {
    final ext = name.toLowerCase();
    return ext.endsWith('.txt') ||
        ext.endsWith('.md') ||
        ext.endsWith('.json') ||
        ext.endsWith('.log') ||
        ext.endsWith('.csv') ||
        ext.endsWith('.xml') ||
        ext.endsWith('.yaml') ||
        ext.endsWith('.dart') ||
        ext.endsWith('.py');
  }

  void _openFilePreview(
    BuildContext context, {
    required String fileName,
    required String? filePath,
  }) {
    if (filePath == null || !File(filePath).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File non trovato sul disco locale.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => _FilePreviewDialog(
        fileName: fileName,
        filePath: filePath,
        isImage: _isImageFile(fileName),
        isAudio: _isAudioFile(fileName),
        isVideo: _isVideoFile(fileName),
        isText: _isTextFile(fileName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<P2PController>();
    final bool isDesktop = MediaQuery.of(context).size.width >= 860;

    // Su Mobile, se un peer è selezionato, apriamo la vista Chat pulita a tutto schermo
    if (!isDesktop && controller.selectedPeer != null) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildIncomingRequestOverlay(context, controller),
              if (controller.isTransferring)
                LinearProgressIndicator(
                  value: controller.activeTransferProgress > 0
                      ? controller.activeTransferProgress
                      : null,
                  minHeight: 3,
                ),
              Expanded(
                child: _buildChatStage(
                  context,
                  controller,
                  isMobileFullScreen: true,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: _buildMinimalHeader(context, controller),
      body: Column(
        children: [
          _buildStatusToast(context, controller),
          _buildIncomingRequestOverlay(context, controller),
          if (controller.isTransferring)
            LinearProgressIndicator(
              value: controller.activeTransferProgress > 0
                  ? controller.activeTransferProgress
                  : null,
              minHeight: 3,
            ),
          Expanded(
            child: isDesktop
                ? _buildDesktopWorkspace(context, controller)
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    child: _buildMobileSectionBody(context, controller),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: isDesktop
          ? null
          : NavigationBar(
              selectedIndex: _section.index,
              onDestinationSelected: (idx) {
                setState(() => _section = AppSection.values[idx]);
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.radar_rounded),
                  selectedIcon: const Icon(Icons.radar_rounded),
                  label: 'Radar (${controller.peers.length})',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: controller.totalUnreadCount > 0,
                    label: Text('${controller.totalUnreadCount}'),
                    child: const Icon(Icons.chat_bubble_outline_rounded),
                  ),
                  selectedIcon: const Icon(Icons.chat_bubble_rounded),
                  label: 'Chat',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.folder_copy_outlined),
                  selectedIcon: const Icon(Icons.folder_copy_rounded),
                  label: 'Archivio',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.tune_rounded),
                  selectedIcon: Icon(Icons.tune_rounded),
                  label: 'Stile',
                ),
              ],
            ),
    );
  }

  PreferredSizeWidget _buildMinimalHeader(
    BuildContext context,
    P2PController controller,
  ) {
    final Color accent = Theme.of(context).colorScheme.primary;
    return AppBar(
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.bolt_rounded, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.localAlias,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: controller.localIp != null
                            ? const Color(0xFF10B981)
                            : Colors.amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      controller.localIp ?? 'Rete offline',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Connessione diretta IP',
          icon: const Icon(Icons.add_link_rounded, size: 22),
          onPressed: () => _showConnectByIpModal(context, controller),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: IconButton(
            tooltip: 'Aggiorna radar Wi-Fi',
            icon: controller.isScanningWifi
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                : const Icon(Icons.sync_rounded, size: 22),
            onPressed:
                controller.isScanningWifi ? null : controller.refreshNetwork,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusToast(BuildContext context, P2PController controller) {
    if (controller.errorBanner == null) return const SizedBox.shrink();
    final Color color = controller.isBannerError
        ? const Color(0xFFEF4444)
        : Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            controller.isBannerError
                ? Icons.warning_amber_rounded
                : Icons.info_outline_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              controller.errorBanner!,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 16),
            onPressed: controller.clearError,
          ),
        ],
      ),
    );
  }

  /// Card Fintech per le richieste MANDATORIE di invio file da host non fidati
  Widget _buildIncomingRequestOverlay(
    BuildContext context,
    P2PController controller,
  ) {
    if (controller.pendingFileRequests.isEmpty) return const SizedBox.shrink();
    final item = controller.pendingFileRequests.first;
    final req = item.request;
    final Color accent = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius:
            BorderRadius.circular(controller.uiStyle.borderRadius),
        border: Border.all(color: accent, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.file_download_outlined,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Richiesta da ${req.senderAlias}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      '${req.fileName} • ${_formatBytes(req.fileSizeBytes)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: () =>
                    controller.respondToFileRequest(item, accept: false),
                child: const Text('Rifiuta'),
              ),
              OutlinedButton(
                onPressed: () => controller.respondToFileRequest(
                  item,
                  accept: true,
                  trustSender: false,
                ),
                child: const Text('Accetta'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.verified_outlined, size: 16),
                label: const Text('Accetta e Fidati'),
                onPressed: () => controller.respondToFileRequest(
                  item,
                  accept: true,
                  trustSender: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Layout Desktop a 3 colonne (NavigationRail + Lista Contestuale + Stage)
  Widget _buildDesktopWorkspace(
    BuildContext context,
    P2PController controller,
  ) {
    return Row(
      children: [
        NavigationRail(
          selectedIndex: _section.index,
          onDestinationSelected: (idx) {
            setState(() => _section = AppSection.values[idx]);
          },
          labelType: NavigationRailLabelType.all,
          destinations: [
            const NavigationRailDestination(
              icon: Icon(Icons.radar_rounded),
              label: Text('Radar'),
            ),
            NavigationRailDestination(
              icon: Badge(
                isLabelVisible: controller.totalUnreadCount > 0,
                label: Text('${controller.totalUnreadCount}'),
                child: const Icon(Icons.chat_bubble_outline_rounded),
              ),
              selectedIcon: const Icon(Icons.chat_bubble_rounded),
              label: const Text('Chat'),
            ),
            const NavigationRailDestination(
              icon: Icon(Icons.folder_copy_outlined),
              selectedIcon: Icon(Icons.folder_copy_rounded),
              label: Text('Archivio'),
            ),
            const NavigationRailDestination(
              icon: Icon(Icons.tune_rounded),
              label: Text('Stile'),
            ),
          ],
        ),
        const VerticalDivider(width: 1),
        if (_section == AppSection.radar || _section == AppSection.chats) ...[
          SizedBox(
            width: 330,
            child: _section == AppSection.radar
                ? _buildRadarList(context, controller)
                : _buildChatsList(context, controller),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _buildChatStage(context, controller)),
        ] else if (_section == AppSection.vault)
          Expanded(child: _buildVaultStage(context, controller))
        else
          Expanded(child: _buildStyleStage(context, controller)),
      ],
    );
  }

  Widget _buildMobileSectionBody(
    BuildContext context,
    P2PController controller,
  ) {
    return switch (_section) {
      AppSection.radar => _buildRadarList(context, controller),
      AppSection.chats => _buildChatsList(context, controller),
      AppSection.vault => _buildVaultStage(context, controller),
      AppSection.style => _buildStyleStage(context, controller),
    };
  }

  /// Sezione 1: Radar Nodi e Contatti Fidati
  Widget _buildRadarList(BuildContext context, P2PController controller) {
    final List<PeerNode> list = _onlyTrustedFilter
        ? controller.savedContactsList
        : controller.peers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text('Tutti (${controller.peers.length})'),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(
                        'Fidati (${controller.savedContactsList.length})',
                      ),
                    ),
                  ],
                  selected: {_onlyTrustedFilter},
                  onSelectionChanged: (s) =>
                      setState(() => _onlyTrustedFilter = s.first),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? _buildEmptyState(
                  icon: Icons.sensors_off_rounded,
                  title: _onlyTrustedFilter
                      ? 'Nessun contatto fidato'
                      : 'Ricerca nodi sulla LAN...',
                  subtitle: _onlyTrustedFilter
                      ? 'Tocca l\'icona segnalibro su qualsiasi host per salvarlo permanentemente.'
                      : 'Assicurati che i dispositivi siano sotto la stessa rete Wi-Fi o aggiungi un IP.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final peer = list[index];
                    return _buildPeerCard(context, controller, peer);
                  },
                ),
        ),
      ],
    );
  }

  /// Sezione 2: Lista Conversazioni Attive e Permanenti
  Widget _buildChatsList(BuildContext context, P2PController controller) {
    final chats = controller.activeChatPeers;
    if (chats.isEmpty) {
      return _buildEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Nessuna conversazione attiva',
        subtitle:
            'Seleziona un nodo dal Radar per inviare messaggi o file ad alta velocità.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: chats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final peer = chats[index];
        return _buildPeerCard(context, controller, peer, showLastMessage: true);
      },
    );
  }

  Widget _buildPeerCard(
    BuildContext context,
    P2PController controller,
    PeerNode peer, {
    bool showLastMessage = false,
  }) {
    final bool isSelected = controller.selectedPeer?.nodeId == peer.nodeId;
    final P2PChatMessage? lastMsg = controller.lastMessageForPeer(peer.nodeId);
    final int unread = controller.unreadCountForPeer(peer.nodeId);
    final Color accent = Theme.of(context).colorScheme.primary;

    return Card(
      color: isSelected ? accent.withValues(alpha: 0.10) : null,
      child: InkWell(
        borderRadius:
            BorderRadius.circular(controller.uiStyle.borderRadius),
        onTap: () => controller.selectPeer(peer),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      peer.platform == PeerPlatform.windows
                          ? Icons.laptop_mac_rounded
                          : Icons.phone_android_rounded,
                      color: accent,
                      size: 22,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: peer.isOnline
                            ? const Color(0xFF10B981)
                            : Colors.grey,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            peer.alias,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (peer.isTrusted) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.verified_rounded,
                            size: 15,
                            color: accent,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      showLastMessage && lastMsg != null
                          ? '${lastMsg.isOutgoing ? "Tu: " : ""}${lastMsg.content}'
                          : '${peer.ipAddress} • ${peer.isOnline ? "Online" : "Salvato"}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              if (unread > 0)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: peer.isTrusted
                    ? 'Rimuovi dai contatti fidati'
                    : 'Salva come contatto fidato',
                icon: Icon(
                  peer.isTrusted
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  size: 20,
                  color: peer.isTrusted ? accent : null,
                ),
                onPressed: () => controller.toggleSaveContact(peer),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Stage della Chat (con selettore rapido per scorrere le diverse chat senza ridondanza)
  Widget _buildChatStage(
    BuildContext context,
    P2PController controller, {
    bool isMobileFullScreen = false,
  }) {
    final PeerNode? peer = controller.selectedPeer;
    if (peer == null) {
      return _buildEmptyState(
        icon: Icons.bolt_rounded,
        title: 'Nessun nodo selezionato',
        subtitle:
            'Scegli un dispositivo dalla lista laterale per iniziare a condividere file o messaggi.',
      );
    }

    final messages = controller.messagesForSelectedPeer;
    final allChats = controller.activeChatPeers;
    final Color accent = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -450) {
          controller.cycleActiveChat(1);
        } else if (details.primaryVelocity! > 450) {
          controller.cycleActiveChat(-1);
        }
      },
      child: Column(
        children: [
          // Top Bar minimale della Chat
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerTheme.color ??
                      Colors.transparent,
                ),
              ),
            ),
            child: Row(
              children: [
                if (isMobileFullScreen)
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
                    onPressed: () => controller.selectPeer(null),
                  ),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: peer.isOnline
                        ? const Color(0xFF10B981)
                        : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              peer.alias,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (peer.isTrusted) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.verified_rounded,
                              size: 15,
                              color: accent,
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '${peer.ipAddress} • ${peer.isTrusted ? "Host Fidato" : "Richiesta attiva"}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color
                              ?.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),

                // Controlli compatti per scorrere tra le DIVERSE chat se ce n'è più di una
                if (allChats.length > 1) ...[
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Chat precedente',
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () => controller.cycleActiveChat(-1),
                  ),
                  Text(
                    '${allChats.indexWhere((c) => c.nodeId == peer.nodeId) + 1}/${allChats.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Chat successiva',
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: () => controller.cycleActiveChat(1),
                  ),
                ],
                IconButton(
                  tooltip: peer.isTrusted
                      ? 'Rimuovi dai contatti fidati'
                      : 'Salva come contatto fidato',
                  icon: Icon(
                    peer.isTrusted
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color: peer.isTrusted ? accent : null,
                  ),
                  onPressed: () => controller.toggleSaveContact(peer),
                ),
              ],
            ),
          ),

          // Corpo Messaggi
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState(
                    icon: Icons.swap_horiz_rounded,
                    title: 'Canale P2P pronto con ${peer.alias}',
                    subtitle:
                        'Tocca il pulsante + in basso per trasferire file di qualsiasi dimensione o scrivi un messaggio.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      return _buildModernMessageBubble(
                        context,
                        controller,
                        messages[index],
                      );
                    },
                  ),
          ),

          // Unica barra di composizione minimale (Niente pulsanti duplicati)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Invia file',
                  icon: const Icon(Icons.add_rounded),
                  onPressed: controller.isTransferring
                      ? null
                      : () => controller.pickAndSendFile(targetOverride: peer),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: const InputDecoration(
                      hintText: 'Messaggio...',
                    ),
                    onSubmitted: (_) => _sendText(controller),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  icon: const Icon(Icons.arrow_upward_rounded),
                  onPressed: () => _sendText(controller),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _sendText(P2PController controller) {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();
    controller.sendText(text);
  }

  Widget _buildModernMessageBubble(
    BuildContext context,
    P2PController controller,
    P2PChatMessage msg,
  ) {
    final bool isMe = msg.isOutgoing;
    final bool isFile = msg.type == TransferPayloadType.binaryFile;
    final bool hasLocalFile =
        msg.filePath != null && File(msg.filePath!).existsSync();
    final Color accent = Theme.of(context).colorScheme.primary;
    final double radius = controller.uiStyle.borderRadius;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: isMe
                ? accent.withValues(alpha: 0.16)
                : Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: isMe
                  ? accent.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: isFile
                ? () => _openFilePreview(
                      context,
                      fileName: msg.content,
                      filePath: msg.filePath,
                    )
                : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isFile) ...[
                    if (_isImageFile(msg.content) && hasLocalFile)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(radius - 4),
                          child: Image.file(
                            File(msg.filePath!),
                            height: 170,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _isImageFile(msg.content)
                                ? Icons.image_outlined
                                : _isVideoFile(msg.content)
                                    ? Icons.play_circle_outline_rounded
                                    : _isAudioFile(msg.content)
                                        ? Icons.graphic_eq_rounded
                                        : Icons.insert_drive_file_outlined,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg.content,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_formatBytes(msg.fileSize ?? 0)} • Tocca per aprire',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ] else
                    Text(
                      msg.content,
                      style: const TextStyle(fontSize: 14.5, height: 1.35),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('HH:mm').format(msg.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Sezione 3: Archivio (Cronologia File Inviati e Ricevuti)
  Widget _buildVaultStage(BuildContext context, P2PController controller) {
    final List<FileHistoryEntry> list = switch (_vaultFilter) {
      'sent' => controller.sentFileHistory,
      'received' => controller.receivedFileHistory,
      _ => controller.fileHistory,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: 'all',
                      label: Text('Tutti (${controller.fileHistory.length})'),
                    ),
                    ButtonSegment(
                      value: 'sent',
                      label: Text(
                        'Inviati (${controller.sentFileHistory.length})',
                      ),
                    ),
                    ButtonSegment(
                      value: 'received',
                      label: Text(
                        'Ricevuti (${controller.receivedFileHistory.length})',
                      ),
                    ),
                  ],
                  selected: {_vaultFilter},
                  onSelectionChanged: (s) =>
                      setState(() => _vaultFilter = s.first),
                ),
              ),
              if (controller.fileHistory.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Svuota archivio',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: controller.clearFileHistory,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? _buildEmptyState(
                  icon: Icons.folder_open_rounded,
                  title: 'Archivio trasferimenti vuoto',
                  subtitle:
                      'I file inviati e ricevuti compariranno qui con accesso rapido all\'anteprima.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final item = list[idx];
                    final Color accent = Theme.of(context).colorScheme.primary;

                    return Card(
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            item.isOutgoing
                                ? Icons.north_east_rounded
                                : Icons.south_west_rounded,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          item.fileName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${item.isOutgoing ? "A" : "Da"} ${item.peerAlias} • ${_formatBytes(item.fileSizeBytes)} • ${DateFormat("dd/MM HH:mm").format(item.timestamp)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(
                          Icons.open_in_new_rounded,
                          size: 18,
                        ),
                        onTap: () => _openFilePreview(
                          context,
                          fileName: item.fileName,
                          filePath: item.filePath,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Sezione 4: Stile, Temi, Audio SFX e Identità Locale (Senza Google Login)
  Widget _buildStyleStage(BuildContext context, P2PController controller) {
    final aliasCtrl = TextEditingController(text: controller.localAlias);

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'IDENTITÀ DISPOSITIVO',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: aliasCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nome visibile sulla rete LAN',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: () {
                        controller.updateLocalAlias(aliasCtrl.text);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Alias aggiornato.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: const Text('Salva'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PALETTE COLORI FINTECH',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AppThemePreset.values.map((preset) {
                    final selected = controller.themePreset == preset;
                    return ChoiceChip(
                      avatar: CircleAvatar(
                        backgroundColor: preset.darkSeed,
                        radius: 8,
                      ),
                      label: Text(preset.label),
                      selected: selected,
                      onSelected: (_) => controller.setThemePreset(preset),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                const Text(
                  'GEOMETRIA INTERFACCIA',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AppUiStyle.values.map((style) {
                    return ChoiceChip(
                      label: Text(style.label),
                      selected: controller.uiStyle == style,
                      onSelected: (_) => controller.setUiStyle(style),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Tema Scuro (Dark Mode)'),
                value: controller.isDarkMode,
                onChanged: controller.toggleDarkMode,
              ),
              if (controller.isDarkMode)
                SwitchListTile(
                  title: const Text('Contrasto Puro AMOLED (#000000)'),
                  value: controller.useAmoledBlack,
                  onChanged: controller.toggleAmoledBlack,
                ),
              SwitchListTile(
                title: const Text('Suono Notifica Richieste (SFX)'),
                subtitle: const Text(
                  'Avviso acustico quando un host non salvato invia un file',
                ),
                value: controller.sfxEnabled,
                onChanged: controller.toggleSfx,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final Color accent = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: accent, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showConnectByIpModal(
    BuildContext context,
    P2PController controller,
  ) {
    final ipCtrl = TextEditingController();
    final aliasCtrl = TextEditingController();
    bool trustHost = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('Collega Host via IP'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ipCtrl,
                decoration: const InputDecoration(
                  labelText: 'Indirizzo IP (es. 192.168.1.45)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: aliasCtrl,
                decoration: const InputDecoration(
                  labelText: 'Alias (opzionale)',
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Salva nei Contatti Fidati'),
                value: trustHost,
                onChanged: (v) => setModalState(() => trustHost = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                controller.connectByIp(
                  ipAddress: ipCtrl.text,
                  customAlias: aliasCtrl.text,
                  saveAsTrusted: trustHost,
                );
              },
              child: const Text('Connetti'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog Multimediale per Foto, Video (con supporto Windows nativo), Audio e Testo
class _FilePreviewDialog extends StatefulWidget {
  final String fileName;
  final String filePath;
  final bool isImage;
  final bool isAudio;
  final bool isVideo;
  final bool isText;

  const _FilePreviewDialog({
    required this.fileName,
    required this.filePath,
    required this.isImage,
    required this.isAudio,
    required this.isVideo,
    required this.isText,
  });

  @override
  State<_FilePreviewDialog> createState() => _FilePreviewDialogState();
}

class _FilePreviewDialogState extends State<_FilePreviewDialog> {
  AudioPlayer? _audioPlayer;
  bool _isPlayingAudio = false;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;

  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  String? _videoError;

  String? _textContent;

  @override
  void initState() {
    super.initState();
    if (widget.isAudio) {
      _initAudio();
    } else if (widget.isVideo) {
      _initVideo();
    } else if (widget.isText) {
      _initText();
    }
  }

  Future<void> _initAudio() async {
    _audioPlayer = AudioPlayer();
    _audioPlayer!.onDurationChanged.listen((d) {
      if (mounted) setState(() => _audioDuration = d);
    });
    _audioPlayer!.onPositionChanged.listen((p) {
      if (mounted) setState(() => _audioPosition = p);
    });
    _audioPlayer!.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlayingAudio = false;
          _audioPosition = Duration.zero;
        });
      }
    });
    await _audioPlayer!.play(DeviceFileSource(widget.filePath));
    if (mounted) setState(() => _isPlayingAudio = true);
  }

  Future<void> _initVideo() async {
    try {
      final controller = VideoPlayerController.file(File(widget.filePath));
      _videoController = controller;
      await controller.initialize();
      await controller.play();
      if (mounted) setState(() => _videoInitialized = true);
    } catch (e) {
      if (mounted) setState(() => _videoError = '$e');
    }
  }

  Future<void> _initText() async {
    try {
      final content = await File(widget.filePath).readAsString();
      if (mounted) {
        setState(() {
          _textContent = content.length > 20000
              ? '${content.substring(0, 20000)}\n\n... [Troncato]'
              : content;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _textContent = 'Errore lettura: $e');
    }
  }

  Future<void> _launchNativePlayer() async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', widget.filePath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [widget.filePath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [widget.filePath]);
      }
    } catch (_) {}
  }

  Future<void> _revealInFolder() async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', widget.filePath]);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _audioPlayer?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.fileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (Platform.isWindows) ...[
                    TextButton.icon(
                      icon: const Icon(Icons.play_lesson_outlined, size: 18),
                      label: const Text('Apri con App PC'),
                      onPressed: _launchNativePlayer,
                    ),
                    IconButton(
                      tooltip: 'Mostra in Esplora File',
                      icon: const Icon(Icons.folder_open_rounded, size: 20),
                      onPressed: _revealInFolder,
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Flexible(child: _buildPreviewContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewContent() {
    if (widget.isImage) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 5.0,
        child: Image.file(File(widget.filePath), fit: BoxFit.contain),
      );
    }

    if (widget.isAudio) {
      final double maxMs =
          _audioDuration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
      final double curMs =
          _audioPosition.inMilliseconds.toDouble().clamp(0.0, maxMs);

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.graphic_eq_rounded, size: 56),
            const SizedBox(height: 16),
            Slider(
              value: curMs,
              max: maxMs,
              onChanged: (val) {
                _audioPlayer?.seek(Duration(milliseconds: val.toInt()));
              },
            ),
            Text(
              '${_audioPosition.inMinutes}:${(_audioPosition.inSeconds % 60).toString().padLeft(2, "0")} / '
              '${_audioDuration.inMinutes}:${(_audioDuration.inSeconds % 60).toString().padLeft(2, "0")}',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            IconButton.filled(
              iconSize: 34,
              icon: Icon(
                _isPlayingAudio
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
              onPressed: () async {
                if (_isPlayingAudio) {
                  await _audioPlayer?.pause();
                  setState(() => _isPlayingAudio = false);
                } else {
                  await _audioPlayer?.resume();
                  setState(() => _isPlayingAudio = true);
                }
              },
            ),
          ],
        ),
      );
    }

    if (widget.isVideo) {
      if (_videoError != null) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.movie_outlined, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Formato video pronto per il lettore di sistema.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Riproduci nel Player Nativo'),
                onPressed: _launchNativePlayer,
              ),
            ],
          ),
        );
      }
      if (!_videoInitialized || _videoController == null) {
        return const Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio > 0
                  ? _videoController!.value.aspectRatio
                  : 16 / 9,
              child: VideoPlayer(_videoController!),
            ),
          ),
          const SizedBox(height: 8),
          VideoProgressIndicator(_videoController!, allowScrubbing: true),
          const SizedBox(height: 10),
          IconButton.filled(
            icon: Icon(
              _videoController!.value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
            onPressed: () {
              setState(() {
                _videoController!.value.isPlaying
                    ? _videoController!.pause()
                    : _videoController!.play();
              });
            },
          ),
        ],
      );
    }

    if (widget.isText) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          _textContent ?? 'Caricamento...',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            widget.filePath,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }
}
