part of 'focus_widgets.dart';

// Shared Focus primitives. Everything follows DESIGN.md §9 and the prototype:
// inverse text-on-bg primary buttons, hairline outline, ghost text-2, >= 44px
// targets, context colors only as dots / selected chips / the focus-block accent.

class _T {
  _T(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark;
  final bool dark;
  Color get bg =>
      dark ? EzyDesignTokens.darkBackground : EzyDesignTokens.lightBackground;
  Color get surface =>
      dark ? EzyDesignTokens.darkSurface : EzyDesignTokens.lightSurface;
  Color get text => dark ? EzyDesignTokens.darkText : EzyDesignTokens.lightText;
  Color get text2 =>
      dark ? EzyDesignTokens.darkText2 : EzyDesignTokens.lightText2;
  Color get hairline =>
      dark ? EzyDesignTokens.darkHairline : EzyDesignTokens.lightHairline;
  Color get danger =>
      dark ? EzyDesignTokens.darkDanger : EzyDesignTokens.lightDanger;
  Color get social =>
      dark ? EzyDesignTokens.darkSocial : EzyDesignTokens.lightSocial;
  Color accent(String? slug) => slug == 'work'
      ? (dark ? EzyDesignTokens.darkWork : EzyDesignTokens.lightWork)
      : slug == 'sidegig' || slug == 'side-gig'
      ? (dark ? EzyDesignTokens.darkSidegig : EzyDesignTokens.lightSidegig)
      : text;
  BoxShadow get cardShadow =>
      dark ? EzyDesignTokens.darkCardShadow : EzyDesignTokens.lightCardShadow;
  BoxShadow get sheetShadow =>
      dark ? EzyDesignTokens.darkSheetShadow : EzyDesignTokens.lightSheetShadow;
}

String _contextName(String slug) => slug == 'work' ? 'Work' : 'Side Gig';

/// Context dot, decorative only (the name always sits beside it).
class _Dot extends StatelessWidget {
  const _Dot(this.slug);
  final String slug;
  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      color: _T(context).accent(slug),
      shape: BoxShape.circle,
    ),
  );
}

/// Dot + name (+ optional suffix), the `f-ctxline` of the prototype.
class _CtxLine extends StatelessWidget {
  const _CtxLine(this.slug, {this.suffix, this.label});
  final String slug;
  final String? suffix, label;
  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        ExcludeSemantics(child: _Dot(slug)),
        Text(
          '${label ?? _contextName(slug)}${suffix == null ? '' : ' · $suffix'}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: t.text2,
          ),
        ),
      ],
    );
  }
}

enum _BS { primary, outline, ghost, duration }

