import 'package:flutter/material.dart';

import '../../../core/app_colors.dart';
import '../../../core/app_typography.dart';
import '../../../data/models/product.dart';
import '../../../data/remote/api_exception.dart';
import '../../../data/repositories/seller_repository.dart';
import '../../../shared/widgets/gradient_button.dart';

/// Cadastro e edição de produto — o mesmo formulário, porque os campos são os
/// mesmos. Com [initial] preenchido, vira edição (`PATCH`); sem, cadastro
/// (`POST`).
class NewProductForm extends StatefulWidget {
  const NewProductForm({
    super.key,
    required this.onSubmit,
    this.initial,
    this.submitLabel = 'Publicar produto',
  });

  final Future<void> Function(NewProductDraft draft) onSubmit;
  final Product? initial;
  final String submitLabel;

  @override
  State<NewProductForm> createState() => _NewProductFormState();
}

class _NewProductFormState extends State<NewProductForm> {
  late final TextEditingController _titulo =
      TextEditingController(text: widget.initial?.title ?? '');
  late final TextEditingController _preco = TextEditingController(
    text: widget.initial == null ? '' : _emReais(widget.initial!.priceCents),
  );
  late final TextEditingController _estoque = TextEditingController(
    text: '${widget.initial?.stock ?? 1}',
  );
  late final TextEditingController _descricao =
      TextEditingController(text: widget.initial?.description ?? '');
  late final TextEditingController _imagem =
      TextEditingController(text: widget.initial?.imageUrl ?? '');

  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _titulo.dispose();
    _preco.dispose();
    _estoque.dispose();
    _descricao.dispose();
    _imagem.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final String titulo = _titulo.text.trim();
    final int? centavos = _emCentavos(_preco.text);
    final int? estoque = int.tryParse(_estoque.text.trim());

    // A API valida de novo (title >= 3, priceCents >= 1); validar aqui evita
    // ida e volta só para descobrir que o campo estava vazio.
    final String? problema =
        _validar(titulo, centavos, estoque, _imagem.text.trim());
    if (problema != null) {
      setState(() => _erro = problema);
      return;
    }

    setState(() {
      _enviando = true;
      _erro = null;
    });

    try {
      await widget.onSubmit(
        NewProductDraft(
          title: titulo,
          priceCents: centavos!,
          stock: estoque!,
          description: _descricao.text,
          imageUrl: _imagem.text,
        ),
      );
      if (widget.initial == null) {
        _limpar();
      }
    } on ApiException catch (erro) {
      if (mounted) {
        setState(() => _erro = erro.message);
      }
    } finally {
      if (mounted) {
        setState(() => _enviando = false);
      }
    }
  }

  void _limpar() {
    _titulo.clear();
    _preco.clear();
    _descricao.clear();
    _imagem.clear();
    _estoque.text = '1';
  }

  static String? _validar(
    String titulo,
    int? centavos,
    int? estoque,
    String imagem,
  ) {
    if (titulo.length < 3) {
      return 'O nome precisa de ao menos 3 caracteres.';
    }
    if (centavos == null || centavos < 1) {
      return 'Informe um preço válido, como 649,90.';
    }
    if (estoque == null || estoque < 0) {
      return 'Informe o estoque em número inteiro.';
    }
    if (imagem.isNotEmpty && !pareceUrl(imagem)) {
      return 'O link da imagem precisa começar com http:// ou https://.';
    }
    return null;
  }

  /// A API recusa o cadastro inteiro quando a URL é inválida; barrar aqui
  /// evita perder o formulário preenchido por causa de um link torto.
  static bool pareceUrl(String valor) {
    final Uri? uri = Uri.tryParse(valor);
    return uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static String _emReais(int centavos) =>
      (centavos / 100).toStringAsFixed(2).replaceAll('.', ',');

  /// "2.699,00" e "649.90" viram centavos. A vírgula manda: se ela existe, o
  /// ponto é separador de milhar.
  static int? _emCentavos(String texto) {
    String limpo = texto.trim().replaceAll(RegExp(r'[^0-9,.]'), '');
    if (limpo.isEmpty) {
      return null;
    }
    if (limpo.contains(',')) {
      limpo = limpo.replaceAll('.', '').replaceAll(',', '.');
    }
    final double? valor = double.tryParse(limpo);
    if (valor == null) {
      return null;
    }
    return (valor * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('NOME DO PRODUTO', style: AppTypography.label),
        const SizedBox(height: 8),
        _Field(controller: _titulo, hintText: 'Ex.: Fone Bluetooth ANC'),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('PREÇO', style: AppTypography.label),
                  const SizedBox(height: 8),
                  _Field(
                    controller: _preco,
                    hintText: '649,90',
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('ESTOQUE', style: AppTypography.label),
                  const SizedBox(height: 8),
                  _Field(
                    controller: _estoque,
                    hintText: '1',
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text('DESCRIÇÃO (OPCIONAL)', style: AppTypography.label),
        const SizedBox(height: 8),
        _Field(
          controller: _descricao,
          hintText: 'O que o comprador precisa saber',
          maxLines: 3,
        ),
        const SizedBox(height: 18),
        Text('LINK DA IMAGEM (OPCIONAL)', style: AppTypography.label),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _Field(
                controller: _imagem,
                hintText: 'https://...',
                keyboardType: TextInputType.url,
                // Redesenha para a prévia acompanhar o que está sendo colado.
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            _Previa(url: _imagem.text.trim()),
          ],
        ),
        if (_erro != null) ...<Widget>[
          const SizedBox(height: 16),
          Text(
            _erro!,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.primary,
            ),
          ),
        ],
        const SizedBox(height: 26),
        GradientButton(
          label: _enviando ? 'Salvando…' : widget.submitLabel,
          onPressed: _enviando ? null : _enviar,
        ),
        const SizedBox(height: 10),
        const Text(
          'A categoria não é enviada: a API exige o UUID da categoria e não '
          'existe rota que liste as categorias.',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Mostra o que o link devolve, do tamanho que a miniatura do catálogo terá.
/// É a forma mais barata de descobrir que o link está quebrado antes de
/// publicar — e depois de publicar o comprador veria o mesmo vazio.
class _Previa extends StatelessWidget {
  const _Previa({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: _NewProductFormState.pareceUrl(url)
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image_outlined,
                size: 18,
                color: AppColors.textSecondary,
              ),
            )
          : const Icon(
              Icons.image_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.maxLines = 1,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle:
            const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}
