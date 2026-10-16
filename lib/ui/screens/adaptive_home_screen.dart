import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:desktop_drop/desktop_drop.dart';
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
  String _vaultFilter = 'all';
  bool _isDraggingFileOverChat = false;
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
    return '${size.toStringAsFixed(i == 0 ? 0 : 1)}${suffixes[i]}';
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '0.0 MB/s';
    final double mb = bytesPerSec / (1024 * 1024);
    if (mb >= 1.0) {
      return '${mb.toStringAsFixed(1)} MB/s';
    }
    final double kb = bytesPerSec / 1024;
    return '${kb.toStringAsFixed(0)} KB/s';
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

  void _confirmDeleteChat(
    BuildContext context,
    P2PController controller,
    PeerNode peer,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Elimina chat con ${peer.alias}'),
        content: const Text(
          'Vuoi eliminare definitivamente la cronologia dei messaggi di questa chat?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              controller.deleteChat(peer.nodeId);
            },
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<P2PController>();
    final bool isDesktop = MediaQuery.of(context).size.width >= 860;

    if (!isDesktop && controller.selectedPeer != null) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildIncomingRequestOverlay(context, controller),
              _buildLiveTransferMonitor(context, controller),
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
          _buildLiveTransferMonitor(context, controller),
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
                  label: 'Chat (${controller.activeChatPeers.length})',
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

  Widget _buildLiveTransferMonitor(
    BuildContext context,
    P2PController controller,
  ) {
    final ActiveTransferTask? task = controller.activeTransferTask;
    if (task == null) return const SizedBox.shrink();

    final Color accent = Theme.of(context).colorScheme.primary;
    final bool isPaused = task.state == TransferTaskState.paused;
    final bool isWaiting = task.state == TransferTaskState.waitingApproval;
    final int pct = (task.progress * 100).round();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                task.isOutgoing
                    ? Icons.upload_rounded
                    : Icons.download_rounded,
                color: accent,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isWaiting
                          ? 'In attesa che ${task.peerAlias} accetti "${task.fileName}"...'
                          : '${task.isOutgoing ? "Invio a" : "Ricezione da"} ${task.peerAlias}:${task.fileName}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isWaiting
                          ? 'Dimensione: ${_formatBytes(task.totalBytes)}'
                          : '${_formatBytes(task.transferredBytes)} / ${_formatBytes(task.totalBytes)} ($pct%) • '
                              '${isPaused ? "IN PAUSA" : _formatSpeed(task.speedBytesPerSec)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: isPaused ? Colors.amber : accent,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isWaiting)
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  tooltip: isPaused ? 'Riprendi' : 'Metti in pausa',
                  icon: Icon(
                    isPaused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    size: 18,
                  ),
                  onPressed: isPaused
                      ? controller.resumeTransfer
                      : controller.pauseTransfer,
                ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                tooltip: 'Annulla trasferimento',
                style: IconButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                ),
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: controller.cancelTransfer,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: isWaiting ? null : task.progress,
              minHeight: 6,
            ),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent, width: 1.5),
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
                      '${req.fileName} •${_formatBytes(req.fileSizeBytes)}',
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
                isLabelVisible: controller.totalUnreadCount > 0
