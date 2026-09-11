import 'package:flutter/foundation.dart';

/// Endereço da API por plataforma.
///
/// O emulador Android não enxerga `localhost` do host — para ele a máquina é
/// `10.0.2.2`. Simulador iOS, macOS e web usam `localhost` normalmente.
///
/// Dá para sobrescrever sem tocar no código:
/// `flutter run --dart-define=API_BASE_URL=http://192.168.0.10:3001`
class ApiConfig {
  ApiConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// Porta 3001 porque é o que o docker-compose expõe no host.
  static const String _porta = '3001';

  static String get baseUrl {
    if (_override.isNotEmpty) {
      return _override;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:$_porta';
    }
    return 'http://localhost:$_porta';
  }
}
