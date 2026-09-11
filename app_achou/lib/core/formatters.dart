/// Formata centavos no padrão brasileiro: 269900 -> R$ 2.699,00.
///
/// Dinheiro trafega e é somado sempre como `int` em centavos, igual ao
/// backend. A divisão por 100 acontece só aqui, na exibição.
String formatBrl(int cents) {
  final bool negativo = cents < 0;
  final int absoluto = cents.abs();
  final String reais = (absoluto ~/ 100).toString();
  final String centavos = (absoluto % 100).toString().padLeft(2, '0');

  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < reais.length; i++) {
    final bool precisaSeparador = i > 0 && (reais.length - i) % 3 == 0;
    if (precisaSeparador) {
      buffer.write('.');
    }
    buffer.write(reais[i]);
  }

  return 'R\$ ${negativo ? '-' : ''}$buffer,$centavos';
}
