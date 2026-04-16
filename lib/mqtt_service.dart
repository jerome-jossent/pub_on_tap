import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  MqttServerClient? _client;
  bool _isConnected = false;

  bool get isConnected => _isConnected;

  Future<bool> connect(String host, int port) async {
    _client = MqttServerClient(host, 'flutter_top_button');
    _client!.port = port;
    _client!.keepAlivePeriod = 30;
    _client!.logging(on: false);

    _client!.onConnected = () {
      _isConnected = true;
      print('✅ Connecté au broker MQTT');
    };

    _client!.onDisconnected = () {
      _isConnected = false;
      print('❌ Déconnecté du broker MQTT');
    };

    final connMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_top_button')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    _client!.connectionMessage = connMessage;

    try {
      await _client!.connect();
      return _isConnected;
    } catch (e) {
      print('Erreur connexion: $e');
      _client!.disconnect();
      return false;
    }
  }

  void sendMessage(String topic, String value, bool retain) {
    if (!_isConnected || _client == null) return;

    // Remplace {dt} par la date/heure actuelle
    final now = DateTime.now();
    final formattedDate =
        '${now.year.toString().padLeft(4, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';

    final finalValue = value.replaceAll('{dt}', formattedDate);

    final builder = MqttClientPayloadBuilder();
    builder.addString(finalValue);

    _client!.publishMessage(
      topic,
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: retain,
    );

    print('📤 Message "$finalValue" envoyé sur $topic (retain: $retain)');
  }

  String resolveValue(String value) {
    final now = DateTime.now();
    final formattedDate =
        '${now.year.toString().padLeft(4, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    return value.replaceAll('{dt}', formattedDate);
  }

  void disconnect() {
    _client?.disconnect();
    _isConnected = false;
  }
}
