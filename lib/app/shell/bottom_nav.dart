import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';

/// Bottom bar with a notch for the centre "New" button. Adapted from the Omni
/// Tools bar (same geometry, motion and colours) without the app tour or the
/// Scan action. Omni Plan's destinations: Home, My Tasks, New, Projects,
/// Profile.
class BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BottomNav({super.key, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navTheme = theme.bottomNavigationBarTheme;
    final isLight = theme.brightness == Brightness.light;

    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: isLight
            ? const [
                BoxShadow(
                  color: Color(0x14202124),
                  blurRadius: 20,
                  offset: Offset(0, -4),
                ),
              ]
            : const [],
      ),
      child: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 7,
        color: navTheme.backgroundColor ?? theme.colorScheme.surface,
        elevation: 0,
        padding: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.none,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 68,
            child: Row(
              children: [
                Expanded(
                  child: _NavItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home_rounded,
                    label: 'Home',
                    isActive: currentIndex == 0,
                    onTap: () => onTap(0),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.task_alt_outlined,
                    activeIcon: Icons.task_alt_rounded,
                    label: 'My Tasks',
                    isActive: currentIndex == 1,
                    onTap: () => onTap(1),
                  ),
                ),
                SizedBox(
                  width: 78,
                  // Label under the centre button, on the same line as the
                  // other items.
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 30),
                      const SizedBox(height: 3),
                      Text(
                        'New',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color:
                              navTheme.unselectedItemColor ??
                              theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.folder_outlined,
                    activeIcon: Icons.folder_rounded,
                    label: 'Projects',
                    isActive: currentIndex == 2,
                    onTap: () => onTap(2),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.person_outline_rounded,
                    activeIcon: Icons.person_rounded,
                    label: 'Profile',
                    isActive: currentIndex == 3,
                    onTap: () => onTap(3),
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

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final selectedColor = isLight
        ? OmniDesignTokens.primaryDeep
        : theme.colorScheme.primary;
    final unselectedColor =
        theme.bottomNavigationBarTheme.unselectedItemColor ??
        theme.colorScheme.onSurfaceVariant;
    final color = isActive ? selectedColor : unselectedColor;

    return Semantics(
      button: true,
      selected: isActive,
      label: label,
      child: InkResponse(
        onTap: () {
          if (!isActive) HapticFeedback.selectionClick();
          onTap();
        },
        radius: 36,
        highlightShape: BoxShape.circle,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              width: isActive ? 56 : 36,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive
                    ? OmniDesignTokens.primary.withValues(
                        alpha: isLight ? 0.16 : 0.24,
                      )
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(
                  OmniDesignTokens.radiusPill,
                ),
              ),
              child: AnimatedScale(
                scale: isActive ? 1.1 : 1,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: Icon(
                    isActive ? activeIcon : icon,
                    key: ValueKey(isActive),
                    size: 23,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              style: (theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
                color: color,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                fontSize: 11,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
