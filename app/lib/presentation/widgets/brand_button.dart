/// BrandButton — the single source of truth for button states across the app.
///
/// Encodes the 2026 kit's exact fills for every state, in both themes:
///  • Primary   — lime fill / onLime text; hover [Brand.limeHover]; pressed
///                [Brand.limePressed]; disabled [Brand.disabledFill]/onDisabled.
///  • Secondary — glass (blur + hairline); [Brand.text] label.
///  • Destructive — [Brand.danger] fill / [Brand.onDanger] text.
/// Hover applies on desktop/web (pointer); press applies everywhere. Min hit
/// target is 44px — except [compact], the sanctioned micro-pill variant for
/// tight inline chrome (banners, list trailing actions): 30px min, 13.5pt
/// label, same state fills. Use this instead of hand-rolling buttons so a
/// token change restyles every button at once.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/brand.dart';

enum BrandButtonVariant { primary, secondary, destructive }

class BrandButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed; // null ⇒ disabled
  final BrandButtonVariant variant;
  final IconData? icon;
  final String? svgPath;
  final bool isLoading;
  final bool expand; // stretch to full width
  final double borderRadius;
  /// Defaults per size: normal h24/v15 · compact h14/v6.
  final EdgeInsetsGeometry? padding;
  /// Micro-pill for tight inline chrome where 44px would break the layout
  /// (e.g. the update-banner pill). Same kit state fills, smaller metrics.
  final bool compact;

  const BrandButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = BrandButtonVariant.primary,
    this.icon,
    this.svgPath,
    this.isLoading = false,
    this.expand = true,
    this.borderRadius = 14,
    this.padding,
    this.compact = false,
  });

  const BrandButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.svgPath,
    this.isLoading = false,
    this.expand = true,
    this.borderRadius = 14,
    this.padding,
    this.compact = false,
  }) : variant = BrandButtonVariant.secondary;

  const BrandButton.destructive({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.svgPath,
    this.isLoading = false,
    this.expand = true,
    this.borderRadius = 14,
    this.padding,
    this.compact = false,
  }) : variant = BrandButtonVariant.destructive;

  @override
  State<BrandButton> createState() => _BrandButtonState();
}

class _BrandButtonState extends State<BrandButton> {
  bool _hover = false;
  bool _pressed = false;

  bool get _disabled => widget.onPressed == null || widget.isLoading;

  static Color _darken(Color c, double amt) =>
      Color.lerp(c, const Color(0xFF000000), amt) ?? c;

  Color get _fill {
    if (_disabled) {
      return widget.variant == BrandButtonVariant.secondary
          ? Brand.glassFill
          : Brand.disabledFill;
    }
    switch (widget.variant) {
      case BrandButtonVariant.primary:
        return _pressed ? Brand.limePressed : (_hover ? Brand.limeHover : Brand.lime);
      case BrandButtonVariant.destructive:
        return _pressed
            ? _darken(Brand.danger, 0.12)
            : (_hover ? _darken(Brand.danger, 0.06) : Brand.danger);
      case BrandButtonVariant.secondary:
        // Glass base; press/hover conveyed by a veil overlay in build().
        return Brand.glassFill;
    }
  }

  Color get _fg {
    if (_disabled) return Brand.onDisabled;
    switch (widget.variant) {
      case BrandButtonVariant.primary:
        return Brand.onLime;
      case BrandButtonVariant.destructive:
        return Brand.onDanger;
      case BrandButtonVariant.secondary:
        return Brand.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGlass = widget.variant == BrandButtonVariant.secondary;
    final r = BorderRadius.circular(widget.borderRadius);
    final fg = _fg;

    // Compact = sanctioned micro-pill metrics; normal keeps the 44px target.
    final compact = widget.compact;
    final double glyph = compact ? 15 : 20;
    final double gap = compact ? 5 : 8;
    final double labelSize = compact ? 13.5 : 16;
    final double minHeight = compact ? 30 : 44;
    final EdgeInsetsGeometry pad = widget.padding ??
        (compact
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 24, vertical: 15));

    Widget content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.isLoading)
          SizedBox(
            width: glyph,
            height: glyph,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          )
        else ...[
          if (widget.svgPath != null) ...[
            SvgPicture.asset(widget.svgPath!,
                width: glyph, height: glyph, colorFilter: ColorFilter.mode(fg, BlendMode.srcIn)),
            SizedBox(width: gap),
          ] else if (widget.icon != null) ...[
            Icon(widget.icon, size: glyph, color: fg),
            SizedBox(width: gap),
          ],
          Flexible(
            child: Text(
              widget.label,
              overflow: TextOverflow.ellipsis,
              style: BrandText.title(
                  size: labelSize,
                  weight: compact ? FontWeight.w600 : FontWeight.w700,
                  color: fg),
            ),
          ),
        ],
      ],
    );

    Widget body = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      constraints: BoxConstraints(minHeight: minHeight), // hit target (30 compact)
      width: widget.expand ? double.infinity : null,
      padding: pad,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: r,
        border: isGlass ? Border.all(color: Brand.glassBorder, width: 1) : null,
        boxShadow: (!isGlass && !_disabled)
            ? [
                BoxShadow(
                  color: _fill.withValues(alpha: 0.30),
                  blurRadius: compact ? 10 : 16,
                  offset: Offset(0, compact ? 3 : 6),
                ),
              ]
            : null,
      ),
      child: content,
    );

    // Secondary is glassy: blur behind + a faint press veil.
    if (isGlass) {
      body = ClipRRect(
        borderRadius: r,
        child: Stack(
          children: [
            Positioned.fill(child: BackdropFilter(filter: Brand.blurSm, child: const SizedBox())),
            body,
            if (_pressed || _hover)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Brand.text.withValues(alpha: _pressed ? 0.10 : 0.05),
                      borderRadius: r,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return MouseRegion(
      cursor: _disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: _disabled ? null : (_) => setState(() => _pressed = true),
        onTapUp: _disabled
            ? null
            : (_) {
                setState(() => _pressed = false);
                widget.onPressed?.call();
              },
        onTapCancel: () => setState(() => _pressed = false),
        child: body,
      ),
    );
  }
}
