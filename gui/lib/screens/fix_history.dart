/// Historique des modifications écrites depuis le lancement (corrections,
/// éditions, restaurations) et annulation : la dernière modification d'un
/// script s'annule, et la copie `.orig` permet de revenir à l'original.
library;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_state.dart';
import '../help/tips.dart';
import '../strings.dart';

/// Libellé d'une modification : « Correction : SEC003 ×2 », « Modification
/// manuelle », « Restauration de l'original ».
String fixLabel(S s, FixRecord r) => switch (r.kind) {
      FixKind.fix =>
        r.detail.isEmpty ? s.fixKindFix : '${s.fixKindFix} : ${r.detail}',
      FixKind.edit => s.fixKindEdit,
      FixKind.restore => s.fixKindRestore,
    };

String _time(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:'
    '${d.second.toString().padLeft(2, '0')}';

/// Annule la dernière modification de [path] et prévient par un message.
Future<void> undoLastFix(
    BuildContext context, AppState state, String path) async {
  final r = state.lastFixOf(path);
  if (r == null) return;
  final s = S(state.lang);
  final messenger = ScaffoldMessenger.of(context);
  final why = await state.undoFix(r);
  messenger.showSnackBar(SnackBar(
      content: Text(why == null
          ? s.fixUndone(fixLabel(s, r))
          : (why == AppState.staleFix ? s.undoStale : s.error(why)))));
}

/// Ouvre l'historique des modifications.
Future<void> showFixHistory(BuildContext context, AppState state) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => ListenableBuilder(
      listenable: state,
      builder: (ctx, _) => _FixHistory(state: state),
    ),
  );
}

class _FixHistory extends StatelessWidget {
  const _FixHistory({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = S(state.lang);
    final tp = Tips(state.lang);
    final theme = Theme.of(context);
    final rows = state.fixHistory.reversed.toList();
    final active = state.activeTab;
    final canRestore =
        active != null && !state.busy && state.hasOriginalBackup(active);

    return AlertDialog(
      title: Text(s.fixHistoryTitle),
      content: SizedBox(
        width: 560,
        height: 380,
        child: rows.isEmpty
            ? Center(child: Text(s.noFixHistory))
            : ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final undoable = identical(state.lastFixOf(r.path), r);
                  return ListTile(
                    dense: true,
                    leading: Icon(switch (r.kind) {
                      FixKind.fix => Icons.auto_fix_high,
                      FixKind.edit => Icons.edit_outlined,
                      FixKind.restore => Icons.restore,
                    }),
                    title: Text('${p.basename(r.path)} — ${fixLabel(s, r)}'),
                    subtitle: Text('${_time(r.time)} · ${p.dirname(r.path)}',
                        overflow: TextOverflow.ellipsis),
                    trailing: tip(
                      undoable ? tp.undoFix : tp.undoOlderFirst,
                      TextButton.icon(
                        icon: const Icon(Icons.undo, size: 18),
                        label: Text(s.undoFix),
                        onPressed: undoable && !state.busy
                            ? () => undoLastFix(context, state, r.path)
                            : null,
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        if (active != null)
          tip(
            tp.restoreOriginal,
            TextButton.icon(
              icon: const Icon(Icons.restore, size: 18),
              label: Text(s.restoreOriginal),
              onPressed: canRestore
                  ? () => _confirmRestore(context, state, active)
                  : null,
            ),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(s.close)),
      ],
      backgroundColor: theme.colorScheme.surface,
    );
  }

  /// Confirme puis restaure la copie `.orig` du script [path].
  Future<void> _confirmRestore(
      BuildContext context, AppState state, String path) async {
    final s = S(state.lang);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.restoreOriginalTitle(p.basename(path))),
        content: Text(s.restoreOriginalBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.restoreOriginal)),
        ],
      ),
    );
    if (ok != true) return;
    final why = await state.restoreOriginal(path);
    messenger.showSnackBar(SnackBar(
        content: Text(why == null ? s.originalRestored(path) : s.error(why))));
  }
}
