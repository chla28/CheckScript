/// Écran dossier : analyse de tous les scripts d'un dossier, tableau triable
/// des notes, tendance par rapport à la référence.
library;

import 'package:check_script/check_script.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_state.dart';
import '../help/help_content.dart';
import '../help/help_screen.dart';
import '../help/tips.dart';
import '../strings.dart';
import '../widgets/common.dart';
import '../widgets/history_chart.dart';
import 'analysis_screen.dart';

/// Colonne de tri : -2 script, -1 note globale, 0..4 catégorie, 5 problèmes.
typedef SortKey = int;

List<ScriptReport> sortReports(
    List<ScriptReport> reports, SortKey key, bool asc) {
  int cmp(ScriptReport a, ScriptReport b) => switch (key) {
        -2 => a.script.path.compareTo(b.script.path),
        -1 => a.global.compareTo(b.global),
        5 => a.findings.length.compareTo(b.findings.length),
        _ => a.scores[key].score.compareTo(b.scores[key].score),
      };
  final out = [...reports]..sort(cmp);
  return asc ? out : out.reversed.toList();
}

class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key, required this.state, required this.onOpen});
  final AppState state;

  /// Ouvre un script dans l'écran d'analyse.
  final void Function(String path) onOpen;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  SortKey _sort = -1;
  bool _asc = true;

  AppState get state => widget.state;

  @override
  Widget build(BuildContext context) {
    final s = S(state.lang);
    final t = s.m;
    final tp = Tips(state.lang);
    final b = Theme.of(context).brightness;
    final reports = sortReports(state.folderReports, _sort, _asc);

    DataColumn col(String label, SortKey key, {bool numeric = true}) =>
        DataColumn(
          label: Text(label),
          tooltip: tp.folderSort,
          numeric: numeric,
          onSort: (_, __) => setState(() {
            _asc = _sort == key ? !_asc : true;
            _sort = key;
          }),
        );
    final sortIndex =
        switch (_sort) { -2 => 0, -1 => 6, 5 => 7, _ => _sort + 1 };

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              tip(
                tp.openFolder,
                FilledButton.icon(
                  onPressed: state.busy
                      ? null
                      : () async {
                          final dir = await FilePicker.getDirectoryPath(
                              dialogTitle: s.openFolder);
                          if (dir != null) await state.analyzeFolder(dir);
                        },
                  icon: const Icon(Icons.folder_open),
                  label: Text(s.openFolder),
                ),
              ),
              tip(
                tp.reanalyze,
                OutlinedButton.icon(
                  onPressed: state.busy || state.folderPath == null
                      ? null
                      : () => state.analyzeFolder(state.folderPath!),
                  icon: const Icon(Icons.refresh),
                  label: Text(s.reanalyze),
                ),
              ),
              tip(
                tp.export,
                OutlinedButton.icon(
                  onPressed: reports.isEmpty
                      ? null
                      : () => exportReports(context, state, reports),
                  icon: const Icon(Icons.save_alt),
                  label: Text(s.export),
                ),
              ),
              ...baselineActions(context, state,
                  hasReport: reports.isNotEmpty, folder: true),
              HelpButton(HelpTopic.folder, lang: state.lang),
              if (state.folderPath != null)
                Text(state.folderPath!,
                    style: Theme.of(context).textTheme.bodySmall),
            ]),
      ),
      if (state.folderHistory.length >= 2)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                SizedBox(
                  width: 240,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        tip(
                            tp.history,
                            Text(s.history,
                                style: Theme.of(context).textTheme.titleSmall)),
                        const SizedBox(height: 4),
                        Text(s.historyLine(
                            state.folderHistory.length,
                            fmtScore(
                                state.folderHistory.first.average, state.lang),
                            fmtScore(
                                state.folderHistory.last.average, state.lang),
                            fmtDelta(
                                state.folderHistory.last.average,
                                state.folderHistory.first.average,
                                state.lang))),
                      ]),
                ),
                Expanded(
                  child: SizedBox(
                    height: 110,
                    child: HistoryChart(
                        entries: state.folderHistory, lang: state.lang),
                  ),
                ),
              ]),
            ),
          ),
        ),
      const Divider(height: 1),
      Expanded(
        child: reports.isEmpty
            ? Center(
                child:
                    Text(state.folderPath == null ? s.dropHere : s.noScripts))
            : SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    sortColumnIndex: sortIndex,
                    sortAscending: _asc,
                    showCheckboxColumn: false,
                    columns: [
                      col(t.script, -2, numeric: false),
                      for (var i = 0; i < Category.values.length; i++)
                        col(t.category(Category.values[i]), i),
                      col(t.globalScore, -1),
                      col(s.issues, 5),
                      if (state.baseline != null)
                        DataColumn(label: Text(s.trend), tooltip: tp.trend),
                    ],
                    rows: [
                      for (final r in reports)
                        DataRow(
                          onSelectChanged: (_) => widget.onOpen(r.script.path),
                          cells: [
                            DataCell(Tooltip(
                              message: r.script.path,
                              child: Text(state.folderPath == null
                                  ? r.script.path
                                  : p.relative(r.script.path,
                                      from: state.folderPath)),
                            )),
                            for (final sc in r.scores)
                              DataCell(Text(fmtScore(sc.score, state.lang),
                                  style: TextStyle(
                                      color: scoreColor(sc.score, b)))),
                            DataCell(Text(
                                '${fmtScore(r.global, state.lang)} (${r.grade})',
                                style: TextStyle(
                                    color: scoreColor(r.global, b),
                                    fontWeight: FontWeight.w700))),
                            DataCell(Text('${r.findings.length}')),
                            if (state.baseline != null)
                              DataCell(r.comparison == null
                                  ? const Text('—')
                                  : DeltaChip(
                                      r.global,
                                      r.comparison!.previousGlobal,
                                      state.lang)),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
      ),
    ]);
  }
}
