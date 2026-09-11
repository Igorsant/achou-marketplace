import 'package:flutter/material.dart';

import '../../core/app_typography.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(title, style: AppTypography.sectionTitle)),
        ?trailing,
      ],
    );
  }
}
