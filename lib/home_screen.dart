import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'mqtt_service.dart';

// Modèle d'un message envoyé
class SentMessage {
  final String topic;
  final String value;
  final DateTime sentAt;
  final bool retain;

  SentMessage({
    required this.topic,
    required this.value,
    required this.sentAt,
    required this.retain,
  });

  String get formattedTime =>
      '${sentAt.hour.toString().padLeft(2, '0')}:'
      '${sentAt.minute.toString().padLeft(2, '0')}:'
      '${sentAt.second.toString().padLeft(2, '0')}.'
      '${sentAt.millisecond.toString().padLeft(3, '0')}';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {

  // Controllers
  final _ipController    = TextEditingController(text: '192.168.1.100');
  final _portController  = TextEditingController(text: '1883');
  final _topicController = TextEditingController(text: 'maison/top');
  final _valueController = TextEditingController(text: 'TOP');

  // MQTT
  final _mqttService = MqttService();
  bool _isConnected  = false;
  bool _isConnecting = false;
  String _statusMessage = 'Non connecté';
  Color _statusColor = Colors.grey;

  // Panels
  bool _connexionExpanded = true;
  bool _topicExpanded     = true;
  bool _retainMessage     = false;

  // Messages envoyés
  bool _messagesExpanded = false;
  final List<SentMessage> _sentMessages = [];
  final ScrollController _scrollController = ScrollController();

  // Animation bouton
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _loadPreferences();

    _ipController.addListener(_savePreferences);
    _portController.addListener(_savePreferences);
    _topicController.addListener(_savePreferences);
    _valueController.addListener(_savePreferences);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  // ── Préférences ──────────────────────────────────────────

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ipController.text    = prefs.getString('ip')    ?? '192.168.1.100';
      _portController.text  = prefs.getString('port')  ?? '1883';
      _topicController.text = prefs.getString('topic') ?? 'maison/top';
      _valueController.text = prefs.getString('value') ?? 'TOP';
      _retainMessage        = prefs.getBool('retain')  ?? false;
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ip',    _ipController.text);
    await prefs.setString('port',  _portController.text);
    await prefs.setString('topic', _topicController.text);
    await prefs.setString('value', _valueController.text);
    await prefs.setBool('retain',  _retainMessage);
  }

  // ── Connexion ─────────────────────────────────────────────

  Future<void> _toggleConnection() async {
    if (_isConnected) {
      _mqttService.disconnect();
      setState(() {
        _isConnected       = false;
        _statusMessage     = 'Déconnecté';
        _statusColor       = Colors.grey;
        _connexionExpanded = true;
      });
      return;
    }

    setState(() {
      _isConnecting  = true;
      _statusMessage = 'Connexion en cours...';
      _statusColor   = Colors.orange;
    });

    await _savePreferences();

    final success = await _mqttService.connect(
      _ipController.text,
      int.tryParse(_portController.text) ?? 1883,
    );

    setState(() {
      _isConnecting      = false;
      _isConnected       = success;
      _connexionExpanded = !success;
      _statusMessage     = success
          ? '✅ Connecté à ${_ipController.text}'
          : '❌ Échec de connexion';
      _statusColor       = success ? Colors.green : Colors.red;
    });
  }

  // ── Envoi message ─────────────────────────────────────────

