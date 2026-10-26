import 'package:flutter/material.dart';
import 'package:omni_plan/core/branding/plan_brand.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';

/// The three Omni Plan banner slides. Same layout idea as the Omni Tools
/// banners (brand tag, bold headline, one line of support, an illustration on
/// the right) but drawn in Flutter, so they follow the light and dark themes.
List<Widget> homeBannerSlides() => const [
  _BannerSlide(
    headline: ['PLAN BETTER.', 'GET THINGS DONE.'],
    subtitle: 'Tasks, projects and deadlines in one place.',
    icon: Icons.task_alt_rounded,
    iconColor: OmniDesignTokens.primary,
  ),
  _BannerSlide(
    headline: ['START FROM A', 'READY-MADE PLAN.'],
    subtitle: 'Pick a template, set the dates, done.',
    icon: Icons.dashboard_customize_rounded,
    iconColor: OmniDesignTokens.categoryBusiness,
  ),
  _BannerSlide(
    headline: ['WORKS OFFLINE.', 'SAVED ON YOUR PHONE.'],
    subtitle: 'Reminders arrive even with no signal.',
    icon: Icons.offline_pin_rounded,
    iconColor: OmniDesignTokens.categoryConverters,
  ),
];

class _BannerSlide extends StatelessWidget {
  final List<String> headline;
  final String subtitle;
  final IconData icon;
  final Color iconColor;

  const _BannerSlide({
    required this.headline,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ink = theme.colorScheme.onSurface;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [OmniDesignTokens.darkSurface, Color(0xFF16302F)]
              : const [Color(0xFFFFFFFF), Color(0xFFDDF4F3)],
        ),
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(OmniDesignTokens.radiusLargeCard),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 14,
            top: 14,
            bottom: 14,
            width: 118,
            child: _Art(icon: icon, color: iconColor),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 130, 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PlanLogo(height: 18),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline[0],
                        style: TextStyle(
                          color: ink,
                          fontSize: 19,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        headline[1],
                        style: TextStyle(
                          color: dark
                              ? OmniDesignTokens.primary
                              : OmniDesignTokens.primaryDeep,
                          fontSize: 19,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Two stacked sheets of paper with a badge, the banner's illustration.
class _Art extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _Art({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final paper = dark ? const Color(0xFF263031) : Colors.white;

    Widget sheet({required double angle, required double opacity}) =>
        Transform.rotate(
          angle: angle,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: 82,
              height: 106,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: paper,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [OmniDesignTokens.cardShadow],
                border: Border.all(
                  color: dark
                      ? OmniDesignTokens.darkBorder
                      : OmniDesignTokens.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 30, height: 5, decoration: _bar(color)),
                  const SizedBox(height: 8),
                  for (final w in const [58.0, 50.0, 56.0, 40.0]) ...[
                    Container(
                      width: w,
                      height: 4,
                      decoration: _bar(dark ? Colors.white24 : Colors.black12),
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          ),
        );

    return Stack(
      alignment: Alignment.center,
      children: [
        sheet(angle: -0.16, opacity: 0.75),
        sheet(angle: 0.08, opacity: 1),
        Positioned(
          right: 0,
          bottom: 6,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ],
    );
  }

  static BoxDecoration _bar(Color c) =>
      BoxDecoration(color: c, borderRadius: BorderRadius.circular(3));
}
