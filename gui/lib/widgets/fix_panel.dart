/// Code à écrire pour résoudre un problème : correction concrète des lignes
/// concernées (avant / après) quand elle est sûre, sinon exemple générique
/// de la règle (à éviter / à écrire).
library;

import 'package:check_script/check_script.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../strings.dart';

class FixPanel extends StatelessWidget {
  const FixPanel({
    super.key,
    required this.finding,
    required this.lines,
    required this.lang,
    this.onApply,
  });

  final Finding finding;

  /// Lignes du script analysé (aperçu de la correction concrète).
  final List<String> lines;
  final Lang lang;

  /// Applique la correction concrète au fichier ; null : bouton absent.
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final s = S(lang);
    final t = s.m;
    final preview = fixPreview(finding, lines);
    final example = preview == null ? exampleFor(finding.ruleId) : null;

    final String toCopy;
    final List<Widget> blocks;
    if (preview != null) {
      final (first, before, after) = preview;
      toCopy = after;
      blocks = [
        _Label(t.suggestedFix, bold: true),
        _Label(s.before(first)),
        CodeBlock(before, good: false),
        _Label(s.after),
        CodeBlock(after, good: true),
      ];
    } else if (example != null) {
      toCopy = example.goodOf(lang);
      blocks = [
        _Label(t.fixExample, bold: true),
        _Label(t.avoid),
        CodeBlock(example.badOf(lang), good: false),
        _Label(t.writeInstead),
        CodeBlock(toCopy, good: true),
      ];
    } else {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(s.noFixAvailable,
            style: Theme.of(context).textTheme.bodySmall),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ...blocks,
        const SizedBox(height: 4),
        Wrap(spacing: 8, children: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: Text(s.copy),
            onPressed: () async {
              final messenger = ScaffoldMessenger.maybeOf(context);
              await Clipboard.setData(ClipboardData(text: toCopy));
              messenger?.showSnackBar(SnackBar(content: Text(s.copied)));
            },
          ),
          if (preview != null && onApply != null)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.auto_fix_high, size: 16),
              label: Text(s.applyThisFix),
              onPressed: onApply,
            ),
        ]),
      ]),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.bold = false});
  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Text(text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
      );
}

/// Bloc de code monospace sélectionnable, teinté en rouge (à éviter) ou en
/// vert (à écrire), défilant horizontalement.
class CodeBlock extends StatelessWidget {
  const CodeBlock(this.code, {super.key, required this.good});
  final String code;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final tint = good ? Colors.green : Colors.red;
    return Container(
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        border: Border(left: BorderSide(color: tint, width: 3)),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(code,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
      ),
    );
  }
}
