/// Onglet « Anomalies » : constats informatifs du script affiché, et
/// relecture à la demande par un modèle, local ou distant.
library;

import 'package:check_script/check_script.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../help/tips.dart';
import '../strings.dart';
import 'common.dart';

Color _levelColor(AnomalyLevel l, Brightness b) => severityColor(
    switch (l) {
      AnomalyLevel.high => Severity.high,
      AnomalyLevel.medium => Severity.medium,
      AnomalyLevel.low => Severity.low,
    },
    b);

class AnomaliesPanel extends StatelessWidget {
  const AnomaliesPanel(
      {super.key,
      required this.state,
      required this.report,
      required this.onSelectLine});

  final AppState state;
  final ScriptReport report;
  final void Function(int line) onSelectLine;

  /// Chaque envoi hors du poste est confirmé, avec sa destination.
  Future<void> _review(BuildContext context) async {
    final provider = state.settings.aiProvider;
    if (!provider.remote) return state.reviewWithModel();
    final s = S(state.lang);
    final path = report.script.path;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.aiSendTitle(provider.label)),
        content: Text(s.aiSendBody(path, report.script.totalLines,
            provider.host, state.settings.reviewModel)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.aiSendCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(s.aiSend)),
        ],
      ),
    );
    // Le script affiché a pu changer pendant la question.
    if (ok == true && state.current?.script.path == path) {
      await state.reviewWithModel(confirmedRemote: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S(state.lang);
    final tp = Tips(state.lang);
    final theme = Theme.of(context);
    final found = report.anomalies;
    if (found == null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(s.anomaliesOff, textAlign: TextAlign.center)));
    }
    final reviewing = state.reviewing == report.script.path;
    final provider = state.settings.aiProvider;
    final block = state.reviewBlock;
    return ListView(children: [
      Text(s.m.anomaliesIntro, style: theme.textTheme.bodySmall),
      const SizedBox(height: 8),
      Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            tip(
                provider.remote
                    ? tp.aiReviewRemote(provider.host)
                    : tp.aiReview,
                OutlinedButton.icon(
                  onPressed:
                      state.reviewing != null || state.busy || block != null
                          ? null
                          : () => _review(context),
                  icon: reviewing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.psychology_outlined),
                  label: Text(reviewing
                      ? s.aiReviewing
                      : provider.remote
                          ? s.aiReviewWith(provider.label)
                          : s.aiReview),
                )),
            Text(state.settings.reviewModel, style: theme.textTheme.bodySmall),
          ]),
      if (block != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
              block == AiBlock.notAllowed
                  ? s.aiNotAllowed
                  : s.aiMissingKey(provider.keyVariable),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error)),
        ),
      if (report.aiNote != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(report.aiNote!, style: theme.textTheme.bodySmall),
        ),
      const SizedBox(height: 8),
      if (found.isEmpty) Text(s.m.noAnomaly),
      for (final a in found)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  '${a.id} · ${s.m.anomalyLevel(a.level)} · ${s.m.anomalyKind(a.kind)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: _levelColor(a.level, theme.brightness))),
              const SizedBox(height: 4),
              Text(a.title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              SelectableText(a.detail),
              if (a.lines.isNotEmpty)
                Wrap(spacing: 4, children: [
                  for (final l in a.lines)
                    TextButton(
                        onPressed: () => onSelectLine(l), child: Text('L$l')),
                ]),
            ]),
          ),
        ),
    ]);
  }
}
