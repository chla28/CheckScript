/// Réglages : langue, thème, profil, contextes, outils, configuration YAML.
library;

import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../code_style.dart';
import '../editor.dart';
import '../help/help_content.dart';
import '../help/help_screen.dart';
import '../help/tips.dart';
import '../strings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// Aperçu de la police du code : caractères faciles à confondre.
const _preview = r'for f in "$@"; do [ -e "$f" ] || exit 1; done  # 0O 1lI {}';

/// Choix de la police du code : police intégrée, ou une police à chasse
/// fixe installée (liste de fontconfig, ou nom saisi puis Entrée).
class _CodeFontField extends StatefulWidget {
  const _CodeFontField({required this.state});
  final AppState state;

  @override
  State<_CodeFontField> createState() => _CodeFontFieldState();
}

class _CodeFontFieldState extends State<_CodeFontField> {
  List<String> _installed = const [];

  @override
  void initState() {
    super.initState();
    installedMonospaceFonts().then((f) {
      if (mounted) setState(() => _installed = f);
    });
  }

  void _set(String? family) {
    final st = widget.state;
    final f = family?.trim();
    st.updateSettings(st.settings.copyWith(
        codeFont: () =>
            f == null || f.isEmpty || f == defaultCodeFont ? null : f));
  }

  @override
  Widget build(BuildContext context) {
    final s = S(widget.state.lang);
    final current = widget.state.settings.codeFont;
    return Row(children: [
      Expanded(
        child: Autocomplete<String>(
          key: ValueKey(current),
          initialValue: TextEditingValue(text: current ?? ''),
          optionsBuilder: (v) {
            final q = v.text.trim().toLowerCase();
            return [
              for (final f in _installed)
                if (q.isEmpty || f.toLowerCase().contains(q)) f
            ];
          },
          onSelected: _set,
          fieldViewBuilder: (context, controller, focus, submit) => TextField(
            controller: controller,
            focusNode: focus,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: s.embeddedFont,
              helperText: s.otherFont,
            ),
            // Nom saisi tel quel (une police de la liste se choisit en
            // cliquant dessus).
            onSubmitted: _set,
          ),
        ),
      ),
      const SizedBox(width: 8),
      IconButton(
        tooltip: s.embeddedFont,
        onPressed: current == null ? null : () => _set(null),
        icon: const Icon(Icons.restart_alt),
      ),
    ]);
  }
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    if (state.toolVersions.isEmpty) state.detectTools();
  }

  @override
  Widget build(BuildContext context) {
    final s = S(state.lang);
    final g = state.settings;
    final theme = Theme.of(context);
    final tp = Tips(state.lang);
    Widget section(String title, HelpTopic help, [String? hint]) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 6),
          child: Row(children: [
            Flexible(
              child: tip(
                  hint,
                  Text(title,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium)),
            ),
            HelpButton(help, lang: state.lang),
          ]),
        );

    return ListView(padding: const EdgeInsets.all(16), children: [
      section(s.language, HelpTopic.settings, tp.language),
      SegmentedButton<Lang?>(
        segments: [
          ButtonSegment(value: null, label: Text(s.systemDefault)),
          const ButtonSegment(value: Lang.fr, label: Text('Français')),
          const ButtonSegment(value: Lang.en, label: Text('English')),
        ],
        selected: {g.lang},
        onSelectionChanged: (v) =>
            state.updateSettings(g.copyWith(lang: () => v.first)),
      ),
      section(s.theme, HelpTopic.settings, tp.theme),
      SegmentedButton<ThemeMode>(
        segments: [
          ButtonSegment(value: ThemeMode.system, label: Text(s.systemDefault)),
          ButtonSegment(value: ThemeMode.light, label: Text(s.light)),
          ButtonSegment(value: ThemeMode.dark, label: Text(s.dark)),
        ],
        selected: {g.theme},
        onSelectionChanged: (v) =>
            state.updateSettings(g.copyWith(theme: v.first)),
      ),
      section(s.codeFont, HelpTopic.settings, tp.codeFontField),
      _CodeFontField(state: state),
      const SizedBox(height: 8),
      Row(children: [
        tip(tp.codeFontSize, Text(s.codeFontSize)),
        Expanded(
          child: Slider(
            value: g.codeFontSize,
            min: minCodeFontSize,
            max: maxCodeFontSize,
            divisions: (maxCodeFontSize - minCodeFontSize).round(),
            label: '${g.codeFontSize.round()} pt',
            onChanged: (v) => state.updateSettings(g.copyWith(codeFontSize: v)),
          ),
        ),
        Text('${g.codeFontSize.round()} pt'),
      ]),
      Container(
        padding: const EdgeInsets.all(8),
        color: theme.colorScheme.surfaceContainerLowest,
        child: Text.rich(
          highlightedLine(
              _preview,
              highlightLines([_preview], HighlightLanguage.shell).first,
              codeTextStyle(g.codeFont, g.codeFontSize,
                  color: theme.colorScheme.onSurface),
              theme.brightness),
          softWrap: false,
          overflow: TextOverflow.fade,
        ),
      ),
      section(s.profile, HelpTopic.profiles, tp.profile),
      SegmentedButton<Profile>(
        segments: [
          ButtonSegment(
              value: Profile.strict,
              label: Text(s.profileStrict),
              tooltip: tp.profileStrict),
          ButtonSegment(
              value: Profile.standard,
              label: Text(s.profileStandard),
              tooltip: tp.profileStandard),
          ButtonSegment(
              value: Profile.legacy,
              label: Text(s.profileLegacy),
              tooltip: tp.profileLegacy),
        ],
        selected: {g.profile},
        onSelectionChanged: (v) =>
            state.updateSettings(g.copyWith(profile: v.first)),
      ),
      section(s.contexts, HelpTopic.profiles, tp.contexts),
      Wrap(spacing: 8, children: [
        for (final c in [
          ExecContext.root,
          ExecContext.cron,
          ExecContext.systemd
        ])
          tip(
            tp.context(c),
            FilterChip(
              label: Text(c.name),
              selected: g.contexts.contains(c),
              onSelected: (v) => state.updateSettings(g.copyWith(
                  contexts:
                      v ? {...g.contexts, c} : ({...g.contexts}..remove(c)))),
            ),
          ),
      ]),
      section(s.tools, HelpTopic.tools),
      for (final (title, tools) in [
        (s.shellTools, ['shellcheck', 'shfmt', 'bashate', 'checkbashisms']),
        (
          s.pythonTools,
          [
            'ruff', 'bandit', 'semgrep', 'mypy', 'radon', 'vermin', //
            'pydeps', 'pip-audit', 'pylint', 'pyright',
          ]
        ),
        (s.commonTools, ['gitleaks', 'trufflehog', 'syntax']),
        (s.hostTools, ['hadolint', 'actionlint', 'zizmor']),
      ]) ...[
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 16),
          child: Text(title, style: theme.textTheme.labelLarge),
        ),
        for (final tool in tools)
          tip(
              tp.tool(tool),
              SwitchListTile(
                dense: true,
                title: Text(tool),
                subtitle: Text(switch (tool) {
                  'syntax' => 'bash -n / sh -n / python3 compile()',
                  'semgrep' => '${_version(s, tool)} · ${s.semgrepNetwork}',
                  'pylint' || 'pyright' => '${_version(s, tool)} · ${s.optIn}',
                  _ => _version(s, tool),
                }),
                value: g.toolEnabled(tool),
                onChanged: (v) => state.updateSettings(g.withTool(tool, v)),
              )),
      ],
      tip(
        tp.ruffProjectConfig,
        SwitchListTile(
          dense: true,
          title: Text(s.ruffProjectConfig),
          value: g.ruffProjectConfig,
          onChanged: (v) =>
              state.updateSettings(g.copyWith(ruffProjectConfig: v)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          Expanded(child: tip(tp.pythonTarget, Text(s.pythonTarget))),
          DropdownButton<String?>(
            value: g.pythonTarget,
            items: [
              DropdownMenuItem(
                  value: null,
                  child: Text(
                      '${s.systemDefault} (${CheckConfig.defaultPythonTarget})')),
              for (var m = 6; m <= 14; m++)
                DropdownMenuItem(value: '3.$m', child: Text('3.$m')),
            ],
            onChanged: (v) =>
                state.updateSettings(g.copyWith(pythonTarget: () => v)),
          ),
        ]),
      ),
      tip(
        tp.useCache,
        SwitchListTile(
          title: Text(s.useCacheSetting),
          value: g.useCache,
          onChanged: (v) => state.updateSettings(g.copyWith(useCache: v)),
        ),
      ),
      tip(
        tp.watchFile,
        SwitchListTile(
          title: Text(s.watchFileSetting),
          value: g.watchFile,
          onChanged: (v) => state.updateSettings(g.copyWith(watchFile: v)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: tip(
          tp.editorCommand,
          TextFormField(
            initialValue: g.editorCommand,
            decoration: InputDecoration(
              labelText: s.editorCommand,
              helperText: s.editorHint(detectEditor()),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => state.updateSettings(g.copyWith(
                editorCommand: () => v.trim().isEmpty ? null : v.trim())),
          ),
        ),
      ),
      tip(
        tp.followSource,
        SwitchListTile(
          title: Text(s.followSource),
          value: g.followSource,
          onChanged: (v) => state.updateSettings(g.copyWith(followSource: v)),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: tip(
          tp.detect,
          TextButton.icon(
              onPressed: state.detectTools,
              icon: const Icon(Icons.search),
              label: Text(s.detect)),
        ),
      ),
      section(s.configFile, HelpTopic.config),
      Row(children: [
        Expanded(child: Text(g.configPath ?? s.none)),
        Tooltip(
          message: tp.importConfig,
          child: TextButton(
            onPressed: () => _import(context),
            child: Text(s.importConfig),
          ),
        ),
        Tooltip(
          message: tp.exportConfig,
          child: TextButton(
            onPressed: () => _export(context),
            child: Text(s.exportConfig),
          ),
        ),
        if (g.configPath != null)
          tip(
            tp.removeConfig,
            TextButton(
              onPressed: () =>
                  state.updateSettings(g.copyWith(configPath: () => null)),
              child: Text(s.remove),
            ),
          ),
      ]),
      const SizedBox(height: 24),
      Row(children: [
        Text('check-script $appVersion', style: theme.textTheme.bodySmall),
        HelpButton(HelpTopic.about, lang: state.lang),
      ]),
    ]);
  }

  Future<void> _import(BuildContext context) async {
    final s = S(state.lang);
    final messenger = ScaffoldMessenger.of(context);
    final r = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['yaml', 'yml']);
    final path = r?.files.single.path;
    if (path == null) return;
    try {
      await state.importConfig(path);
      messenger.showSnackBar(SnackBar(content: Text(s.configImported(path))));
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.error(e.message))));
    } on FileSystemException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.error(e.message))));
    }
  }

  Future<void> _export(BuildContext context) async {
    final s = S(state.lang);
    final messenger = ScaffoldMessenger.of(context);
    final path = await FilePicker.saveFile(
      dialogTitle: s.exportConfig,
      fileName: '.checkscript.yaml',
      type: FileType.custom,
      allowedExtensions: ['yaml', 'yml'],
    );
    if (path == null) return;
    try {
      await state.exportConfig(path);
      messenger.showSnackBar(SnackBar(content: Text(s.configExported(path))));
    } on FileSystemException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.error(e.message))));
    }
  }

  String _version(S s, String tool) => state.toolVersions.containsKey(tool)
      ? (state.toolVersions[tool] == null
          ? s.notInstalled
          : '${s.available} ${state.toolVersions[tool]}')
      : '…';
}
