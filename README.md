# CheckScript — `check-script`

Évalue des scripts shell et produit un classement sur cinq catégories notées
sur 10 — **Sécurité, Robustesse, Maintenabilité, Portabilité, Performance** —
avec, pour chacune, le nombre de problèmes par sévérité (Critical / High /
Medium / Low) et leur total. Sortie dans le terminal et/ou en Markdown,
AsciiDoc ou JSON, en français ou en anglais.

`check-script` exploite **ShellCheck, shfmt, bashate, checkbashisms** et
`bash -n` lorsqu'ils sont installés, et les complète par une cinquantaine de
règles intégrées (secrets en dur, `curl | sh`, permissions, structure…) qui
fonctionnent toujours.

```bash
check-script deploy.sh                         # rapport terminal
check-script deploy.sh -o rapport.md -o rapport.adoc
check-script --lang en scripts/                # un dossier, en anglais
check-script --fail-under 7 -q scripts/        # intégration continue
check-script --list-tools                      # outils détectés
```

```
Catégorie        Note /10             Critical     High   Medium      Low   Total
Sécurité           0,0 ░░░░░░░░░░            3        3        3        0       9
Robustesse         1,8 ██░░░░░░░░            0        1        8        2      11
Maintenabilité     8,8 █████████░            0        0        0        5       5
Portabilité       10,0 ██████████            0        0        0        0       0
Performance        9,0 █████████░            0        0        0        4       4

Note globale : 2,5/10 (E)
```

## Documentation

- [Guide utilisateur](doc/user.adoc) — installation, options, lecture du
  rapport, calcul des notes, règles, configuration.
- [Guide développeur](doc/developer.adoc) — architecture, analyseurs,
  ajout de règles, tests, packaging, préparation de la version Flutter.
- [Exemple de configuration](doc/checkscript.example.yaml).

## Développement

```bash
dart pub get
dart run bin/check_script.dart test/fixtures/bad.sh
dart analyze --fatal-infos
dart test
./scripts/build-dist.sh            # → dist/check_script-VERSION-linux-ARCH.tar.gz
./scripts/build-dist.sh --install  # + installation dans ~/.local
```

Plateforme cible : Linux. Une interface Flutter est prévue dans un second
temps ; elle réutilisera la bibliothèque `lib/` (voir le guide développeur).
