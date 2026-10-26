import 'package:flutter/material.dart';

/// One smooth transition for every page: the new page fades in while it
/// glides a few pixels in from the right, and the page below fades back a
/// little. Back reverses it.
class OmniPageTransitionsBuilder extends PageTransitionsBuilder {
  const OmniPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 340);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 280);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enter = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final leave = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.86).animate(leave),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.04, 0),
        ).animate(leave),
        child: FadeTransition(
          opacity: enter,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.07, 0),
              end: Offset.zero,
            ).animate(enter),
            child: child,
          ),
        ),
      ),
    );
  }
}

const PageTransitionsTheme omniPageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: OmniPageTransitionsBuilder(),
    TargetPlatform.iOS: OmniPageTransitionsBuilder(),
    TargetPlatform.windows: OmniPageTransitionsBuilder(),
    TargetPlatform.macOS: OmniPageTransitionsBuilder(),
    TargetPlatform.linux: OmniPageTransitionsBuilder(),
  },
);
