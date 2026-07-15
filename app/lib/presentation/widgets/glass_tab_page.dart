/// Glass Tab Page - OrbX Style Internal Tab Navigation
///
/// Provides bottom navigation bar for screens with internal tabs.
/// Supports optional search functionality with expand/collapse animation.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/brand.dart';
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

  /// Bottom-right floating action button. On standalone tab pages it floats
  /// above the bottom tab bar (kit: primary "Add"-style actions live here, not
  /// inline in the body).
  final Widget? floatingActionButton;
  final int initialIndex;

  /// When true, skips the outer GlassPage wrapper (for embedding in other screens)
  final bool embedded;

  /// Forwarded to the standalone GlassPage header: whether to show the round
  /// leading button, its icon (e.g. AppIcons.home to act as "go home"), and the
  /// tap handler.
  final bool showBackButton;
  final String? leadingIcon;
  final VoidCallback? onBack;

  const GlassTabPage({
    super.key,
    required this.title,
    required this.tabs,
    this.hasSearch = false,
    this.searchHint,
    this.onSearchChanged,
    this.actions,
    this.headerContent,
    this.floatingActionButton,
    this.initialIndex = 0,
    this.embedded = false,
    this.showBackButton = true,
    this.leadingIcon,
    this.onBack,
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
    // Note: GlassPage wraps body in SafeArea, so bottomPadding is already handled
    // We only need to add margin for the nav bar itself (12px)

    return GlassPage(
      title: widget.title,
      actions: widget.actions,
      embedded: widget.embedded,
      showBackButton: widget.showBackButton,
      leadingIcon: widget.leadingIcon,
      onBack: widget.onBack,
      body: widget.embedded ? _buildEmbeddedLayout() : _buildStandaloneLayout(),
    );
  }

  /// Standalone screens own the whole page, so the tab selector floats at the
  /// bottom like the app's main navigation bar.
  Widget _buildStandaloneLayout() {
    return Stack(
      children: [
        // Header content + Tab content
        Column(
          children: [
            // Optional header content (like action buttons)
            if (widget.headerContent != null) widget.headerContent!,

            // Tab content
            Expanded(child: _buildTabContent()),

            // Space for bottom nav (height + margin only, SafeArea handles safe area)
            const SizedBox(height: 60 + 12),
          ],
        ),

        // Floating action button — bottom-right, above the tab bar
        if (widget.floatingActionButton != null)
          Positioned(
            right: 20,
            bottom: 60 + 12 + 16,
            child: widget.floatingActionButton!,
          ),

        // Bottom navigation
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildBottomNav(),
        ),
      ],
    );
  }

  /// Embedded screens sit inside the app shell, which already shows the main
  /// bottom navigation bar — render the tab selector at the top instead of
  /// stacking a second pill above it.
  Widget _buildEmbeddedLayout() {
    final column = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: _buildNavRow(),
        ),
        if (widget.headerContent != null) widget.headerContent!,
        Expanded(child: _buildTabContent()),
      ],
    );
    if (widget.floatingActionButton == null) return column;
    return Stack(
      children: [
        column,
        Positioned(
          right: 20,
          bottom: 16,
          child: widget.floatingActionButton!,
        ),
      ],
    );
  }

  Widget _buildTabContent() {
    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      children: widget.tabs.map((tab) => tab.content).toList(),
    );
  }

  Widget _buildBottomNav() {
    // SafeArea in GlassPage already handles safe area insets
    // We only add 12px margin from the safe area boundary
    return Padding(
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 12,
      ),
      child: _buildNavRow(),
    );
  }

  Widget _buildNavRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = Theme.of(context).colorScheme.onSurface;

    return AnimatedBuilder(
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
        });
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
                        // Kit: only the ACTIVE tab takes lime — pill tint +
                        // ink-safe icon/label (deep lime on light).
                        color: isSelected
                            ? Brand.navActivePill
                            : Colors.transparent,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          DuotoneIcon(
                            tab.iconPath,
                            size: 22,
                            color: isSelected
                                ? Brand.navActive
                                : Brand.navInactive,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            tab.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: isSelected
                                  ? Brand.navActive
                                  : Brand.navInactive,
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
        decoration:
            GlassTheme.circularGlassDecoration(isDark: isDark, elevated: true),
        child: ClipOval(
          child: BackdropFilter(
            filter: GlassTheme.blurFilter,
            child: Center(
              child: DuotoneIcon(
                'magnifer',
                size: 24,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        decoration:
            GlassTheme.circularGlassDecoration(isDark: isDark, elevated: true),
        child: ClipOval(
          child: BackdropFilter(
            filter: GlassTheme.blurFilter,
            child: Center(
              child: DuotoneIcon(
                currentTab.iconPath,
                size: 26,
                color: Brand.navActive,
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
                  'magnifer',
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
                    cursorColor: Brand.focus,
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
