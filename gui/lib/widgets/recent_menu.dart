/// Menu des scripts et dossiers analysés récemment.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_state.dart';
import '../help/tips.dart';
import '../strings.dart';

class RecentMenu extends StatelessWidget {
  const RecentMenu({super.key, required this.state, required this.onOpen});

  final AppState state;

  /// Ouvre une entrée (dossier : vue Dossier ; sinon : Analyse).
  final void Function(String path, bool directory) onOpen;

  /// Valeur du menu qui vide la liste.
  static const _clear = '\u0000clear';

  @override
  Widget build(BuildContext context) {
    final s = S(state.lang);
    final recent = state.settings.recent;
    return PopupMenuButton<String>(
      tooltip: '${s.recent} — ${Tips(state.lang).recentMenu}',
      enabled: !state.busy,
      icon: const Icon(Icons.history),
      onSelected: (v) {
        if (v == _clear) {
          state.clearRecent();
        } else {
          onOpen(v, FileSystemEntity.isDirectorySync(v));
        }
      },
      itemBuilder: (_) => [
        if (recent.isEmpty)
          PopupMenuItem<String>(enabled: false, child: Text(s.noRecent)),
        for (final r in recent)
          PopupMenuItem<String>(
            value: r,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(FileSystemEntity.isDirectorySync(r)
                  ? Icons.folder_outlined
                  : Icons.description_outlined),
              title: Text(p.basename(r)),
              subtitle: Text(p.dirname(r),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        if (recent.isNotEmpty) const PopupMenuDivider(),
        if (recent.isNotEmpty)
          PopupMenuItem<String>(value: _clear, child: Text(s.clearRecent)),
      ],
    );
  }
}
