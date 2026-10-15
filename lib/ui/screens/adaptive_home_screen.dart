import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../models/p2p_packet.dart';
import '../../models/peer_node.dart';
import '../../providers/p2p_controller.dart';

enum LeftSidebarTab { allPeers, savedContacts, chats, fileHistory }

class AdaptiveHomeScreen extends StatefulWidget {
  const AdaptiveHomeScreen({super.key});

  @override
  State<AdaptiveHomeScreen> createState() => _AdaptiveHomeScreenState();
}

class _AdaptiveHomeScreenState extends State<AdaptiveHomeScreen> {
  LeftSidebarTab _activeTab = LeftSidebarTab.allPeers;
  String _historyFilter = 'sent'; // 'sent', 'received', 'all'
  final TextEditingController _msgController = TextEditingController();
  final Map<String, ScrollController> _chatScrollControllers = {};

  ScrollController _scrollControllerForPeer(String peerId) {
    return _chatScrollControllers.putIfAbsent(
      peerId,
      () => ScrollController(),
    );
  }

  @override
  void dispose() {
    _msgController.dispose();
    for (final c in _chatScrollControllers.values) {
      c.dispose();
    }
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
    return '${size.toStringAsFixed(i == 0 ? 0 : 2)} ${suffixes[i]}';
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
          content: Text('Il file locale non è più presente sul disco.'),
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
    final bool isWide = MediaQuery.of(context).size.width >= 820;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.radar_rounded),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LanPulse P2P • ${controller.localAlias}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'IP Wi-Fi: ${controller.localIp ?? "Ricerca rete..."} : ${controller.tcpPort}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Aggiungi Host via IP',
            icon: const Icon(Icons.add_link_rounded),
            onPressed: () => _showConnectByIpDialog(context, controller),
          ),
          IconButton(
            tooltip: 'Scansiona Rete Wi-Fi',
            icon: controller.isScanningWifi
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed:
                controller.isScanningWifi ? null : controller.refreshNetwork,
          ),
          IconButton(
            tooltip: 'Temi, Stili e Login Google',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => _showSettingsAndThemesSheet(context, controller),
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner notifiche di stato o errori
          if (controller.errorBanner != null)
            MaterialBanner(
              backgroundColor: controller.isBannerError
                  ? Colors.red.withValues(alpha: 0.15)
                  : Theme.of(context).colorScheme.primaryContainer,
              content: Text(controller.errorBanner!),
              leading: Icon(
                controller.isBannerError
                    ? Icons.error_outline
                    : Icons.info_outline,
              ),
              actions: [
                TextButton(
                  onPressed: controller.clearError,
                  child: const Text('CHIUDI'),
                ),
              ],
            ),

          // Richieste MANDATORIE di ricezione file in entrata (per gli host non fidati)
          for (final reqItem in controller.pendingFileRequests)
            _buildMandatoryFileRequestBanner(context, controller, reqItem),

          // Barra progresso trasferimento attivo
          if (controller.isTransferring)
            LinearProgressIndicator(
              value: controller.activeTransferProgress > 0
                  ? controller.activeTransferProgress
                  : null,
              minHeight: 5,
            ),

          // Barra rapida per scorrere le DIVERSE chat aperte/salvate
          if (controller.activeChatPeers.isNotEmpty)
            _buildChatSwitcherBar(context, controller),

          // Contenuto principale
          Expanded(
            child: isWide
                ? Row(
                    children: [
                      SizedBox(
                        width: 340,
                        child: _buildSidebar(context, controller),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _activeTab == LeftSidebarTab.fileHistory
                            ? _buildFileHistoryView(context, controller)
                            : _buildChatArea(context, controller),
                      ),
                    ],
                  )
                : (_activeTab == LeftSidebarTab.fileHistory
                    ? Column(
                        children: [
                          _buildMobileTopTabs(controller),
                          Expanded(
                            child: _buildFileHistoryView(context, controller),
                          ),
                        ],
                      )
                    : (controller.selectedPeer == null
                        ? Column(
                            children: [
                              _buildMobileTopTabs(controller),
                              Expanded(
                                child: _buildSidebar(context, controller),
                              ),
                            ],
                          )
                        : _buildChatArea(context, controller, isMobile: true))),
          ),
        ],
      ),
    );
  }

  /// Banner interattivo obbligatorio quando un host NON fidato chiede di inviare un file
  Widget _buildMandatoryFileRequestBanner(
    BuildContext context,
    P2PController controller,
    PendingRequestItem item,
  ) {
    final req = item.request;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius:
            BorderRadius.circular(controller.uiStyle.borderRadius),
        border: Border.all(
          color: Theme.of(context).colorScheme.tertiary,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_rounded, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Richiesta di invio file da ${req.senderAlias} (${req.senderIp})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'File: "${req.fileName}" • Dimensione: ${_formatBytes(req.fileSizeBytes)}',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Rifiuta'),
                onPressed: () => controller.respondToFileRequest(
                  item,
                  accept: false,
                ),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Accetta questa volta'),
                onPressed: () => controller.respondToFileRequest(
                  item,
                  accept: true,
                  trustSender: false,
                ),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.verified_user_rounded, size: 18),
                label: const Text('Accetta e Salva come Fidato'),
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

  /// Barra orizzontale per scorrere rapidamente le diverse chat attive e salvate
  Widget _buildChatSwitcherBar(
    BuildContext context,
    P2PController controller,
  ) {
    final chats = controller.activeChatPeers;
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Chat precedente',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => controller.cycleActiveChat(-1),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: chats.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final peer = chats[index];
                final bool isSelected =
                    controller.selectedPeer?.nodeId == peer.nodeId;
                final int unread = controller.unreadCountForPeer(peer.nodeId);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: ChoiceChip(
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() {
                        if (_activeTab == LeftSidebarTab.fileHistory) {
                          _activeTab = LeftSidebarTab.chats;
                        }
                      });
                      controller.selectPeer(peer);
                    },
                    avatar: Icon(
                      peer.isTrusted ? Icons.star_rounded : Icons.chat_bubble,
                      size: 16,
                      color: peer.isOnline ? Colors.greenAccent : Colors.grey,
                    ),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(peer.alias),
                        if (unread > 0) ...[
                          const SizedBox(width: 6),
                          CircleAvatar(
                            radius: 9,
                            backgroundColor:
                                Theme.of(context).colorScheme.error,
                            child: Text(
                              '$unread',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'Chat successiva',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => controller.cycleActiveChat(1),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTopTabs(P2PController controller) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SegmentedButton<LeftSidebarTab>(
        segments: [
          const ButtonSegment(
            value: LeftSidebarTab.allPeers,
            icon: Icon(Icons.wifi_tethering, size: 18),
            label: Text('Nodi'),
          ),
          const ButtonSegment(
            value: LeftSidebarTab.savedContacts,
            icon: Icon(Icons.star_rounded, size: 18),
            label: Text('Contatti'),
          ),
          const ButtonSegment(
            value: LeftSidebarTab.chats,
            icon: Icon(Icons.forum_outlined, size: 18),
            label: Text('Chat'),
          ),
          ButtonSegment(
            value: LeftSidebarTab.fileHistory,
            icon: const Icon(Icons.history_rounded, size: 18),
            label: Text('File (${controller.fileHistory.length})'),
          ),
        ],
        selected: {_activeTab},
        onSelectionChanged: (s) => setState(() => _activeTab = s.first),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, P2PController controller) {
    final List<PeerNode> displayedPeers = switch (_activeTab) {
      LeftSidebarTab.savedContacts => controller.savedContactsList,
      LeftSidebarTab.chats => controller.activeChatPeers,
      _ => controller.peers,
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: const Text('Rete'),
                selected: _activeTab == LeftSidebarTab.allPeers,
                onSelected: (_) =>
                    setState(() => _activeTab = LeftSidebarTab.allPeers),
              ),
              ChoiceChip(
                label: Text('Contatti (${controller.savedContactsList.length})'),
                selected: _activeTab == LeftSidebarTab.savedContacts,
                onSelected: (_) =>
                    setState(() => _activeTab = LeftSidebarTab.savedContacts),
              ),
              ChoiceChip(
                label: Text('Chat (${controller.activeChatPeers.length})'),
                selected: _activeTab == LeftSidebarTab.chats,
                onSelected: (_) =>
                    setState(() => _activeTab = LeftSidebarTab.chats),
              ),
              ChoiceChip(
                label: Text('Cronologia (${controller.fileHistory.length})'),
                selected: _activeTab == LeftSidebarTab.fileHistory,
                onSelected: (_) =>
                    setState(() => _activeTab = LeftSidebarTab.fileHistory),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: displayedPeers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(
                      _activeTab == LeftSidebarTab.savedContacts
                          ? 'Nessun contatto salvato.\nClicca sulla stella accanto a un host per salvarlo e rendere la chat permanente.'
                          : 'Nessun nodo rilevato.\nAssicurati di essere sulla stessa rete Wi-Fi o aggiungi un IP manualmente.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: displayedPeers.length,
                  itemBuilder: (context, idx) {
                    final peer = displayedPeers[idx];
                    final isSelected =
                        controller.selectedPeer?.nodeId == peer.nodeId;
                    final lastMsg = controller.lastMessageForPeer(peer.nodeId);
                    final unread = controller.unreadCountForPeer(peer.nodeId);

                    return ListTile(
                      selected: isSelected,
                      leading: Stack(
                        children: [
                          CircleAvatar(
                            child: Icon(
                              peer.platform == PeerPlatform.windows
                                  ? Icons.desktop_windows_rounded
                                  : Icons.smartphone_rounded,
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
                                    ? Colors.greenAccent
                                    : Colors.grey,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.black, width: 1.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              peer.alias,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (unread > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$unread',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        lastMsg != null
                            ? '${lastMsg.isOutgoing ? "Tu: " : ""}${lastMsg.content}'
                            : '${peer.ipAddress} • ${peer.isOnline ? "Online" : "Offline (Chat salvata)"}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: peer.isTrusted
                            ? 'Rimuovi dai Contatti Fidati'
                            : 'Salva come Contatto Fidato (Chat permanente)',
                        icon: Icon(
                          peer.isTrusted
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: peer.isTrusted ? Colors.amber : null,
                        ),
                        onPressed: () => controller.toggleSaveContact(peer),
                      ),
                      onTap: () {
                        if (_activeTab == LeftSidebarTab.fileHistory) {
                          setState(() => _activeTab = LeftSidebarTab.chats);
                        }
                        controller.selectPeer(peer);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Vista della Cronologia dei File Mandati e Ricevuti
  Widget _buildFileHistoryView(
    BuildContext context,
    P2PController controller,
  ) {
    final List<FileHistoryEntry> items = switch (_historyFilter) {
      'sent' => controller.sentFileHistory,
      'received' => controller.receivedFileHistory,
      _ => controller.fileHistory,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            children: [
              const Icon(Icons.history_edu_rounded),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Cronologia Trasferimenti File',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'sent',
                    label: Text('Inviati (${controller.sentFileHistory.length})'),
                  ),
                  ButtonSegment(
                    value: 'received',
                    label: Text(
                      'Ricevuti (${controller.receivedFileHistory.length})',
                    ),
                  ),
                  const ButtonSegment(value: 'all', label: Text('Tutti')),
                ],
                selected: {_historyFilter},
                onSelectionChanged: (v) =>
                    setState(() => _historyFilter = v.first),
              ),
              const SizedBox(width: 8),
              if (controller.fileHistory.isNotEmpty)
                IconButton(
                  tooltip: 'Svuota cronologia',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: controller.clearFileHistory,
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text('Nessun file presente in questa sezione.'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = items[index];
                    final bool exists = entry.filePath != null &&
                        File(entry.filePath!).existsSync();

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            entry.isOutgoing
                                ? Icons.upload_file_rounded
                                : Icons.downloading_rounded,
                          ),
                        ),
                        title: Text(
                          entry.fileName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${entry.isOutgoing ? "Inviato a" : "Ricevuto da"}: ${entry.peerAlias} (${entry.peerIp})\n'
                          'Dimensione: ${_formatBytes(entry.fileSizeBytes)} • ${DateFormat("dd/MM/yyyy HH:mm").format(entry.timestamp)}',
                        ),
                        isThreeLine: true,
                        trailing: exists
                            ? FilledButton.tonalIcon(
                                icon: const Icon(
                                  Icons.visibility_rounded,
                                  size: 18,
                                ),
                                label: const Text('Anteprima'),
                                onPressed: () => _openFilePreview(
                                  context,
                                  fileName: entry.fileName,
                                  filePath: entry.filePath,
                                ),
                              )
                            : const Chip(label: Text('File spostato')),
                        onTap: exists
                            ? () => _openFilePreview(
                                  context,
                                  fileName: entry.fileName,
                                  filePath: entry.filePath,
                                )
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Area Chat con supporto allo scorrimento tra chat e anteprima multimediale
  Widget _buildChatArea(
    BuildContext context,
    P2PController controller, {
    bool isMobile = false,
  }) {
    final PeerNode? peer = controller.selectedPeer;
    if (peer == null) {
      return const Center(
        child: Text(
          'Seleziona un nodo o un contatto salvato per chattare o inviare file.',
        ),
      );
    }

    final messages = controller.messagesForSelectedPeer;
    final scrollController = _scrollControllerForPeer(peer.nodeId);

    return GestureDetector(
      // Permette di scorrere orizzontalmente tra le diverse chat su mobile/touch
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -400) {
          controller.cycleActiveChat(1);
        } else if (details.primaryVelocity! > 400) {
          controller.cycleActiveChat(-1);
        }
      },
      child: Column(
        children: [
          // Intestazione della Chat selezionata
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                if (isMobile)
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => controller.selectPeer(null),
                  ),
                Icon(
                  peer.isOnline ? Icons.circle : Icons.circle_outlined,
                  size: 12,
                  color: peer.isOnline ? Colors.greenAccent : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        peer.alias,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15.5,
                        ),
                      ),
                      Text(
                        '${peer.ipAddress}:${peer.tcpPort} • ${peer.isTrusted ? "Contatto Fidato (Chat Permanente)" : "Host Temporaneo (Richiesta Obbligatoria)"}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: peer.isTrusted
                      ? 'Contatto Fidato Salvato'
                      : 'Salva come Contatto Fidato',
                  icon: Icon(
                    peer.isTrusted
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: peer.isTrusted ? Colors.amber : null,
                  ),
                  onPressed: () => controller.toggleSaveContact(peer),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.attach_file_rounded, size: 18),
                  label: const Text('Invia File'),
                  onPressed: controller.isTransferring
                      ? null
                      : () => controller.pickAndSendFile(targetOverride: peer),
                ),
              ],
            ),
          ),

          // Lista Messaggi e File con Anteprima
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      'Nessun messaggio con ${peer.alias}.\nInvia un testo o un file (anche di grandi dimensioni)!',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(14),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return _buildMessageBubble(context, controller, msg);
                    },
                  ),
          ),

          // Barra di input messaggio e allegato
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Allega e invia file frammentato',
                  icon: const Icon(Icons.add_rounded),
                  onPressed: controller.isTransferring
                      ? null
                      : () => controller.pickAndSendFile(targetOverride: peer),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: const InputDecoration(
                      hintText: 'Scrivi un messaggio...',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (val) => _submitText(controller),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send_rounded),
                  onPressed: () => _submitText(controller),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _submitText(P2PController controller) {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();
    controller.sendText(text);
  }

  Widget _buildMessageBubble(
    BuildContext context,
    P2PController controller,
    P2PChatMessage msg,
  ) {
    final bool isMe = msg.isOutgoing;
    final bool isFile = msg.type == TransferPayloadType.binaryFile;
    final bool hasLocalFile =
        msg.filePath != null && File(msg.filePath!).existsSync();

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          color: isMe
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).cardTheme.color,
          margin: const EdgeInsets.symmetric(vertical: 5),
          child: InkWell(
            borderRadius:
                BorderRadius.circular(controller.uiStyle.borderRadius),
            onTap: isFile
                ? () => _openFilePreview(
                      context,
                      fileName: msg.content,
                      filePath: msg.filePath,
                    )
                : null,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isFile) ...[
                    // Se è un'immagine presente su disco, mostra subito la miniatura cliccabile
                    if (_isImageFile(msg.content) && hasLocalFile)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(msg.filePath!),
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isImageFile(msg.content)
                              ? Icons.image_rounded
                              : _isVideoFile(msg.content)
                                  ? Icons.movie_creation_rounded
                                  : _isAudioFile(msg.content)
                                      ? Icons.audiotrack_rounded
                                      : Icons.insert_drive_file_rounded,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg.content,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${_formatBytes(msg.fileSize ?? 0)} • Tocca per aprire l\'anteprima',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ] else
                    Text(msg.content, style: const TextStyle(fontSize: 14.5)),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('HH:mm').format(msg.timestamp),
                    style: TextStyle(
                      fontSize: 10.5,
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
          ),
        ),
      ),
    );
  }

  void _showConnectByIpDialog(
    BuildContext context,
    P2PController controller,
  ) {
    final ipCtrl = TextEditingController();
    final aliasCtrl = TextEditingController();
    bool saveAsTrusted = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Connetti o Salva Host via IP'),
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
                  labelText: 'Nome Contatto (opzionale)',
                ),
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Salva come Contatto Fidato'),
                subtitle: const Text(
                  'Chat permanente e ricezione file senza richiesta',
                ),
                value: saveAsTrusted,
                onChanged: (v) =>
                    setDialogState(() => saveAsTrusted = v ?? true),
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
                  saveAsTrusted: saveAsTrusted,
                );
              },
              child: const Text('Connetti'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsAndThemesSheet(
    BuildContext context,
    P2PController controller,
  ) {
    final aliasCtrl = TextEditingController(text: controller.localAlias);
    final clientIdCtrl =
        TextEditingController(text: controller.googleDesktopClientId);
    final clientSecretCtrl =
        TextEditingController(text: controller.googleDesktopClientSecret);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        maxChildSize: 0.92,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Personalizzazione, Temi e Account Google',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Sezione Temi Colore
            const Text(
              'Tema Colore',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AppThemePreset.values.map((preset) {
                return ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: preset.darkSeed),
                  label: Text(preset.label),
                  selected: controller.themePreset == preset,
                  onSelected: (_) => controller.setThemePreset(preset),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Sezione Stile UI
            const Text(
              'Stile Interfaccia e Bordi',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
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
            const Divider(height: 28),

            SwitchListTile(
              title: const Text('Modalità Scura (Dark Mode)'),
              value: controller.isDarkMode,
              onChanged: controller.toggleDarkMode,
            ),
            if (controller.isDarkMode)
              SwitchListTile(
                title: const Text('Nero Puro AMOLED'),
                value: controller.useAmoledBlack,
                onChanged: controller.toggleAmoledBlack,
              ),
            SwitchListTile(
              title: const Text('Effetto Sonoro (SFX) su Richieste File'),
              subtitle: const Text(
                'Riproduce un suono quando un host non fidato chiede di inviare un file',
              ),
              value: controller.sfxEnabled,
              onChanged: controller.toggleSfx,
            ),
            const Divider(height: 28),

            // Vero Login Google OAuth 2.0 (Desktop PKCE + Android)
            const Text(
              'Account Google (OAuth 2.0 PKCE Desktop / Android)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) ...[
              TextField(
                controller: clientIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'Google OAuth Desktop Client ID',
                  hintText: 'es. 123456-abc.apps.googleusercontent.com',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: clientSecretCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Google OAuth Client Secret ( per Desktop)',
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Salva Credenziali OAuth'),
                  onPressed: () {
                    controller.saveGoogleOAuthCredentials(
                      clientId: clientIdCtrl.text,
                      clientSecret: clientSecretCtrl.text,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Credenziali OAuth salvate.'),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (controller.isGoogleSignedIn)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.verified_user)),
                title: Text(controller.googleDisplayName ?? 'Utente Google'),
                subtitle: Text(controller.googleEmail ?? ''),
                trailing: OutlinedButton(
                  onPressed: controller.signOutGoogle,
                  child: const Text('Disconnetti'),
                ),
              )
            else
              FilledButton.icon(
                icon: controller.isAuthenticatingGoogle
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login_rounded),
                label: const Text('Accedi con Google (OAuth 2.0 Reale)'),
                onPressed: controller.isAuthenticatingGoogle
                    ? null
                    : () async {
                        await controller.saveGoogleOAuthCredentials(
                          clientId: clientIdCtrl.text,
                          clientSecret: clientSecretCtrl.text,
                        );
                        await controller.signInWithGoogle();
                      },
              ),
            const Divider(height: 28),

            // Modifica Alias Locale
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: aliasCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Il tuo Alias in Rete',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    controller.updateLocalAlias(aliasCtrl.text);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Aggiorna'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog modale di Anteprima per Foto, Video, Audio e File di Testo
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
      _videoController = VideoPlayerController.file(File(widget.filePath));
      await _videoController!.initialize();
      await _videoController!.play();
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
              ? '${content.substring(0, 20000)}\n\n... [File troncato per anteprima]'
              : content;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _textContent = 'Impossibile leggere il testo: $e');
    }
  }

  Future<void> _openWithSystemApp() async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', widget.filePath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [widget.filePath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [widget.filePath]);
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
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
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
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                    TextButton.icon(
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: const Text('Mostra nella cartella'),
                      onPressed: _openWithSystemApp,
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Flexible(child: _buildPreviewBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewBody() {
    if (widget.isImage) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 5.0,
        child: Image.file(File(widget.filePath), fit: BoxFit.contain),
      );
    }

    if (widget.isAudio) {
      final double maxSec =
          _audioDuration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
      final double curSec =
          _audioPosition.inMilliseconds.toDouble().clamp(0.0, maxSec);

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_note_rounded, size: 64),
            const SizedBox(height: 16),
            Slider(
              value: curSec,
              max: maxSec,
              onChanged: (val) {
                _audioPlayer?.seek(Duration(milliseconds: val.toInt()));
              },
            ),
            Text(
              '${_audioPosition.inMinutes}:${(_audioPosition.inSeconds % 60).toString().padLeft(2, "0")} / '
              '${_audioDuration.inMinutes}:${(_audioDuration.inSeconds % 60).toString().padLeft(2, "0")}',
            ),
            const SizedBox(height: 12),
            IconButton.filled(
              iconSize: 36,
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
        return Center(
          child: Text('Codec video gestito dal sistema:\n$_videoError'),
        );
      }
      if (!_videoInitialized || _videoController == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
          ),
          VideoProgressIndicator(_videoController!, allowScrubbing: true),
          const SizedBox(height: 8),
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
          const Icon(Icons.insert_drive_file_outlined, size: 56),
          const SizedBox(height: 12),
          Text('Percorso salvataggio:\n${widget.filePath}',
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
