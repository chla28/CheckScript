/// Ajoute les anomalies aux rapports d'une analyse (un script ou un parc).
/// Elles sont informatives : notes, problèmes et seuils sont inchangés.
library;

import '../baseline.dart';
import '../i18n.dart';
import '../model/report.dart';
import 'anomaly.dart';
import 'detectors.dart';
import 'local_model.dart';
import 'signals.dart';

/// [baseline] active les dérives, [model] les suggestions du modèle local
/// (un script après l'autre, [onModel] avant chacun). Un échec du modèle est
/// noté dans le rapport : l'absence de suggestion ne doit pas passer pour un
/// script sain.
Future<List<ScriptReport>> annotateAnomalies(List<ScriptReport> reports,
    {required Lang lang,
    Baseline? baseline,
    LocalModel? model,
    void Function(String path)? onModel}) async {
  final signals = [for (final r in reports) extractSignals(r.script)];
  final profiles = [
    for (var i = 0; i < reports.length; i++)
      profileOf(reports[i].script, signals[i])
  ];
  final outliers = detectOutliers(profiles, lang);
  String t(String fr, String en) => lang == Lang.fr ? fr : en;
  final out = <ScriptReport>[];
  for (var i = 0; i < reports.length; i++) {
    final r = reports[i];
    final previous = baseline?.entryFor(r.script.path);
    final found = <Anomaly>[
      ...detectBehaviours(r.script, lang, signals[i]),
      ...outliers[i],
      if (previous != null)
        ...detectDrift(
            current: profiles[i],
            before: previous.profile,
            score: r.global,
            previousScore: previous.global,
            lang: lang),
    ];
    String? note;
    if (model != null) {
      onModel?.call(r.script.path);
      try {
        final review = await model.review(r.script, lang);
        found.addAll(review.anomalies);
        note = t(
            '${model.model} : ${review.anomalies.length} suggestion(s) à vérifier${review.truncated ? ' (script tronqué : fin non relue)' : ''}',
            '${model.model}: ${review.anomalies.length} suggestion(s) to check${review.truncated ? ' (script truncated: end not reviewed)' : ''}');
      } on ModelException catch (e) {
        note = t('${model.model} : relecture impossible — ${e.message}',
            '${model.model}: review failed — ${e.message}');
      }
    }
    final kept = applySuppressions(r.script, found)..sortByLevel();
    out.add(r.withAnomalies(kept, profiles[i], note));
  }
  return out;
}

extension on List<Anomaly> {
  /// Constats déterministes d'abord, par niveau ; le modèle à la fin.
  void sortByLevel() => sort((a, b) {
        final m = (a.kind == AnomalyKind.model ? 1 : 0) -
            (b.kind == AnomalyKind.model ? 1 : 0);
        if (m != 0) return m;
        final l = a.level.index.compareTo(b.level.index);
        return l != 0 ? l : a.id.compareTo(b.id);
      });
}
