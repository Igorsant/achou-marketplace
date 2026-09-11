import 'dart:math';

/// Chave de idempotência para o checkout.
///
/// O contrato da API exige `Idempotency-Key` no `POST /v1/orders`: se a rede
/// cair depois do servidor criar o pedido, o app repete a requisição com a
/// mesma chave e recebe o mesmo pedido de volta, em vez de cobrar duas vezes.
String gerarIdempotencyKey() {
  final Random random = Random.secure();
  final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes
      .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}