  Future<void> _sendMessage() async {

    // Retour haptique
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 100, amplitude: 255);
    }

    if (!_isConnected) {
      _showSnackBar('⚠️ Non connecté au broker !', Colors.orange);
      return;
    }

    // Envoi immédiat avant toute animation
    final resolvedValue = _mqttService.resolveValue(_valueController.text);
    _mqttService.sendMessage(
      _topicController.text,
      _valueController.text,
      _retainMessage,
    );

    setState(() {
      _sentMessages.insert(0, SentMessage(
        topic:  _topicController.text,
        value:  resolvedValue,
        sentAt: DateTime.now(),
        retain: _retainMessage,
      ));
    });

    if (!_messagesExpanded) {
      _showSnackBar(
        '📤 "$resolvedValue" envoyé sur "${_topicController.text}"',
        Colors.green,
      );
    }

    // Animation sans bloquer
    _animController.forward().then((_) => _animController.reverse());
  }

  // ── Quitter ───────────────────────────────────────────────

  Future<void> _confirmQuit() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: const Text(
          'Quitter ?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Voulez-vous vraiment quitter l\'application ?',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Quitter',
              style: TextStyle(color: Color(0xFFE94560)),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _mqttService.disconnect();
      SystemNavigator.pop();
    }
  }

  // ── Vider messages ────────────────────────────────────────

  void _clearMessages() {
    setState(() => _sentMessages.clear());
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 14)),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF16213E),
          title: const Text(
            '📡 MQTT Top Button',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(
                Icons.power_settings_new,
                color: Color(0xFFE94560),
              ),
              tooltip: 'Quitter',
              onPressed: _confirmQuit,
            ),
          ],
        ),
        body: Column(
          children: [
            // ── Panels haut ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                children: [
                  _buildConnexionCard(),
                  const SizedBox(height: 12),
                  _buildTopicCard(),
                ],
              ),
            ),

            // ── Zone bouton : prend tout l'espace disponible ──
            Expanded(
              child: GestureDetector(
                onTap: _sendMessage,
                behavior: HitTestBehavior.opaque,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    width: double.infinity,
                    color: Colors.transparent,
                    child: Center(
                      child: _buildSendButton(),
                    ),
                  ),
                ),
              ),
            ),

            // ── Panel Messages : toujours en bas ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: _buildMessagesCard(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Widget : Carte Connexion ──────────────────────────────

  Widget _buildConnexionCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header cliquable
          GestureDetector(
            onTap: () =>
                setState(() => _connexionExpanded = !_connexionExpanded),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.wifi,
                        color: Color(0xFFE94560),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Connexion',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Rond statut connexion
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isConnecting
                              ? Colors.orange
                              : _isConnected
                                  ? Colors.green
                                  : Colors.red,
                          boxShadow: [
                            BoxShadow(
                              color: (_isConnecting
                                      ? Colors.orange
                                      : _isConnected
                                          ? Colors.green
                                          : Colors.red)
                                  .withOpacity(0.6),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Flèche animée
                  AnimatedRotation(
                    turns: _connexionExpanded ? 0 : 0.5,
                    duration: const Duration(milliseconds: 300),
                    child: const Icon(
                      Icons.keyboard_arrow_up,
                      color: Color(0xFFE94560),
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Contenu animé
          AnimatedCrossFade(
            firstChild: _buildConnexionContent(),
            secondChild: const SizedBox.shrink(),
            crossFadeState: _connexionExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  Widget _buildConnexionContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
          const Divider(color: Color(0xFF0F3460), thickness: 1),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _ipController,
            label: 'Adresse IP du Broker',
            icon: Icons.router,
            hint: '192.168.1.100',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _portController,
            label: 'Port',
            icon: Icons.settings_ethernet,
            hint: '1883',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 20),

          // Bouton Connexion
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isConnecting ? null : _toggleConnection,
              icon: _isConnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(_isConnected ? Icons.wifi_off : Icons.wifi),
              label: Text(
                _isConnecting
                    ? 'Connexion...'
                    : _isConnected
                        ? 'Déconnecter'
                        : 'Connecter',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isConnected
                    ? Colors.red.shade700
                    : const Color(0xFF0F3460),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Widget : Carte Topic & Valeur ─────────────────────────

  Widget _buildTopicCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header cliquable
          GestureDetector(
            onTap: () =>
                setState(() => _topicExpanded = !_topicExpanded),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.topic,
                        color: Color(0xFFE94560),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Topic & Valeur',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  // Flèche animée
                  AnimatedRotation(
                    turns: _topicExpanded ? 0 : 0.5,
                    duration: const Duration(milliseconds: 300),
                    child: const Icon(
                      Icons.keyboard_arrow_up,
                      color: Color(0xFFE94560),
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Contenu animé
          AnimatedCrossFade(
            firstChild: _buildTopicContent(),
            secondChild: const SizedBox.shrink(),
            crossFadeState: _topicExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
          const Divider(color: Color(0xFF0F3460), thickness: 1),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _topicController,
            label: 'Topic MQTT',
            icon: Icons.topic,
            hint: 'maison/top',
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _valueController,
            label: 'Valeur envoyée',
            icon: Icons.edit,
            hint: 'TOP ou avec {dt} pour la date',
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Text(
              '💡 {dt} sera remplacé par la date/heure',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Option Retain
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0F3460),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.save,
                      color: Color(0xFFE94560),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Retain',
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: _retainMessage,
                  activeColor: const Color(0xFFE94560),
                  onChanged: (value) {
                    setState(() => _retainMessage = value);
                    _savePreferences();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Widget : Bouton SEND ──────────────────────────────────

  Widget _buildSendButton() {
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: _isConnected
              ? [const Color(0xFFE94560), const Color(0xFF9B1B30)]
              : [Colors.grey.shade700, Colors.grey.shade900],
        ),
        boxShadow: _isConnected
            ? [
                BoxShadow(
                  color: const Color(0xFFE94560).withOpacity(0.5),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ]
            : [],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.touch_app,
            size: 60,
            color: Colors.white.withOpacity(_isConnected ? 1.0 : 0.4),
          ),
          const SizedBox(height: 8),
          Text(
            'SEND',
            style: TextStyle(
              color: Colors.white.withOpacity(_isConnected ? 1.0 : 0.4),
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
            ),
          ),
        ],
      ),
    );
  }

  // ── Widget : Carte Messages envoyés ──────────────────────

  Widget _buildMessagesCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header cliquable
          GestureDetector(
            onTap: () =>
                setState(() => _messagesExpanded = !_messagesExpanded),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.history,
                        color: Color(0xFFE94560),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Messages envoyés',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Badge compteur
                      if (_sentMessages.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE94560),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_sentMessages.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      // Icône poubelle
                      if (_sentMessages.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: const Color(0xFF16213E),
                                title: const Text(
                                  'Vider la liste ?',
                                  style: TextStyle(color: Colors.white),
                                ),
                                content: const Text(
                                  'Tous les messages seront supprimés.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Annuler'),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      _clearMessages();
                                      Navigator.pop(ctx);
                                    },
                                    child: const Text(
                                      'Vider',
                                      style: TextStyle(
                                        color: Color(0xFFE94560),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                          child: const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: Icon(
                              Icons.delete_outline,
                              color: Color(0xFFE94560),
                              size: 24,
                            ),
                          ),
                        ),
                      // Flèche
                      AnimatedRotation(
                        turns: _messagesExpanded ? 0 : 0.5,
                        duration: const Duration(milliseconds: 300),
                        child: const Icon(
                          Icons.keyboard_arrow_up,
                          color: Color(0xFFE94560),
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Contenu animé
          AnimatedCrossFade(
            firstChild: _buildMessagesList(),
            secondChild: const SizedBox.shrink(),
            crossFadeState: _messagesExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_sentMessages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          children: [
            const Divider(color: Color(0xFF0F3460), thickness: 1),
            const SizedBox(height: 20),
            Icon(Icons.inbox, color: Colors.grey.shade600, size: 40),
            const SizedBox(height: 8),
            Text(
              'Aucun message envoyé',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
            const SizedBox(height: 20),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
          const Divider(color: Color(0xFF0F3460), thickness: 1),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _sentMessages.length,
              separatorBuilder: (_, __) => const Divider(
                color: Color(0xFF0F3460),
                thickness: 1,
                height: 1,
              ),
              itemBuilder: (context, index) {
                final msg = _sentMessages[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Heure
                      Text(
                        msg.formattedTime,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Contenu
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg.topic,
                              style: const TextStyle(
                                color: Color(0xFFE94560),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              msg.value,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Badge retain
                      if (msg.retain)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: Colors.orange, width: 1),
                          ),
                          child: const Text(
                            'R',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Widget : TextField stylisé ────────────────────────────

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade400),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade600),
        prefixIcon: Icon(icon, color: const Color(0xFFE94560)),
        filled: true,
        fillColor: const Color(0xFF0F3460),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFFE94560), width: 2),
        ),
      ),
    );
  }

  // ── Dispose ───────────────────────────────────────────────

  @override
  void dispose() {
    _ipController.removeListener(_savePreferences);
    _portController.removeListener(_savePreferences);
    _topicController.removeListener(_savePreferences);
    _valueController.removeListener(_savePreferences);

    _animController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _topicController.dispose();
    _valueController.dispose();
    _scrollController.dispose();
    _mqttService.disconnect();
    super.dispose();
  }
}
