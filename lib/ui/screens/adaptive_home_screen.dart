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
  final TextEditingController _aliasController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  int _activeTabIndex = 0; // 0: Radar/Dispositivi, 1: Chat, 2: Impostazioni

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctrl = context.read<P2PController>();
      _aliasController.text = ctrl.localAlias;
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _aliasController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _copyIpToClipboard(BuildContext context, String ip) {
    Clipboard.setData(ClipboardData(text: ip));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Indirizzo IP copiato negli appunti: $ip'),
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
    final portCtrl =
        TextEditingController(text: controller.tcpPort.toString());

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.wifi_tethering_rounded, color: Color(0xFF38BDF8)),
            SizedBox(width: 10),
            Expanded(child: Text('Connetti tramite IP Wi-Fi')),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Inserisci l\'indirizzo IPv4 mostrato nel riquadro in alto sull\'altro dispositivo (PC o S25 Ultra).',
                style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ipCtrl,
                autofocus: true,
                // TextInputType.url mostra sempre il punto (.) anche sulla tastiera Samsung!
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Indirizzo IP del dispositivo',
                  hintText: 'es. 192.168.1.45',
                  prefixIcon: const Icon(Icons.lan_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: aliasCtrl,
                      decoration: InputDecoration(
                        labelText: 'Nome (opzionale)',
                        hintText: 'es. PC Desktop / S25',
                        prefixIcon: const Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: portCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Porta',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
              final port =
                  int.tryParse(portCtrl.text.trim()) ?? controller.tcpPort;
              Navigator.pop(ctx);
              await controller.connectByIp(
                ipAddress: ip,
                customAlias: aliasCtrl.text.trim(),
                port: port,
              );
              if (mounted) {
                setState(() => _activeTabIndex = 1);
              }
            },
            icon: const Icon(Icons.bolt_rounded),
            label: const Text('Connetti'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<P2PController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Se siamo sulla scheda Chat (mobile) e il nodo si disconnette o cambia rete,
    // torna automaticamente alla lista dei dispositivi!
    if (_activeTabIndex == 1 && controller.selectedPeer == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _activeTabIndex == 1 && controller.selectedPeer == null) {
          setState(() => _activeTabIndex = 0);
        }
      });
    }

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
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF38BDF8), Color(0xFF6366F1)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.wifi_tethering_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                  destinations: [
                    NavigationRailDestination(
                      icon: Badge(
                        isLabelVisible: controller.peers.isNotEmpty,
                        label: Text('${controller.peers.length}'),
                        child: const Icon(Icons.radar_outlined),
                      ),
                      selectedIcon: const Icon(Icons.radar_rounded),
                      label: const Text('Rete & Chat'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.tune_rounded),
                      selectedIcon: Icon(Icons.settings_rounded),
                      label: Text('Settings'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                if (_activeTabIndex == 2)
                  Expanded(child: _buildSettingsView(context, controller))
                else ...[
                  SizedBox(
                    width: 380,
                    child: _buildPeersSidebar(
                      context,
                      controller,
                      isDesktop: true,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _buildConversationWorkspace(
                      context,
                      controller,
                      isDesktop: true,
                    ),
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
                _buildConversationWorkspace(
                  context,
                  controller,
                  isDesktop: false,
                ),
                _buildSettingsView(context, controller),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _activeTabIndex,
            onDestinationSelected: (idx) =>
                setState(() => _activeTabIndex = idx),
            destinations: [
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: controller.peers.isNotEmpty,
                  label: Text('${controller.peers.length}'),
                  child: const Icon(Icons.radar_outlined),
                ),
                selectedIcon: const Icon(Icons.radar_rounded),
                label: 'Dispositivi',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: controller.selectedPeer != null,
                  backgroundColor: Colors.greenAccent,
                  child: const Icon(Icons.chat_bubble_outline_rounded),
                ),
                selectedIcon: const Icon(Icons.chat_bubble_rounded),
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
    final bool hasIp = controller.localIp != null;
    final String ipDisplay = controller.localIp ?? 'Nessuna Wi-Fi rilevata';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Dashboard Hero Card (Rete + IP + Azioni Rapide)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Riga Titolo + Badge Stato Rete Live
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasIp ? Colors.greenAccent : Colors.amber,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      controller.localAlias,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (controller.isGoogleSignedIn)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_user_rounded,
                            size: 12,
                            color: Color(0xFF38BDF8),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Google',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF38BDF8),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // Box IP Wi-Fi in evidenza
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF090D16).withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.router_rounded,
                      color: Color(0xFF38BDF8),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'IL TUO INDIRIZZO IP WI-FI',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          const SizedBox(height: 2),
                          SelectableText(
                            hasIp
                                ? '$ipDisplay : ${controller.tcpPort}'
                                : ipDisplay,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'monospace',
                              color: Color(0xFF38BDF8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasIp)
                      IconButton(
                        tooltip: 'Copia Indirizzo IP',
                        onPressed: () =>
                            _copyIpToClipboard(context, controller.localIp!),
                        icon: const Icon(
                          Icons.copy_rounded,
                          size: 18,
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Pulsanti Azione: Connetti via IP + Scansione Wi-Fi
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () =>
                          _showConnectByIpDialog(context, controller),
                      icon: const Icon(Icons.add_link_rounded, size: 18),
                      label: const Text(
                        'Connetti via IP',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: controller.isScanningWifi
                          ? null
                          : controller.refreshNetwork,
                      icon: controller.isScanningWifi
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.radar_rounded, size: 18),
                      label: Text(
                        controller.isScanningWifi ? 'Scan...' : 'Scansiona',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Banner notifiche di rete / errori
        if (controller.errorBanner != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: (controller.isBannerError
                      ? Colors.redAccent
                      : const Color(0xFF38BDF8))
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (controller.isBannerError
                        ? Colors.redAccent
                        : const Color(0xFF38BDF8))
                    .withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  controller.isBannerError
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline_rounded,
                  color: controller.isBannerError
                      ? Colors.redAccent
                      : const Color(0xFF38BDF8),
                  size: 18,
                ),
                const SizedBox(width: 10),
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

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DISPOSITIVI SULLA RETE (${controller.peers.length})',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: Color(0xFF94A3B8),
                ),
              ),
              if (controller.isScanningWifi)
                const Text(
                  'Ricerca su sottorete Wi-Fi...',
                  style: TextStyle(fontSize: 11, color: Color(0xFF38BDF8)),
                ),
            ],
          ),
        ),

        // Lista Nodi con pulsanti rapidi "Chat" e "Invia File"
        Expanded(
          child: controller.peers.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF38BDF8)
                                .withValues(alpha: 0.1),
                          ),
                          child: const Icon(
                            Icons.wifi_find_rounded,
                            size: 44,
                            color: Color(0xFF38BDF8),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Nessun dispositivo rilevato al momento',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Assicurati che entrambi i dispositivi siano sulla stessa rete Wi-Fi (o Hotspot) oppure premi "Connetti via IP" per collegarli all\'istante.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  itemCount: controller.peers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final PeerNode peer = controller.peers[index];
                    final bool isSelected =
                        controller.selectedPeer?.nodeId == peer.nodeId;

                    return Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF0284C7).withValues(alpha: 0.16)
                            : const Color(0xFF1E293B).withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF38BDF8)
                              : Colors.white.withValues(alpha: 0.07),
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF38BDF8)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    peer.platform == PeerPlatform.windows
                                        ? Icons.desktop_windows_rounded
                                        : peer.platform == PeerPlatform.android
                                            ? Icons.phone_android_rounded
                                            : Icons.devices_other_rounded,
                                    color: const Color(0xFF38BDF8),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        peer.alias,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
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
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'Attivo',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.greenAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Azioni rapide sulla card: Apri Chat oppure Invia File diretto!
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: () {
                                      controller.selectPeer(peer);
                                      if (!isDesktop) {
                                        setState(() => _activeTabIndex = 1);
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Apri Chat'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                    style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: controller.isTransferring
                                        ? null
                                        : () async {
                                            controller.selectPeer(peer);
                                            if (!isDesktop) {
                                              setState(
                                                  () => _activeTabIndex = 1);
                                            }
                                            await controller.pickAndSendFile(
                                              targetOverride: peer,
                                            );
                                          },
                                    icon: const Icon(
                                      Icons.upload_file_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Invia File'),
                                  ),
                                ),
                              ],
                            ),
                          ],
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
    P2PController controller, {
    required bool isDesktop,
  }) {
    final PeerNode? activePeer = controller.selectedPeer;
    if (activePeer == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.1),
                ),
                child: const Icon(
                  Icons.swap_horiz_rounded,
                  size: 48,
                  color: Color(0xFF38BDF8),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Seleziona un dispositivo per iniziare',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Scegli un nodo dalla lista Wi-Fi o connettiti direttamente tramite indirizzo IP per inviare file e messaggi ad alta velocità.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
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
        // Header della Chat con pulsante Back su Mobile e Invia File
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
          ),
          child: Row(
            children: [
              if (!isDesktop)
                IconButton(
                  tooltip: 'Torna ai dispositivi',
                  onPressed: () => setState(() => _activeTabIndex = 0),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              CircleAvatar(
                backgroundColor:
                    const Color(0xFF38BDF8).withValues(alpha: 0.15),
                child: Icon(
                  activePeer.platform == PeerPlatform.windows
                      ? Icons.desktop_windows_rounded
                      : Icons.phone_android_rounded,
                  color: const Color(0xFF38BDF8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activePeer.alias,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${activePeer.ipAddress}:${activePeer.tcpPort}',
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

        // Barra di avanzamento trasferimento file
        if (controller.isTransferring)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF1E293B),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Trasferimento file su Wi-Fi in corso...',
                      style: TextStyle(fontSize: 12, color: Color(0xFF38BDF8)),
                    ),
                    Text(
                      '${(controller.activeTransferProgress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF38BDF8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: controller.activeTransferProgress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(6),
                  backgroundColor: const Color(0xFF0F172A),
                  color: const Color(0xFF38BDF8),
                ),
              ],
            ),
          ),

        // Messaggi e File scambiati
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Connesso a ${activePeer.alias} (${activePeer.ipAddress}).\nScrivi un messaggio o premi "Invia File" per iniziare.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _chatScrollController,
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
                          gradient: msg.isOutgoing
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFF0284C7),
                                    Color(0xFF2563EB),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: msg.isOutgoing
                              ? null
                              : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft:
                                Radius.circular(msg.isOutgoing ? 18 : 4),
                            bottomRight:
                                Radius.circular(msg.isOutgoing ? 4 : 18),
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
                                      color:
                                          Colors.white.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.insert_drive_file_rounded,
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
                                              fontSize: 11.5,
                                            ),
                                          ),
                                        if (msg.filePath != null)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 3),
                                            child: Text(
                                              msg.isOutgoing
                                                  ? 'Inviato con successo'
                                                  : 'Salvato in: ${msg.filePath}',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 10,
                                              ),
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

        // Barra di inserimento testo e allegato file
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFF1E293B))),
          ),
          child: Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Scegli e invia un file',
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
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Impostazioni & Profilo',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Configura il tuo account Google, il nome del dispositivo e la diagnostica Wi-Fi.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 24),

        // SEZIONE 1: Account Google (via Browser su PC / Nativo su Android)
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.account_circle_outlined,
                      color: Color(0xFF38BDF8),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Account Google',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
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
                      icon: const Icon(Icons.logout_rounded, size: 16),
                      label: const Text('Esci'),
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Autenticati tramite il browser di sistema (su PC) o tramite Google Play Services (su Android) per sincronizzare il tuo profilo sulla rete locale.',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: controller.isAuthenticatingGoogle
                            ? null
                            : controller.signInWithGoogle,
                        icon: controller.isAuthenticatingGoogle
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.open_in_browser_rounded),
                        label: Text(
                          controller.isAuthenticatingGoogle
                              ? 'In attesa di conferma nel browser...'
                              : 'Accedi con Google (Browser / App)',
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // SEZIONE 2: Stato Rete & Indirizzo IP
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.settings_ethernet_rounded,
                      color: Color(0xFF38BDF8),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Indirizzo IP Wi-Fi & Nome Dispositivo',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Indirizzo IPv4 Wi-Fi Attivo'),
                  subtitle: Text(
                    controller.localIp != null
                        ? '${controller.localIp}:${controller.tcpPort}'
                        : 'Nessun IP rilevato',
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
                if (controller.allLocalIps.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Interfacce attive: ${controller.allLocalIps.join(", ")}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _aliasController,
                        decoration: InputDecoration(
                          labelText: 'Nome visibile sulla rete (Alias)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () {
                        controller.updateLocalAlias(_aliasController.text);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Nome dispositivo aggiornato!'),
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
        const SizedBox(height: 16),

        // SEZIONE 3: Tema & Opzioni File
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Tema Scuro (Dark Mode)'),
                subtitle: const Text('Interfaccia scura moderna'),
                value: controller.isDarkMode,
                onChanged: controller.toggleDarkMode,
              ),
              if (controller.isDarkMode)
                SwitchListTile(
                  title: const Text('Modalità Nero Puro AMOLED (S25 Ultra)'),
                  subtitle: const Text(
                    'Sfondo #000000 per display Dynamic AMOLED 2X',
                  ),
                  value: controller.useAmoledBlack,
                  onChanged: controller.toggleAmoledBlack,
                ),
              SwitchListTile(
                title: const Text('Salvataggio automatico in Download'),
                subtitle: const Text(
                  'Salva subito i file ricevuti nella cartella Download del PC o del telefono',
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
