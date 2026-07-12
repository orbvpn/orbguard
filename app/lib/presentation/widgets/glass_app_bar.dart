/// Glass App Bar - iOS 26 Liquid Glass Design
/// Frosted glass-effect app bar widget matching OrbX design
///
/// Features:
/// - Round back button on LEFT
/// - Title in pill-shaped container on RIGHT
/// - Tap feedback animation (scale + opacity)

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/glass_theme.dart';
import '../theme/colors.dart';
import 'duotone_icon.dart';

/// Glass-styled floating header bar (OrbX style)
///
/// A floating header with round back button and pill-shaped title container.
/// Not a traditional PreferredSizeWidget - use inside a Stack.
class GlassHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? actionIcon;
  final VoidCallback? onAction;
  final bool showBackButton;

  const GlassHeader({
    super.key,
    required this.title,
    this.onBack,
    this.actionIcon,
    this.onAction,
    this.showBackButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textPrimary;
    final topPadding = MediaQuery.of(context).padding.top;

    return Padding(
      padding: EdgeInsets.only(
        top: topPadding + 12,
        left: 16,
        right: 16,
      ),
      child: Row(
        children: [
          // Back button (round, like OrbX)
          if (showBackButton)
            _TapFeedbackButton(
              onTap: onBack ?? () => Navigator.pop(context),
              child: Container(
                width: 50,
                height: 50,
                decoration: GlassTheme.circularGlassDecoration(isDark: isDark),
                child: ClipOval(
                  child: BackdropFilter(
                    filter: GlassTheme.blurFilter,
                    child: Center(
                      child: DuotoneIcon(
                        AppIcons.chevronLeft,
                        size: 22,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 50),

          const SizedBox(width: 12),

          // Title container (pill-shaped)
          Expanded(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: GlassTheme.glassColor(isDark),
                border: Border.all(
                  color: GlassTheme.glassBorderColor(isDark),
                  width: GlassTheme.borderWidth,
                ),
                boxShadow: [GlassTheme.shadow(isDark)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: BackdropFilter(
                  filter: GlassTheme.blurFilter,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        // Title text
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        // Optional action icon inside the pill
                        if (actionIcon != null && onAction != null)
                          _TapFeedbackButton(
                            onTap: onAction!,
                            child: actionIcon!,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Legacy Glass App Bar (PreferredSizeWidget) - for backward compatibility
/// Consider migrating to GlassHeader for new screens
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;
  final bool isDark;
  final double height;
  final VoidCallback? onLeadingTap;
  final bool showBackButton;

  const GlassAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.bottom,
    this.centerTitle = true,
    this.isDark = true,
    this.height = 56,
    this.onLeadingTap,
    this.showBackButton = false,
  });

  @override
  Size get preferredSize => Size.fromHeight(
    height + (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    final actualIsDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = actualIsDark ? Colors.white : AppColors.textPrimary;
    final totalHeight = height +
        (bottom?.preferredSize.height ?? 0) +
        MediaQuery.of(context).padding.top;

    return ClipRect(
      child: BackdropFilter(
        filter: GlassTheme.blurFilter,
        child: Container(
          height: totalHeight,
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
          decoration: BoxDecoration(
            color: GlassTheme.glassColor(actualIsDark),
            border: Border(
              bottom: BorderSide(
                color: GlassTheme.glassBorderColor(actualIsDark),
                width: GlassTheme.borderWidth,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: height,
                child: Row(
                  children: [
                    // Leading widget
                    if (leading != null)
                      leading!
                    else if (showBackButton)
                      _buildBackButton(context, textColor)
                    else
                      const SizedBox(width: 16),

                    // Title
                    Expanded(
                      child: centerTitle
                          ? Center(child: _buildTitle(textColor))
                          : _buildTitle(textColor),
                    ),

                    // Actions
                    if (actions != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: actions!,
                      )
                    else
                      const SizedBox(width: 16),
                  ],
                ),
              ),
              // Bottom widget (TabBar, etc.)
              if (bottom != null) bottom!,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(Color textColor) {
    if (titleWidget != null) return titleWidget!;
    if (title != null) {
      return Text(
        title!,
        style: TextStyle(
          color: textColor,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildBackButton(BuildContext context, Color textColor) {
    return GestureDetector(
      onTap: onLeadingTap ?? () => Navigator.of(context).pop(),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        child: DuotoneIcon(
          AppIcons.chevronLeft,
          color: textColor,
          size: 20,
        ),
      ),
    );
  }
}

/// Glass action button for app bar
class GlassAppBarAction extends StatelessWidget {
  final IconData? icon;
  final String? svgIcon;
  final VoidCallback? onTap;
  final bool isDark;
  final Color? color;
  final String? tooltip;

  const GlassAppBarAction({
    super.key,
    this.icon,
    this.svgIcon,
    this.onTap,
    this.isDark = true,
    this.color,
    this.tooltip,
  }) : assert(icon != null || svgIcon != null, 'Either icon or svgIcon must be provided');

  @override
  Widget build(BuildContext context) {
    final actualIsDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = color ?? (actualIsDark ? Colors.white : Colors.black87);

    Widget iconWidget;
    if (svgIcon != null) {
      iconWidget = SvgPicture.asset(
        'assets/icons/$svgIcon.svg',
        width: 22,
        height: 22,
        colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
      );
    } else {
      iconWidget = Icon(
        icon,
        color: iconColor,
        size: 22,
      );
    }

    Widget button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: iconWidget,
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }

    return button;
  }
}

/// Floating glass header (for scroll views)
class GlassFloatingHeader extends StatelessWidget {
  final Widget child;
  final bool isDark;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const GlassFloatingHeader({
    super.key,
    required this.child,
    this.isDark = true,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final actualIsDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
        child: BackdropFilter(
          filter: GlassTheme.blurFilter,
          child: Container(
            padding: padding ?? const EdgeInsets.all(16),
            decoration: GlassTheme.glassDecoration(
              isDark: actualIsDark,
              radius: GlassTheme.radiusMedium,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Glass status bar styling helper
class GlassStatusBar extends StatelessWidget {
  final Widget child;
  final bool isDark;

  const GlassStatusBar({
    super.key,
    required this.child,
    this.isDark = true,
  });

  @override
  Widget build(BuildContext context) {
    final actualIsDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: actualIsDark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
            ),
      child: child,
    );
  }
}

/// Glass scaffold wrapper
class GlassScaffold extends StatelessWidget {
  final Widget body;
  final GlassAppBar? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final bool isDark;
  final bool extendBodyBehindAppBar;

  const GlassScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.drawer,
    this.isDark = true,
    this.extendBodyBehindAppBar = true,
  });

  @override
  Widget build(BuildContext context) {
    final actualIsDark = Theme.of(context).brightness == Brightness.dark;

    return GlassStatusBar(
      isDark: actualIsDark,
      child: Container(
        decoration: BoxDecoration(
          gradient: GlassTheme.backgroundGradient(isDark: actualIsDark),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: extendBodyBehindAppBar,
          appBar: appBar,
          body: body,
          bottomNavigationBar: bottomNavigationBar,
          floatingActionButton: floatingActionButton,
          drawer: drawer,
        ),
      ),
    );
  }
}

/// Glass Page - OrbX-style page layout
///
/// A complete page layout matching OrbX design:
/// - Gradient background
/// - Column layout with header at top (NOT floating)
/// - SafeArea for proper padding
/// - Round back button LEFT + pill title RIGHT
class GlassPage extends StatelessWidget {
  final String title;
  final Widget body;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final VoidCallback? onAction;
  final bool showBackButton;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  /// When true, returns just the body without Scaffold/header (for embedding in other screens)
  final bool embedded;

  const GlassPage({
    super.key,
    required this.title,
    required this.body,
    this.onBack,
    this.actions,
    this.onAction,
    this.showBackButton = true,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    // When embedded, just return the body without wrapping scaffold/header
    if (embedded) {
      return body;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final textColor = isDark ? Colors.white : AppColors.textPrimary;

    return GlassStatusBar(
      isDark: isDark,
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              // OrbX-style header: round back + pill title
              _buildOrbXHeader(context, isDark, textColor),
              // Main content
              Expanded(child: body),
            ],
          ),
        ),
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
      ),
    );
  }

  /// OrbX-style header: round back button LEFT, pill title RIGHT
  Widget _buildOrbXHeader(BuildContext context, bool isDark, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Back button (round glass, 50x50)
          if (showBackButton)
            _TapFeedbackButton(
              onTap: onBack ?? () => Navigator.pop(context),
              child: Container(
                width: 50,
                height: 50,
                decoration: GlassTheme.circularGlassDecoration(isDark: isDark),
                child: ClipOval(
                  child: BackdropFilter(
                    filter: GlassTheme.blurFilter,
                    child: Center(
                      child: DuotoneIcon(
                        AppIcons.chevronLeft,
                        size: 22,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (showBackButton) const SizedBox(width: 12),
          // Title container (pill-shaped)
          Expanded(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: GlassTheme.glassColor(isDark),
                border: Border.all(
                  color: GlassTheme.glassBorderColor(isDark),
                  width: GlassTheme.borderWidth,
                ),
                boxShadow: [GlassTheme.shadow(isDark)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: BackdropFilter(
                  filter: GlassTheme.blurFilter,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        // Title text
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        // Action icons inside the pill
                        if (actions != null)
                          ...actions!.map((action) => Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: action,
                              )),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Glass bottom navigation bar
class GlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlassBottomNavItem> items;
  final bool isDark;

  const GlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.isDark = true,
  });

  @override
  Widget build(BuildContext context) {
    final actualIsDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GlassTheme.radiusPill),
        child: BackdropFilter(
          filter: GlassTheme.blurFilter,
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: GlassTheme.pillGlassDecoration(isDark: actualIsDark),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(items.length, (index) {
                final item = items[index];
                final isSelected = index == currentIndex;
                final iconColor = isSelected
                    ? AppColors.accent
                    : (actualIsDark ? Colors.white54 : Colors.black45);

                return GestureDetector(
                  onTap: () => onTap(index),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: isSelected
                        ? BoxDecoration(
                            color: AppColors.accent.withAlpha(30),
                            borderRadius: BorderRadius.circular(20),
                          )
                        : null,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.svgIcon != null)
                          DuotoneIcon(
                            isSelected ? (item.activeSvgIcon ?? item.svgIcon!) : item.svgIcon!,
                            color: iconColor,
                            size: 24,
                          )
                        else
                          Icon(
                            isSelected ? item.activeIcon : item.icon,
                            color: iconColor,
                            size: 24,
                          ),
                        if (item.label != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.label!,
                            style: TextStyle(
                              color: iconColor,
                              fontSize: 10,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass bottom nav item data
class GlassBottomNavItem {
  final IconData? icon;
  final IconData? activeIcon;
  final String? svgIcon;
  final String? activeSvgIcon;
  final String? label;

  const GlassBottomNavItem({
    this.icon,
    this.activeIcon,
    this.svgIcon,
    this.activeSvgIcon,
    this.label,
  }) : assert(icon != null || svgIcon != null, 'Either icon or svgIcon must be provided');

  /// Named constructor for SVG icons
  const GlassBottomNavItem.svg({
    required String icon,
    String? activeIcon,
    this.label,
  })  : svgIcon = icon,
        activeSvgIcon = activeIcon ?? icon,
        icon = null,
        activeIcon = null;
}

// ============================================================================
// TAP FEEDBACK BUTTON
// ============================================================================

/// A button with visual tap feedback (scale + opacity animation)
class _TapFeedbackButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _TapFeedbackButton({
    required this.child,
    required this.onTap,
  });

  @override
  State<_TapFeedbackButton> createState() => _TapFeedbackButtonState();
}

class _TapFeedbackButtonState extends State<_TapFeedbackButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
    HapticFeedback.selectionClick();
    widget.onTap();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(
              opacity: _opacityAnimation.value,
              child: widget.child,
            ),
          );
        },
      ),
    );
  }
}
