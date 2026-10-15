import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/p2p_packet.dart';
import '../../models/peer_node.dart';
import '../../providers/p2p_controller.dart';

class AdaptiveHomeScreen extends StatefulWidget {
  const AdaptiveHomeScreen({super.key});

  @override
  State<AdaptiveHomeScreen> createState() => _AdaptiveHomeScreenState();
}

class _AdaptiveHomeScreenState extends State<AdaptiveHomeScreen> {
  final TextEditingController _textController = TextEditingController();
  int _mobileTabIndex = 0;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<P2PController>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 840;

        if (isDesktop) {
          // Layout Desktop Windows (.exe): Split-View a 2 pannelli
          return Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            body: Row(
              children: [
                SizedBox(
                  width: 320,
                  child: _buildPeersSidebar(controller, isDesktop: true),
                ),
                const VerticalDivider(width: 1, color: Color(0xFF1E293B)),
                Expanded(
                  child: _buildConversationWorkspace(controller),
                ),
              ],
            ),
          );
        }

        // Layout Mobile Android (.apk): Navigazione a schede adattiva
        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          body: SafeArea(
            child: _mobileTabIndex == 0
                ? _buildPeersSidebar(controller, isDesktop: false)
                : _buildConversationWorkspace(controller),
          ),
          bottomNavigationBar: NavigationBar(
            backgroundColor: const Color(0xFF1E293B),
            selectedIndex: _mobileTabIndex,
            onDestinationSelected: (idx) => setState(() => _mobileTabIndex = idx),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.radar),
                label: 'Nodi LAN (${controller.peers.length})',
              ),
              const NavigationDestination(
                icon: Icon(Icons.swap_horiz_rounded),
                label: 'Chat & File Stream',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPeersSidebar(P2PController controller, {required bool isDesktop}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'LanPulse P2P',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${controller.localAlias} · ${controller.localIp ?? "Ricerca IP..."}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ),
        Expanded(
          child: controller.peers.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'In ascolto di nodi sulla rete Wi-Fi locale (UDP :45454)...',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: controller.peers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final PeerNode peer = controller.peers[index];
                    final bool isSelected =
                        controller.selectedPeer?.nodeId == peer.nodeId;

                    return Material(
                      color: isSelected
                          ? const Color(0xFF1E293B)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          controller.selectPeer(peer);
                          if (!isDesktop) {
                            setState(() => _mobileTabIndex = 1);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Icon(
                                peer.platform == PeerPlatform.windows
                                    ? Icons.desktop_windows_outlined
                                    : Icons.phone_android_outlined,
                                color: const Color(0xFF38BDF8),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      peer.alias,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${peer.ipAddress}:${peer.tcpPort}',
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildConversationWorkspace(P2PController controller) {
    final PeerNode? activePeer = controller.selectedPeer;
    if (activePeer == null) {
      return const Center(
        child: Text(
          'Seleziona un nodo dalla lista per avviare lo scambio di messaggi o file.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
      );
    }

    final List<P2PChatMessage> messages = controller.messagesForSelectedPeer;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activePeer.alias,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Socket TCP diretto · ${activePeer.ipAddress}:${activePeer.tcpPort}',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: controller.isTransferring
                    ? null
                    : () => controller.pickAndSendFile(),
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Invia File'),
              ),
            ],
          ),
        ),
        if (controller.isTransferring)
          LinearProgressIndicator(
            value: controller.activeTransferProgress,
            backgroundColor: const Color(0xFF1E293B),
            color: const Color(0xFF38BDF8),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final P2PChatMessage msg = messages[index];
              return Align(
                alignment: msg.isOutgoing
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  constraints: const BoxConstraints(maxWidth: 420),
                  decoration: BoxDecoration(
                    color: msg.isOutgoing
                        ? const Color(0xFF0284C7)
                        : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (msg.type == TransferPayloadType.binaryFile)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.insert_drive_file_outlined,
                                color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                msg.content,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          msg.content,
                          style: const TextStyle(color: Colors.white),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFF1E293B))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Scrivi un messaggio sul socket TCP...',
                    hintStyle: TextStyle(color: Color(0xFF64748B)),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (value) {
                    controller.sendText(value);
                    _textController.clear();
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () {
                  controller.sendText(_textController.text);
                  _textController.clear();
                },
                child: const Text('Invia'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
