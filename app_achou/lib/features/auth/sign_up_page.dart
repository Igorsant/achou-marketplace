import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_typography.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../state/session_controller.dart';
import 'auth_field.dart';

/// Criar conta de lojista (`POST /v1/auth/register`).
///
/// A API já devolve os tokens no cadastro, então quem se cadastra entra
/// direto no painel — sem passar de novo pela tela de login.
class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final TextEditingController _nome = TextEditingController();
  final TextEditingController _loja = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _senha = TextEditingController();

  String? _erroLocal;

  @override
  void dispose() {
    _nome.dispose();
    _loja.dispose();
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _criar() async {
    final String nome = _nome.text.trim();
    final String loja = _loja.text.trim();
    final String email = _email.text.trim();
    final String senha = _senha.text;

    // Mesmas regras do RegisterDto: name >= 2, storeName >= 2, password >= 8.
    final String? problema = _validar(nome, loja, email, senha);
    if (problema != null) {
      setState(() => _erroLocal = problema);
      return;
    }

    setState(() => _erroLocal = null);

    final SessionController sessao = SessionScope.of(context);
    final bool ok = await sessao.signUp(
      name: nome,
      email: email,
      password: senha,
      storeName: loja,
    );

    if (ok && mounted) {
      Navigator.of(context).pop();
    }
  }

  static String? _validar(
    String nome,
    String loja,
    String email,
    String senha,
  ) {
    if (nome.length < 2) {
      return 'Informe seu nome.';
    }
    if (loja.length < 2) {
      return 'Informe o nome da loja — é ele que aparece na vitrine.';
    }
    if (!email.contains('@') || !email.contains('.')) {
      return 'Informe um e-mail válido.';
    }
    if (senha.length < 8) {
      return 'A senha precisa de ao menos 8 caracteres.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final SessionController sessao = SessionScope.of(context);
    final String? erro = _erroLocal ?? sessao.erro;

    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        children: <Widget>[
          Text('SUA LOJA NO ACHOU!', style: AppTypography.label),
          const SizedBox(height: 10),
          const Text(
            'A conta é de lojista: dá acesso ao painel, ao catálogo e aos '
            'pedidos recebidos.',
            style: AppTypography.body,
          ),
          const SizedBox(height: 30),
          Text('SEU NOME', style: AppTypography.label),
          const SizedBox(height: 8),
          AuthField(controller: _nome, hintText: 'Como devemos te chamar'),
          const SizedBox(height: 18),
          Text('NOME DA LOJA', style: AppTypography.label),
          const SizedBox(height: 8),
          AuthField(controller: _loja, hintText: 'Aparece para o comprador'),
          const SizedBox(height: 18),
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
            hintText: 'ao menos 8 caracteres',
            obscure: true,
            onSubmitted: (_) => _criar(),
          ),
          if (erro != null) ...<Widget>[
            const SizedBox(height: 18),
            Text(
              erro,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.primary,
              ),
            ),
          ],
          const SizedBox(height: 28),
          GradientButton(
            label: sessao.ocupado ? 'Criando…' : 'Criar conta e entrar',
            onPressed: sessao.ocupado ? null : _criar,
          ),
        ],
      ),
    );
  }
}
