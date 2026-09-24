/// Réglages : langue, thème, profil, contextes, outils, configuration YAML.
library;

import 'package:check_script/check_script.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../strings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
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
    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 6),
          child: Text(title, style: theme.textTheme.titleMedium),
        );

    return ListView(padding: const EdgeInsets.all(16), children: [
      section(s.language),
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
      section(s.theme),
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
      section(s.profile),
      SegmentedButton<Profile>(
        segments: [
          ButtonSegment(value: Profile.strict, label: Text(s.profileStrict)),
          ButtonSegment(
              value: Profile.standard, label: Text(s.profileStandard)),
          ButtonSegment(value: Profile.legacy, label: Text(s.profileLegacy)),
        ],
        selected: {g.profile},
        onSelectionChanged: (v) =>
            state.updateSettings(g.copyWith(profile: v.first)),
      ),
      section(s.contexts),
      Wrap(spacing: 8, children: [
        for (final c in [
          ExecContext.root,
          ExecContext.cron,
          ExecContext.systemd
        ])
          FilterChip(
            label: Text(c.name),
            selected: g.contexts.contains(c),
            onSelected: (v) => state.updateSettings(g.copyWith(
                contexts:
                    v ? {...g.contexts, c} : ({...g.contexts}..remove(c)))),
          ),
      ]),
      section(s.tools),
      for (final (title, tools) in [
        (s.shellTools, ['shellcheck', 'shfmt', 'bashate', 'checkbashisms']),
        (
          s.pythonTools,
          [
            'ruff', 'bandit', 'semgrep', 'mypy', 'radon', 'vermin', //
            'pylint', 'pyright',
          ]
        ),
        (s.commonTools, ['gitleaks', 'trufflehog', 'syntax']),
      ]) ...[
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 16),
          child: Text(title, style: theme.textTheme.labelLarge),
        ),
        for (final tool in tools)
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
          ),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          Expanded(child: Text(s.pythonTarget)),
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
      SwitchListTile(
        title: Text(s.followSource),
        value: g.followSource,
        onChanged: (v) => state.updateSettings(g.copyWith(followSource: v)),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
            onPressed: state.detectTools,
            icon: const Icon(Icons.search),
            label: Text(s.detect)),
      ),
      section(s.configFile),
      Row(children: [
        Expanded(child: Text(g.configPath ?? s.none)),
        TextButton(
          onPressed: () async {
            final r = await FilePicker.pickFiles(
                type: FileType.custom, allowedExtensions: ['yaml', 'yml']);
            final path = r?.files.single.path;
            if (path != null) {
              await state.updateSettings(g.copyWith(configPath: () => path));
            }
          },
          child: Text(s.choose),
        ),
        if (g.configPath != null)
          TextButton(
            onPressed: () =>
                state.updateSettings(g.copyWith(configPath: () => null)),
            child: Text(s.remove),
          ),
      ]),
      const SizedBox(height: 24),
      Text('check-script $appVersion', style: theme.textTheme.bodySmall),
    ]);
  }

  String _version(S s, String tool) => state.toolVersions.containsKey(tool)
      ? (state.toolVersions[tool] == null
          ? s.notInstalled
          : '${s.available} ${state.toolVersions[tool]}')
      : '…';
}