/// The prototype's `.fb` button. [block] fills the width.
class _Btn extends StatelessWidget {
  const _Btn(
    this.label,
    this.onPressed, {
    this.style = _BS.primary,
    this.block = false,
    this.leading,
    this.danger = false,
    this.semanticLabel,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final _BS style;
  final bool block, danger;
  final Widget? leading;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    final fg = switch (style) {
      _BS.primary => t.bg,
      _BS.ghost => danger ? t.danger : t.text2,
      _BS.duration => t.text2,
      _BS.outline => t.text,
    };
    final bg = switch (style) {
      _BS.primary => t.text,
      _BS.ghost => Colors.transparent,
      _ => t.surface,
    };
    final button = TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg.withValues(alpha: .45),
        disabledForegroundColor: fg.withValues(alpha: .45),
        minimumSize: const Size(44, 44),
        padding: EdgeInsets.symmetric(
          horizontal: style == _BS.ghost
              ? 10
              : style == _BS.duration
              ? 14
              : 16,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        elevation: style == _BS.duration ? 1 : 0,
        shadowColor: style == _BS.duration ? t.cardShadow.color : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: style == _BS.outline || style == _BS.duration
              ? BorderSide(color: t.hairline, width: 1.5)
              : BorderSide.none,
        ),
        textStyle: TextStyle(
          fontSize: style == _BS.duration ? 13 : 15,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
    final wrapped = semanticLabel == null
        ? button
        : Semantics(label: semanticLabel, button: true, excludeSemantics: true, enabled: onPressed != null, onTap: onPressed, child: button);
    return block ? SizedBox(width: double.infinity, child: wrapped) : wrapped;
  }
}

/// Pill / rounded chip (`.fchip2`): selected = 1.5px context border + 10% tint.
class _Chip extends StatelessWidget {
  const _Chip(
    this.label,
    this.selected,
    this.onTap, {
    this.slug,
    this.radius = 999,
    this.leading,
    this.semanticLabel,
    this.expand = false,
    this.padding = 14,
    super.key,
  });
  final String label;
  final double padding;
  final bool selected, expand;
  final VoidCallback onTap;
  final String? slug;
  final double radius;
  final Widget? leading;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    final accent = t.accent(slug);
    final chip = Material(
      color: selected
          ? Color.alphaBlend(accent.withValues(alpha: .10), t.surface)
          : t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: selected ? accent : t.hairline, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 6)],
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? t.text : t.text2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      toggled: selected,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: chip,
    );
  }
}

/// Radio-style row (`.f-choice`) used for outcomes, "When" and context.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.selected,
    required this.onTap,
    this.secondary,
    this.slug,
    this.trailing,
    super.key,
  });
  final String title;
  final String? secondary, slug;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    final accent = t.accent(slug);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        button: true,
        label: secondary == null ? title : '$title, $secondary',
        excludeSemantics: true,
        onTap: onTap,
        child: Material(
          color: selected
              ? Color.alphaBlend(accent.withValues(alpha: .08), t.surface)
              : t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: selected ? accent : t.hairline, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? accent : t.text2,
                          width: 2,
                        ),
                      ),
                      child: selected
                          ? Center(
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: secondary == null
                                  ? FontWeight.w400
                                  : FontWeight.w700,
                              color: t.text,
                            ),
                          ),
                          if (secondary != null)
                            Text(
                              secondary!,
                              style: TextStyle(fontSize: 13, color: t.text2),
                            ),
                        ],
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Inset extends StatelessWidget {
  const _Inset(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: t.text2,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 14, color: t.text)),
        ],
      ),
    );
  }
}

/// A box with a 3px left accent (focus block, warnings). Flutter cannot round
/// a border with non-uniform sides, so the accent is its own strip, clipped.
class _AccentBox extends StatelessWidget {
  const _AccentBox({
    required this.accent,
    required this.color,
    required this.child,
    this.outline,
  });
  final Color accent, color;
  final Color? outline;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: outline == null ? null : Border.all(color: outline!),
    ),
    clipBehavior: Clip.antiAlias,
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 3, color: accent),
          Expanded(
            child: Container(
              color: color,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: child,
            ),
          ),
        ],
      ),
    ),
  );
}

class _FocusBlock extends StatelessWidget {
  const _FocusBlock(this.label, this.value, this.slug);
  final String label, value, slug;
  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    return _AccentBox(
      accent: t.accent(slug),
      color: t.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: t.text2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: t.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bordered `danger` left-accent block (save failure, deadline warning).
class _Warn extends StatelessWidget {
  const _Warn(this.title, this.body, {this.actions = const []});
  final String title, body;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: _AccentBox(
        accent: t.danger,
        color: t.bg,
        outline: t.hairline,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: t.danger,
              ),
            ),
            const SizedBox(height: 4),
            Text(body, style: TextStyle(fontSize: 13, color: t.text)),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline validation / failure text under a field, announced when it appears.
class _Err extends StatelessWidget {
  const _Err(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: _T(context).danger),
      ),
    ),
  );
}

