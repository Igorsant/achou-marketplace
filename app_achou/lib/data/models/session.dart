/// Sessão autenticada devolvida por `/v1/auth/login`.
class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.userName,
    required this.role,
    this.sellerId,
  });

  final String accessToken;
  final String refreshToken;
  final String userName;
  final String role;

  /// Só existe para quem tem `role: LOJISTA`.
  final String? sellerId;

  bool get isLojista => role == 'LOJISTA';

  factory Session.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> user =
        json['user'] as Map<String, dynamic>? ?? <String, dynamic>{};

    return Session(
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
      userName: user['name'] as String? ?? '',
      role: user['role'] as String? ?? 'COMPRADOR',
      sellerId: user['sellerId'] as String?,
    );
  }
}
