/// Glass App Bar - iOS 26 Liquid Glass Design
/// Frosted glass-effect app bar widget

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/glass_theme.dart';

/// Glass-styled app bar with blur effect
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
            color: GlassTheme.glassColor(isDark),
            border: Border(
              bottom: BorderSide(
                color: GlassTheme.glassBorderColor(isDark),
                width: GlassTheme.borderWidth,
              ),
            ),
          ),
          child: Column(
            children: [
              SizedBox(
                height: height,
                child: Row(
                  children: [
                    // Leading widget
                    if (leading != null)
                      leading!
                    else if (showBackButton)
                      _buildBackButton(context)
                    else
                      const SizedBox(width: 16),

                    // Title
                    Expanded(
                      child: centerTitle
                          ? Center(child: _buildTitle())
                          : _buildTitle(),
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

  Widget _buildTitle() {
    if (titleWidget != null) return titleWidget!;
    if (title != null) {
      return Text(
        title!,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildBackButton(BuildContext context) {
    return GestureDetector(
      onTap: onLeadingTap ?? () => Navigator.of(context).pop(),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        child: Icon(
          Icons.arrow_back_ios_new,
          color: isDark ? Colors.white : Colors.black87,
          size: 20,
        ),
      ),
    );
  }
}

/// Glass action button for app bar
class GlassAppBarAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDark;
  final Color? color;
  final String? tooltip;

  const GlassAppBarAction({
    super.key,
    required this.icon,
    this.onTap,
    this.isDark = true,
    this.color,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    Widget button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Icon(
          icon,
          color: color ?? (isDark ? Colors.white : Colors.black87),
          size: 22,
        ),
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
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
        child: BackdropFilter(
          filter: GlassTheme.blurFilter,
          child: Container(
            padding: padding ?? const EdgeInsets.all(16),
            decoration: GlassTheme.glassDecoration(
              isDark: isDark,
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
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
    return GlassStatusBar(
      isDark: isDark,
      child: Container(
        decoration: BoxDecoration(
          gradient: GlassTheme.backgroundGradient(isDark: isDark),
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
    return Container(
      margin: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GlassTheme.radiusPill),
        child: BackdropFilter(
          filter: GlassTheme.blurFilter,
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: GlassTheme.pillGlassDecoration(isDark: isDark),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(items.length, (index) {
                final item = items[index];
                final isSelected = index == currentIndex;

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
                            color: GlassTheme.primaryAccent.withAlpha(30),
                            borderRadius: BorderRadius.circular(20),
                          )
                        : null,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSelected ? item.activeIcon : item.icon,
                          color: isSelected
                              ? GlassTheme.primaryAccent
                              : (isDark ? Colors.white54 : Colors.black45),
                          size: 24,
                        ),
                        if (item.label != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.label!,
                            style: TextStyle(
                              color: isSelected
                                  ? GlassTheme.primaryAccent
                                  : (isDark ? Colors.white54 : Colors.black45),
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
  final IconData icon;
  final IconData activeIcon;
  final String? label;

  const GlassBottomNavItem({
    required this.icon,
    IconData? activeIcon,
    this.label,
  }) : activeIcon = activeIcon ?? icon;
}