class _Sub extends StatelessWidget {
  const _Sub(this.text, {this.optional = false});
  final String text;
  final bool optional;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text.rich(
      TextSpan(
        text: text,
        children: [
          if (optional)
            const TextSpan(
              text: ' (optional)',
              style: TextStyle(fontWeight: FontWeight.w400),
            ),
        ],
      ),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _T(context).text2,
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.top = 8, this.size = 12});
  final String text;
  final double top, size;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top),
    child: Text(text, style: TextStyle(fontSize: size, color: _T(context).text2)),
  );
}

/// Filled text field (`.f-input` / `.f-ta`). [label] is the accessible name;
/// the visible label is a separate [_Sub] above, as in the prototype.
InputDecoration _fieldDecoration(
  BuildContext context, {
  String? hint,
  bool invalid = false,
  bool filledBg = false,
}) {
  final t = _T(context);
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: t.text2),
    filled: true,
    fillColor: filledBg ? t.bg : t.surface,
    isDense: false,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: border(
      invalid
          ? t.danger
          : filledBg
          ? Colors.transparent
          : t.hairline,
    ),
    focusedBorder: border(invalid ? t.danger : t.accent('work'), 2),
    counterText: '',
  );
}

/// Section heading above Today's cards (`section-h`).
class _SectionHead extends StatelessWidget {
  const _SectionHead(this.title, {this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: EzyDesignTokens.sectionHeaderFontSize,
                fontWeight: EzyDesignTokens.sectionHeaderFontWeight,
                letterSpacing: EzyDesignTokens.sectionHeaderLetterSpacing,
                color: _T(context).text2,
              ),
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Card surface: 12px radius, hairline border, `shadow-card`.
class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.label,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? label;
  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    final box = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: padding,
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.hairline),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [t.cardShadow],
      ),
      child: child,
    );
    return label == null ? box : Semantics(container: true, label: label, child: box);
  }
}

String _mmss(int seconds) =>
    '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

void _announce(BuildContext context, String message) {
  try {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ),
    );
  } catch (_) {
    // Announcements are best effort (no semantics tree in some test setups).
  }
}

/// Parses "Minutes" input: whole numbers 1-180 only, else null.
int? _minutesFrom(String selected, String custom) {
  if (selected != 'custom') return int.tryParse(selected);
  final text = custom.trim();
  if (!RegExp(r'^\d+$').hasMatch(text)) return null;
  final n = int.parse(text);
  return n >= 1 && n <= 180 ? n : null;
}

const _minutesError = 'Choose a whole number from 1 to 180 minutes.';

/// Selected chip value for a minutes number among presets (else "custom").
String _presetFor(int minutes, List<String> presets) =>
    presets.contains('$minutes') ? '$minutes' : 'custom';

class _MinuteChips extends StatelessWidget {
  const _MinuteChips({
    required this.values,
    required this.selected,
    required this.slug,
    required this.onSelect,
    this.keyPrefix = 'focus-min',
  });
  final List<String> values;
  final String selected, keyPrefix;
  final String? slug;
  final ValueChanged<String> onSelect;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final v in values)
        _Chip(
          v == 'custom' ? 'Custom' : '$v min',
          selected == v,
          () => onSelect(v),
          slug: slug,
          key: ValueKey('$keyPrefix-$v'),
        ),
    ],
  );
}

class _MinutesField extends StatelessWidget {
  const _MinutesField({
    required this.controller,
    required this.invalid,
    required this.onChanged,
    this.label = 'Minutes (1–180)',
    this.showLabel = true,
    super.key,
  });
  final TextEditingController controller;
  final bool invalid, showLabel;
  final String label;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (showLabel) _Sub(label) else const SizedBox(height: 8),
      Semantics(
        label: label,
        textField: true,
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 15),
          decoration: _fieldDecoration(context, invalid: invalid),
          onChanged: (_) => onChanged(),
        ),
      ),
      if (invalid) const _Err(_minutesError),
    ],
  );
}
