/// Deux panneaux séparés par une barre déplaçable : glisser pour
/// redimensionner, double-clic pour revenir à la répartition par défaut,
/// boutons pour replier l'un ou l'autre panneau.
library;

import 'package:flutter/material.dart';

/// Panneau replié.
enum SplitCollapse { none, first, second }

/// Répartition entre deux panneaux : part du premier (0 à 1) et panneau
/// éventuellement replié. Sérialisée en `ratio;repli` dans les réglages.
class SplitState {
  final double ratio;
  final SplitCollapse collapsed;
  const SplitState(this.ratio, [this.collapsed = SplitCollapse.none]);

  SplitState copyWith({double? ratio, SplitCollapse? collapsed}) =>
      SplitState(ratio ?? this.ratio, collapsed ?? this.collapsed);

  String encode() => '${ratio.toStringAsFixed(4)};${collapsed.name}';

  /// Relit [encode] ; [fallback] si la valeur est absente ou invalide.
  static SplitState decode(String? s, SplitState fallback) {
    final parts = (s ?? '').split(';');
    final r = double.tryParse(parts.first);
    if (r == null || r <= 0 || r >= 1) return fallback;
    final c = SplitCollapse.values.firstWhere(
        (v) => parts.length > 1 && v.name == parts[1],
        orElse: () => SplitCollapse.none);
    return SplitState(r, c);
  }

  @override
  bool operator ==(Object other) =>
      other is SplitState &&
      other.ratio == ratio &&
      other.collapsed == collapsed;

  @override
  int get hashCode => Object.hash(ratio, collapsed);
}

class SplitView extends StatefulWidget {
  const SplitView({
    super.key,
    required this.axis,
    required this.first,
    required this.second,
    required this.state,
    required this.defaultState,
    required this.onChanged,
    this.minFirst = 160,
    this.minSecond = 240,
    this.collapseFirstTooltip,
    this.collapseSecondTooltip,
    this.restoreTooltip,
  });

  /// [Axis.horizontal] : panneaux côte à côte ; [Axis.vertical] : l'un
  /// au-dessus de l'autre.
  final Axis axis;
  final Widget first;
  final Widget second;
  final SplitState state;
  final SplitState defaultState;

  /// Appelé à la fin d'un glissement, au double-clic et au repli : la
  /// position n'est pas enregistrée à chaque image.
  final ValueChanged<SplitState> onChanged;

  /// Tailles minimales (pixels) des panneaux dépliés.
  final double minFirst;
  final double minSecond;
  final String? collapseFirstTooltip;
  final String? collapseSecondTooltip;
  final String? restoreTooltip;

  /// Épaisseur de la barre de séparation.
  static const handle = 12.0;

  @override
  State<SplitView> createState() => _SplitViewState();
}

class _SplitViewState extends State<SplitView> {
  /// Part du premier panneau pendant un glissement (null : [SplitView.state]).
  double? _dragRatio;

  bool get _horizontal => widget.axis == Axis.horizontal;

