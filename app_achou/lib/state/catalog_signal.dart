import 'package:flutter/foundation.dart';

/// Avisa que o catálogo mudou.
///
/// As abas vivem todas montadas dentro de um `IndexedStack`: a vitrine busca
/// os produtos uma vez e, sem este aviso, continuaria mostrando a lista de
/// quando foi aberta — mesmo depois do lojista cadastrar algo na aba ao lado.
class CatalogSignal extends ChangeNotifier {
  void mudou() => notifyListeners();
}
