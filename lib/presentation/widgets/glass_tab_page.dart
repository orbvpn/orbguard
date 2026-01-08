/// Glass Tab Page - OrbX Style Internal Tab Navigation
///
/// Provides bottom navigation bar for screens with internal tabs.
/// Supports optional search functionality with expand/collapse animation.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/colors.dart';
import '../theme/glass_theme.dart';
import 'duotone_icon.dart';
import 'glass_app_bar.dart';

/// Tab item configuration
class GlassTab {
  final String label;
  final String iconPath;
  final Widget content;

  const GlassTab({
    required this.label,
    required this.iconPath,
    required this.content,
  });
}

/// Glass Tab Page with OrbX-style bottom navigation
class GlassTabPage extends StatefulWidget {
  final String title;
  final List<GlassTab> tabs;
  final bool hasSearch;
  final String? searchHint;
  final ValueChanged<String>? onSearchChanged;
  final List<Widget>? actions;
  final Widget? headerContent;
  final int initialIndex;

  const GlassTabPage({
    super.key,
    required this.title,
    required this.tabs,
    this.hasSearch = false,
    this.searchHint,
    this.onSearchChanged,
    this.actions,
    this.headerContent,
    this.initialIndex = 0,
  });

  @override
  State<GlassTabPage> createState() => GlassTabPageState();
}

class GlassTabPageState extends State<GlassTabPage>
    with SingleTickerProviderStateMixin {
  late int _currentIndex;
  late PageController _pageController;

  // Search state
  bool _isSearchExpanded = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late AnimationController _searchAnimationController;
  late Animation<double> _searchExpandAnimation;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);

    // Initialize search animation
    _searchAnimationController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _searchExpandAnimation = CurvedAnimation(
      parent: _searchAnimationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchAnimationController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onTabSelected(int index) {
    if (_currentIndex == index) return;

    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _toggleSearch() {
    setState(() {
      _isSearchExpanded = !_isSearchExpanded;
    });
    if (_isSearchExpanded) {
      _searchAnimationController.forward();
      _searchFocusNode.requestFocus();
    } else {
      _searchAnimationController.reverse();
      _searchFocusNode.unfocus();
      _searchController.clear();
      widget.onSearchChanged?.call('');
    }
    HapticFeedback.mediumImpact();
  }

  void _onSearchChanged(String query) {
    widget.onSearchChanged?.call(query);
  }

  /// Navigate to a specific tab programmatically
  void animateToTab(int index) {
    _onTabSelected(index);
  }

  /// Get current tab index
  int get currentIndex => _currentIndex;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return GlassPage(
      title: widget.title,
      actions: widget.actions,
      body: Stack(
        children: [
          // Header content + Tab content
          Column(
            children: [
              // Optional header content (like action buttons)
              if (widget.headerContent != null) widget.headerContent!,

              // Tab content
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children:
                      widget.tabs.map((tab) => tab.content).toList(),
                ),
              ),

              // Space for bottom nav
              SizedBox(height: 60 + bottomPadding + 24),
            ],
          ),

          // Bottom navigation
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomNav(bottomPadding),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(double bottomPadding) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: bottomPadding + 12,
      ),
      child: AnimatedBuilder(
        animation: _searchExpandAnimation,
        builder: (context, child) {
          return Row(
            children: [
              // When search expanded: show collapsed tab button on LEFT
              if (_isSearchExpanded && widget.hasSearch) ...[
                _buildCollapsedTabButton(isDark, textColor),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildExpandedSearchBar(isDark, textColor),
                ),
              ] else ...[
                // Tabs container (left side)
                Expanded(
                  child: _buildTabsContainer(isDark, textColor),
                ),
                // Search button (right side) - only if hasSearch
                if (widget.hasSearch) ...[
                  const SizedBox(width: 10),
                  _buildSearchButton(isDark, textColor),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabsContainer(bool isDark, Color textColor) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: GlassTheme.glassColor(isDark),
        border: Border.all(
          color: GlassTheme.glassBorderColor(isDark),
          width: GlassTheme.borderWidth,
        ),
        boxShadow: [GlassTheme.elevatedShadow(isDark)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: GlassTheme.blurFilter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: List.generate(widget.tabs.length, (index) {
                final isSelected = _currentIndex == index;
                final tab = widget.tabs[index];

                return Expanded(
                  child: GestureDetector(
                    onTap: () => _onTabSelected(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        color: isSelected
                            ? (isDark
                                ? AppColors.accent.withAlpha(35)
                                : AppColors.accent.withAlpha(20))
                            : Colors.transparent,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          DuotoneIcon(
                            tab.iconPath,
                            size: 22,
                            color: isSelected
                                ? AppColors.accent
                                : (isDark
                                    ? Colors.white.withAlpha(150)
                                    : Colors.black.withAlpha(100)),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            tab.label,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight:
                                  isSelected ? FontWeight.w600 : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.accent
                                  : (isDark
                                      ? Colors.white.withAlpha(150)
                                      : Colors.black.withAlpha(100)),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildSearchButton(bool isDark, Color textColor) {
    return GestureDetector(
      onTap: _toggleSearch,
      child: Container(
        width: 60,
        height: 60,
        decoration: GlassTheme.circularGlassDecoration(isDark: isDark, elevated: true),
        child: ClipOval(
          child: BackdropFilter(
            filter: GlassTheme.blurFilter,
            child: Center(
              child: DuotoneIcon(
                'magnifier',
                size: 24,
                color: isDark ? Colors.white.withAlpha(180) : Colors.black.withAlpha(120),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedTabButton(bool isDark, Color textColor) {
    final currentTab = widget.tabs[_currentIndex];
    return GestureDetector(
      onTap: _toggleSearch,
      child: Container(
        width: 60,
        height: 60,
        decoration: GlassTheme.circularGlassDecoration(isDark: isDark, elevated: true),
        child: ClipOval(
          child: BackdropFilter(
            filter: GlassTheme.blurFilter,
            child: Center(
              child: DuotoneIcon(
                currentTab.iconPath,
                size: 26,
                color: AppColors.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedSearchBar(bool isDark, Color textColor) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: GlassTheme.glassColor(isDark),
        border: Border.all(
          color: GlassTheme.glassBorderColor(isDark),
          width: GlassTheme.borderWidth,
        ),
        boxShadow: [GlassTheme.elevatedShadow(isDark)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: GlassTheme.blurFilter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                DuotoneIcon(
                  'magnifier',
                  size: 22,
                  color: textColor.withAlpha(150),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: TextStyle(
                      fontSize: 16,
                      color: textColor,
                    ),
                    cursorColor: AppColors.accent,
                    decoration: InputDecoration(
                      hintText: widget.searchHint ?? 'Search...',
                      hintStyle: TextStyle(
                        fontSize: 16,
                        color: textColor.withAlpha(100),
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      filled: false,
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                GestureDetector(
                  onTap: _toggleSearch,
                  child: DuotoneIcon(
                    'close_circle',
                    size: 22,
                    color: textColor.withAlpha(150),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
