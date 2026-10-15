import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
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
  int _activeTabIndex = 0; // 0: Radar/Nodi, 1: Chat & File, 2: Impostazioni

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _copyIpToClipboard(BuildContext context, String ip) {
    Clipboard.setData(ClipboardData(text: ip));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Indirizzo IP copiato: $ip'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showConnectByIpDialog(
    BuildContext context,
    P2PController controller,
  ) async {
    final ipCtrl = TextEditingController();
    final aliasCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: controller.tcpPort.toString());

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.wifi_tethering, color: Color(0xFF38BDF8)),
            SizedBox(width: 10),
            Text('Connessione Diretta Wi-Fi (IP)'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Inserisci l\'indirizzo IP mostrato in alto sull\'altro dispositivo (es. S25 Ultra o PC) per inviare file direttamente via Wi-Fi.',
                style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ipCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Indirizzo IPv4 del dispositivo',
                  hintText: 'es. 192.168.1.45',
                  prefixIcon: Icon(Icons.lan_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: aliasCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nome (opzionale)',
                        hintText: 'es. S25 Ultra / PC Casa',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: portCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Porta TCP',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final ip = ipCtrl.text.trim();
              if (ip.isEmpty) return;
              final port = int.tryParse(portCtrl.text.trim()) ?? controller.tcpPort;
              Navigator.pop(ctx);
              await controller.connectByIp(
                ipAddress: ip,
                customAlias: aliasCtrl.text.trim(),
                port: port,
              );
              setState(() => _activeTabIndex = 1);
            },
            icon: const Icon(Icons.link),
            label: const Text('Connetti Ora'),
          ),
        ],
      ),
    );
  }

  Future<void> _showGoogleLoginDialog(
    BuildContext context,
    P2PController controller,
  ) async {
    final nameCtrl = TextEditingController(text: controller.googleDisplayName ?? '');
    final emailCtrl = TextEditingController(text: controller.googleEmail ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.account_circle, color: Color(0xFF38BDF8)),
            SizedBox(width: 10),
            Text('Accedi con Google'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Collega il tuo account Google per sincronizzare automaticamente il tuo Username e renderti subito riconoscibile sulla rete Wi-Fi.',
                style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome visualizzato',
                  hintText: 'es. Mario Rossi',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email Google (@gmail.com)',
                  hintText: 'tuonome@gmail.com',
                  prefixIcon: Icon(Icons.alternate_email),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await controller.signInWithGoogle(
                fallbackName: nameCtrl.text,
                fallbackEmail: emailCtrl.text.isEmpty
                    ? 'utente@gmail.com'
                    : emailCtrl.text,
              );
            },
            icon: const Icon(Icons.login),
            label: const Text('Continua con Google'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<P2PController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 900;

        if (isDesktop) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  backgroundColor: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF1F5F9),
                  selectedIndex: _activeTabIndex == 2 ? 1 : 0,
                  onDestinationSelected: (idx) {
                    setState(() => _activeTabIndex = idx == 1 ? 2 : 0);
                  },
                  labelType: NavigationRailLabelType.all,
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: Color(0xFF0284C7),
                      child: Icon(Icons.bolt_rounded, color: Colors.white, size: 26),
                    ),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.hub_outlined),
                      selectedIcon: Icon(Icons.hub),
                      label: Text('Workspace'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Impostazioni'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                if (_activeTabIndex == 2)
                  Expanded(child: _buildSettingsView(context, controller))
                else ...[
                  SizedBox(
                    width: 360,
                    child: _buildPeersSidebar(context, controller, isDesktop: true),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _buildConversationWorkspace(context, controller),
                  ),
                ],
              ],
            ),
          );
        }

        // Layout Mobile (Samsung S25 Ultra)
        return Scaffold(
          body: SafeArea(
            child: IndexedStack(
              index: _activeTabIndex,
              children: [
                _buildPeersSidebar(context, controller, isDesktop: false),
                _buildConversationWorkspace(context, controller),
                _buildSettingsView(context, controller),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _activeTabIndex,
            onDestinationSelected: (idx) => setState(() => _activeTabIndex = idx),
            destinations: [
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: controller.peers.isNotEmpty,
                  label: Text('${controller.peers.length}'),
                  child: const Icon(Icons.radar_outlined),
                ),
                selectedIcon: const Icon(Icons.radar),
                label: 'Dispositivi Wi-Fi',
              ),
              const NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline_rounded),
                selectedIcon: Icon(Icons.chat_bubble_rounded),
                label: 'Chat & File',
              ),
              const NavigationDestination(
                icon: Icon(Icons.tune_rounded),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Impostazioni',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPeersSidebar(
    BuildContext context,
    P2PController controller, {
    required bool isDesktop,
  }) {
    final String ipDisplay = controller.localIp ?? 'Non connesso al Wi-Fi';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header moderno con Card IP sempre in vista
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF0284C7).withValues(alpha: 0.22),
                Colors.transparent,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: const Border(
              bottom: BorderSide(color: Color(0xFF1E293B)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.wifi_rounded, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'LanPulse P2P',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Aggiorna Rete e IP',
                    onPressed: controller.refreshNetwork,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Card IP ben visibile per condivisione Wi-Fi immediata
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.router_outlined,
                        color: Color(0xFF38BDF8),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'IL TUO IP WI-FI (${controller.localAlias})',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: Color(0xFF94A3B8),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          SelectableText(
                            '$ipDisplay : ${controller.tcpPort}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: Color(0xFF38BDF8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (controller.localIp != null)
                      IconButton(
                        tooltip: 'Copia IP',
                        onPressed: () =>
                            _copyIpToClipboard(context, controller.localIp!),
                        icon: const Icon(Icons.copy_rounded, size: 18),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () => _showConnectByIpDialog(context, controller),
                  icon: const Icon(Icons.add_link_rounded, size: 18),
                  label: const Text('Connetti a Dispositivo tramite IP Wi-Fi'),
                ),
              ),
            ],
          ),
        ),

        if (controller.errorBanner != null)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.amber, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    controller.errorBanner!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: controller.clearError,
                ),
              ],
            ),
          ),

        // Lista Nodi Rilevati o Aggiunti via IP
        Expanded(
          child: controller.peers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF38BDF8).withValues(alpha: 0.1),
                          ),
                          child: const Icon(
                            Icons.wifi_find_rounded,
                            size: 42,
                            color: Color(0xFF38BDF8),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Ricerca dispositivi sulla rete Wi-Fi...',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Se il tuo router blocca il broadcast automatico, premi "Connetti a Dispositivo tramite IP Wi-Fi" e inserisci l\'IP dell\'altro dispositivo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: controller.peers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final PeerNode peer = controller.peers[index];
                    final bool isSelected =
                        controller.selectedPeer?.nodeId == peer.nodeId;
                    final bool isManual = peer.nodeId.startsWith('manual-');

                    return Material(
                      color: isSelected
                          ? const Color(0xFF0284C7).withValues(alpha: 0.2)
                          : const Color(0xFF1E293B).withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          controller.selectPeer(peer);
                          if (!isDesktop) {
                            setState(() => _activeTabIndex = 1);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF38BDF8)
                                  : Colors.transparent,
                              width: 1.4,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor:
                                    const Color(0xFF38BDF8).withValues(alpha: 0.15),
                                child: Icon(
                                  peer.platform == PeerPlatform.windows
                                      ? Icons.desktop_windows_rounded
                                      : peer.platform == PeerPlatform.android
                                          ? Icons.phone_android_rounded
                                          : Icons.devices_other_rounded,
                                  color: const Color(0xFF38BDF8),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            peer.alias,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: (isManual
                                                    ? Colors.amber
                                                    : Colors.emeraldAccent ??
                                                        Colors.greenAccent)
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            isManual ? 'IP Diretto' : 'Online',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: isManual
                                                  ? Colors.amber
                                                  : Colors.greenAccent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
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
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFF64748B),
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

  Widget _buildConversationWorkspace(
    BuildContext context,
    P2PController controller,
  ) {
    final PeerNode? activePeer = controller.selectedPeer;
    if (activePeer == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.swap_horizontal_circle_outlined,
                size: 56,
                color: Color(0xFF64748B),
              ),
              const SizedBox(height: 16),
              const Text(
                'Nessun nodo selezionato',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Seleziona un dispositivo dalla lista o connettiti direttamente inserendo il suo indirizzo IP Wi-Fi.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _showConnectByIpDialog(context, controller),
                icon: const Icon(Icons.add_link_rounded),
                label: const Text('Connetti tramite IP'),
              ),
            ],
          ),
        ),
      );
    }

    final List<P2PChatMessage> messages = controller.messagesForSelectedPeer;
    final DateFormat timeFormatter = DateFormat('HH:mm');

    return Column(
      children: [
        // Top Bar della conversazione attiva
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    const Color(0xFF38BDF8).withValues(alpha: 0.15),
                child: const Icon(Icons.devices_rounded, color: Color(0xFF38BDF8)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activePeer.alias,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Connessione TCP Wi-Fi · ${activePeer.ipAddress}:${activePeer.tcpPort}',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: controller.isTransferring
                    ? null
                    : () => controller.pickAndSendFile(),
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('Invia File'),
              ),
            ],
          ),
        ),

        if (controller.isTransferring)
          Column(
            children: [
              LinearProgressIndicator(
                value: controller.activeTransferProgress,
                minHeight: 6,
                backgroundColor: const Color(0xFF1E293B),
                color: const Color(0xFF38BDF8),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Trasferimento in corso: ${(controller.activeTransferProgress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8)),
                ),
              ),
            ],
          ),

        // Area Messaggi e File
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Text(
                    'Invia un messaggio o un file a ${activePeer.alias} (${activePeer.ipAddress})',
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final P2PChatMessage msg = messages[index];
                    final bool isFile =
                        msg.type == TransferPayloadType.binaryFile;

                    return Align(
                      alignment: msg.isOutgoing
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        constraints: const BoxConstraints(maxWidth: 440),
                        decoration: BoxDecoration(
                          color: msg.isOutgoing
                              ? const Color(0xFF0284C7)
                              : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft:
                                Radius.circular(msg.isOutgoing ? 16 : 4),
                            bottomRight:
                                Radius.circular(msg.isOutgoing ? 4 : 16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isFile)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.folder_zip_outlined,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          msg.content,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (msg.fileSize != null)
                                          Text(
                                            _formatBytes(msg.fileSize!),
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11,
                                            ),
                                          ),
                                        if (msg.filePath != null)
                                          Text(
                                            'Salvato in: ${msg.filePath}',
                                            style: const TextStyle(
                                              color: Colors.white60,
                                              fontSize: 10,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            else
                              SelectableText(
                                msg.content,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                ),
                              ),
                            const SizedBox(height: 6),
                            Text(
                              timeFormatter.format(msg.timestamp),
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Barra di invio inferiore
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFF1E293B))),
          ),
          child: Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Allega e invia file',
                onPressed: controller.isTransferring
                    ? null
                    : () => controller.pickAndSendFile(),
                icon: const Icon(Icons.attach_file_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _textController,
                  decoration: InputDecoration(
                    hintText: 'Scrivi un messaggio a ${activePeer.alias}...',
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (value) {
                    controller.sendText(value);
                    _textController.clear();
                  },
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () {
                  controller.sendText(_textController.text);
                  _textController.clear();
                },
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Invia'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsView(BuildContext context, P2PController controller) {
    final aliasController = TextEditingController(text: controller.localAlias);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Impostazioni & Account',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Gestisci il tuo profilo Google, il tuo indirizzo IP Wi-Fi e le preferenze di trasferimento.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 24),

        // SEZIONE 1: Account Google
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.account_circle_outlined, color: Color(0xFF38BDF8)),
                    SizedBox(width: 10),
                    Text(
                      'Account Google',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (controller.isGoogleSignedIn)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF0284C7),
                      child: Text(
                        (controller.googleDisplayName ?? 'G')[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      controller.googleDisplayName ?? 'Utente Google',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(controller.googleEmail ?? ''),
                    trailing: OutlinedButton.icon(
                      onPressed: controller.signOutGoogle,
                      icon: const Icon(Icons.logout, size: 16),
                      label: const Text('Disconnetti'),
                    ),
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Accedi con Google per impostare automaticamente il tuo nome utente su tutti i dispositivi della rete.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 16),
                      FilledButton.icon(
                        onPressed: () =>
                            _showGoogleLoginDialog(context, controller),
                        icon: const Icon(Icons.login),
                        label: const Text('Accedi con Google'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // SEZIONE 2: Stato Rete & Indirizzo IP in Vista
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.settings_ethernet_rounded, color: Color(0xFF38BDF8)),
                    SizedBox(width: 10),
                    Text(
                      'Indirizzo IP Wi-Fi & Diagnostica Rete',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Indirizzo IPv4 Principale (Wi-Fi / LAN)'),
                  subtitle: Text(
                    controller.localIp ?? 'Nessun IP rilevato',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 15,
                      color: Color(0xFF38BDF8),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Copia IP',
                    onPressed: controller.localIp == null
                        ? null
                        : () =>
                            _copyIpToClipboard(context, controller.localIp!),
                    icon: const Icon(Icons.copy_rounded),
                  ),
                ),
                if (controller.allLocalIps.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Tutte le schede rilevate: ${controller.allLocalIps.join(", ")}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: aliasController,
                        decoration: const InputDecoration(
                          labelText: 'Nome Dispositivo (Alias P2P)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () {
                        controller.updateLocalAlias(aliasController.text);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Alias dispositivo aggiornato!'),
                          ),
                        );
                      },
                      child: const Text('Salva Nome'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // SEZIONE 3: Aspetto & Trasferimenti
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Tema Scuro (Dark Mode)'),
                subtitle: const Text('Interfaccia scura ad alto contrasto'),
                value: controller.isDarkMode,
                onChanged: controller.toggleDarkMode,
              ),
              if (controller.isDarkMode)
                SwitchListTile(
                  title: const Text('Modalità Nero AMOLED (S25 Ultra)'),
                  subtitle: const Text(
                    'Sfondo nero puro #000000 per risparmiare batteria su display OLED',
                  ),
                  value: controller.useAmoledBlack,
                  onChanged: controller.toggleAmoledBlack,
                ),
              SwitchListTile(
                title: const Text('Salvataggio automatico file in arrivo'),
                subtitle: const Text(
                  'Salva automaticamente i file ricevuti nella cartella Download/Documenti',
                ),
                value: controller.autoAcceptFiles,
                onChanged: controller.toggleAutoAcceptFiles,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
