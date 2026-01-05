######################################

Created: /lib/presentation/theme/glass_theme.dart

Constants (iOS 26 Liquid Glass specs):

| Property              | Light Mode                         | Dark Mode                          |
| --------------------- | ---------------------------------- | ---------------------------------- |
| Glass Color           | white.withAlpha(230)               | white.withAlpha(22)                |
| Border Color          | black.withAlpha(12)                | white.withAlpha(30)                |
| Border Width          | 0.5                                | 0.5                                |
| Blur Sigma            | 20                                 | 20                                 |
| Shadow                | blur: 15, offset: (0,3), alpha: 15 | blur: 15, offset: (0,3), alpha: 40 |
| Border Radius (Pill)  | 38                                 | 38                                 |
| Border Radius (Large) | 24                                 | 24                                 |

Reusable Widgets:

1. GlassGradientBackground - Gradient for glass visibility (top/bottom)
2. GlassContainer - Generic glass container with blur
3. GlassPillContainer - Pill-shaped glass (for nav bars)
4. GlassCircleButton - Circular glass button

Helper Methods:

- GlassTheme.glassColor(isDark) - Get glass background color
- GlassTheme.glassBorderColor(isDark) - Get border color
- GlassTheme.shadow(isDark) - Get shadow
- GlassTheme.glassDecoration(...) - Complete glass decoration
- GlassTheme.pillGlassDecoration(...) - Pill-shaped decoration
- GlassTheme.circularGlassDecoration(...) - Circular decoration
- GlassTheme.blurFilter - Standard blur filter

Updated Files to Use GlassTheme:

- glass_bottom_nav.dart - Bottom navigation bar
- glass_connection_header.dart - Connection header widget
- home_screen.dart - Uses GlassGradientBackground
- dns_settings_screen.dart - All glass elements now use GlassTheme

Any future glass widgets will automatically match the iOS 26 Liquid Glass design by using these centralized constants and widgets.
