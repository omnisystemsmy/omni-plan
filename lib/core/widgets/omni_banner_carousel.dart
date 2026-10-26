import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';

/// Banner carousel, same behaviour and geometry as the Omni Tools one: 16:9
/// slides at 92% viewport width, 24 px corners, a pill indicator and a new
/// slide every 4 seconds.
///
/// Images dropped into `assets/banners/` replace the built-in [slides]
/// automatically (file-name order), exactly like in Omni Tools.
class OmniBannerCarousel extends StatefulWidget {
  /// Slides shown when there are no banner images.
  final List<Widget> slides;

  const OmniBannerCarousel({super.key, required this.slides});

  @override
  State<OmniBannerCarousel> createState() => _OmniBannerCarouselState();
}

class _OmniBannerCarouselState extends State<OmniBannerCarousel> {
  static const _folder = 'assets/banners/';
  static const _exts = ['.jpg', '.jpeg', '.png', '.webp'];

  final PageController _controller = PageController(viewportFraction: 0.92);
  Timer? _timer;
  List<String> _assets = const [];
  int _page = 0;

  int get _count => _assets.isEmpty ? widget.slides.length : _assets.length;

  @override
  void initState() {
    super.initState();
    _loadAssets();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients || _count < 2) return;
      _controller.animateToPage(
        (_page + 1) % _count,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _loadAssets() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final found =
          manifest
              .listAssets()
              .where(
                (a) =>
                    a.startsWith(_folder) &&
                    _exts.any((e) => a.toLowerCase().endsWith(e)),
              )
              .toList()
            ..sort();
      if (mounted) setState(() => _assets = found);
    } catch (_) {
      // The built-in slides stay in place.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Widget _slide(int i) {
    final radius = BorderRadius.circular(OmniDesignTokens.radiusLargeCard);
    final Widget child = _assets.isNotEmpty
        ? Image.asset(
            _assets[i],
            fit: BoxFit.cover,
            width: double.infinity,
            cacheWidth: 1200,
            errorBuilder: (_, _, _) => widget.slides.first,
          )
        : widget.slides[i];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: PageView.builder(
            controller: _controller,
            itemCount: _count,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => _slide(i),
          ),
        ),
        if (_count > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _count; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