  /// Part bornée pour respecter les tailles minimales.
  double _clamp(double ratio, double total) {
    final avail = total - SplitView.handle;
    if (avail <= widget.minFirst + widget.minSecond) return ratio.clamp(0, 1);
    return ratio.clamp(
        widget.minFirst / avail, (avail - widget.minSecond) / avail);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final total = _horizontal ? c.maxWidth : c.maxHeight;
      final avail = (total - SplitView.handle).clamp(0.0, double.infinity);
      final collapsed = widget.state.collapsed;
      final ratio = _clamp(_dragRatio ?? widget.state.ratio, total);
      final firstSize = switch (collapsed) {
        SplitCollapse.first => 0.0,
        SplitCollapse.second => avail,
        SplitCollapse.none => avail * ratio,
      };

      // Un panneau replié reste dans l'arbre, hors écran et à sa taille
      // normale ([natural]) : ses filtres et son défilement sont conservés.
      // La structure est la même replié ou non, sinon l'état serait perdu.
      Widget sized(Widget child, double size, double natural) {
        final hidden = size <= 0;
        double? fixed(bool along) => hidden && along ? natural : null;
        return SizedBox(
          width: _horizontal ? size : null,
          height: _horizontal ? null : size,
          child: Offstage(
            offstage: hidden,
            child: OverflowBox(
              minWidth: fixed(_horizontal),
              maxWidth: fixed(_horizontal),
              minHeight: fixed(!_horizontal),
              maxHeight: fixed(!_horizontal),
              child: child,
            ),
          ),
        );
      }

      final children = [
        sized(widget.first, firstSize, avail * ratio),
        _handle(context, total, ratio),
        sized(widget.second, avail - firstSize, avail * (1 - ratio)),
      ];
      return _horizontal
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children);
    });
  }

  Widget _handle(BuildContext context, double total, double ratio) {
    final theme = Theme.of(context);
    final collapsed = widget.state.collapsed;
    final draggable = collapsed == SplitCollapse.none;

    void drag(DragUpdateDetails d) {
      final avail = total - SplitView.handle;
      if (avail <= 0) return;
      final delta = _horizontal ? d.delta.dx : d.delta.dy;
      setState(() =>
          _dragRatio = _clamp((_dragRatio ?? ratio) + delta / avail, total));
    }

    void end() {
      final r = _dragRatio;
      setState(() => _dragRatio = null);
      if (r != null) widget.onChanged(widget.state.copyWith(ratio: r));
    }

    // Boutons de repli : flèche vers le panneau à masquer, ou pour rétablir.
    Widget button(IconData icon, String? tip, SplitCollapse target) => SizedBox(
          width: _horizontal ? SplitView.handle : 28,
          height: _horizontal ? 28 : SplitView.handle,
          child: IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            iconSize: SplitView.handle + 2,
            tooltip: tip,
            icon: Icon(icon),
            onPressed: () =>
                widget.onChanged(widget.state.copyWith(collapsed: target)),
          ),
        );
    final back = _horizontal ? Icons.chevron_left : Icons.expand_less;
    final forth = _horizontal ? Icons.chevron_right : Icons.expand_more;
    final buttons = switch (collapsed) {
      SplitCollapse.none => [
          button(back, widget.collapseFirstTooltip, SplitCollapse.first),
          button(forth, widget.collapseSecondTooltip, SplitCollapse.second),
        ],
      SplitCollapse.first => [
          button(forth, widget.restoreTooltip, SplitCollapse.none)
        ],
      SplitCollapse.second => [
          button(back, widget.restoreTooltip, SplitCollapse.none)
        ],
    };

    // Les boutons sont posés par-dessus la zone de glissement, pas dedans :
    // sinon la détection du double-clic retarderait chaque clic.
    return SizedBox(
      width: _horizontal ? SplitView.handle : null,
      height: _horizontal ? null : SplitView.handle,
      child: Stack(fit: StackFit.expand, children: [
        MouseRegion(
          cursor: draggable
              ? (_horizontal
                  ? SystemMouseCursors.resizeColumn
                  : SystemMouseCursors.resizeRow)
              : MouseCursor.defer,
          child: GestureDetector(
            key: const Key('split-handle'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: draggable && _horizontal ? drag : null,
            onHorizontalDragEnd: draggable && _horizontal ? (_) => end() : null,
            onVerticalDragUpdate: draggable && !_horizontal ? drag : null,
            onVerticalDragEnd: draggable && !_horizontal ? (_) => end() : null,
            onDoubleTap: () => widget.onChanged(widget.defaultState),
            child: ColoredBox(
                color:
                    theme.colorScheme.outlineVariant.withValues(alpha: 0.35)),
          ),
        ),
        Center(
          child: Flex(
            direction: _horizontal ? Axis.vertical : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            children: buttons,
          ),
        ),
      ]),
    );
  }
}
