/// Lecture tolérante des nombres dans le JSON produit par les outils
/// externes : selon la version (et la distribution), un même champ peut
/// arriver en nombre (`3`) ou en chaîne (`"3"`).
library;

/// Valeur entière de [v] (nombre ou chaîne numérique) ; null sinon.
int? jsonInt(Object? v) => switch (v) {
      num n => n.toInt(),
      String s => int.tryParse(s.trim()) ?? double.tryParse(s.trim())?.toInt(),
      _ => null,
    };

/// Valeur réelle de [v] (nombre ou chaîne numérique) ; null sinon.
double? jsonDouble(Object? v) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s.trim()),
      _ => null,
    };
