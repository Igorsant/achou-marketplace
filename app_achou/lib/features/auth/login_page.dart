import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_typography.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../state/session_controller.dart';
import 'auth_field.dart';
import 'sign_up_page.dart';

/// Entrada do lojista. Ocupa a aba "Vender" enquanto não há sessão — a
/// vitrine e a busca continuam abertas, como em qualquer marketplace.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.onEntrou});

  final VoidCallback? onEntrou;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  /// Em debug os campos já vêm preenchidos com o usuário do seed, para não
  /// digitar a cada hot restart. Em release nascem vazios.
  static const String _emailSeed = 'lojista@achou.com';
  static const String _senhaSeed = 'senha123';

  late final TextEditingController _email =
      TextEditingController(text: kDebugMode ? _emailSeed : '');
  late final TextEditingController _senha =
      TextEditingController(text: kDebugMode ? _senhaSeed : '');

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    final SessionController sessao = SessionScope.of(context);
    final bool ok = await sessao.signIn(
      email: _email.text.trim(),
      password: _senha.text,
    );
    if (ok) {
      widget.onEntrou?.call();
    }
  }

  Future<void> _abrirCadastro() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SignUpPage()),
    );
    // Se o cadastro deu certo, a sessão já existe e a aba troca sozinha;
    // isto só avisa o painel para buscar os dados.
    if (mounted && SessionScope.of(context).autenticado) {
      widget.onEntrou?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final SessionController sessao = SessionScope.of(context);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 28),
        children: <Widget>[
          const Text(
            'Achou!',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 28),
          Text('ÁREA DO LOJISTA', style: AppTypography.label),
          const SizedBox(height: 10),
          const Text(
            'Entre para gerenciar seu catálogo e ver os pedidos recebidos.',
            style: AppTypography.body,
          ),
          const SizedBox(height: 32),
          Text('E-MAIL', style: AppTypography.label),
          const SizedBox(height: 8),
          AuthField(
            controller: _email,
            hintText: 'voce@loja.com',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 18),
          Text('SENHA', style: AppTypography.label),
          const SizedBox(height: 8),
          AuthField(
            controller: _senha,
            hintText: '••••••••',
            obscure: true,
            onSubmitted: (_) => _entrar(),
          ),
          if (sessao.erro != null) ...<Widget>[
            const SizedBox(height: 18),
            Text(
              sessao.erro!,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.primary,
              ),
            ),
          ],
          const SizedBox(height: 28),
          GradientButton(
            label: sessao.ocupado ? 'Entrando…' : 'Entrar',
            onPressed: sessao.ocupado ? null : _entrar,
          ),
          const SizedBox(height: 14),
          Center(
            child: TextButton(
              onPressed: sessao.ocupado ? null : _abrirCadastro,
              child: const Text(
                'Ainda não tem loja? Criar conta',
                style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
