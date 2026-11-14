import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/components.dart';

/// One promotional slide. Every slide points at a real catalog destination
/// (a category search or a restaurant menu) supplied by the caller.
class PromoSlide {
  final String image; // bundled, licensed photo key (see docs/ASSET_CREDITS.md)
  final String folder;
  final String eyebrow;
  final String title;
  final String cta;
  final String route;
  const PromoSlide({
    required this.image,
    required this.title,
    required this.cta,
    required this.route,
    this.eyebrow = '',
    this.folder = 'categories',
  });
}

/// Auto-advancing, swipeable carousel with page indicators.
/// - Auto-advance every 5 s; disabled when the platform asks for reduced motion.
/// - Pauses while the route is not visible (TickerMode) and while the user drags.
/// - Timer is cancelled on dispose.
class PromoCarousel extends StatefulWidget {
  final List<PromoSlide> slides;
  final double height;
  const PromoCarousel({super.key, required this.slides, this.height = 196});
  @override
  State<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<PromoCarousel> {
  final _controller = PageController(viewportFraction: 0.92);
  Timer? _timer;
  int _page = 0;
  bool _dragging = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restart();
  }

  @override
  void didUpdateWidget(covariant PromoCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slides.length != widget.slides.length) _restart();
  }

  void _restart() {
    _timer?.cancel();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final visible = TickerMode.valuesOf(context).enabled;
    if (reduceMotion || !visible || widget.slides.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _advance());
  }

  void _advance() {
    if (!mounted || _dragging || !_controller.hasClients) return;
    final next = (_page + 1) % widget.slides.length;
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    if (slides.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification && n.dragDetails != null) {
                _dragging = true;
              }
              if (n is ScrollEndNotification) _dragging = false;
              return false;
            },
            child: PageView.builder(
              key: const ValueKey('promo-carousel'),
              controller: _controller,
              itemCount: slides.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: _SlideCard(slide: slides[i]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < slides.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == _page ? scheme.primary : scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SlideCard extends StatelessWidget {
  final PromoSlide slide;
  const _SlideCard({required this.slide});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '${slide.title}. ${slide.cta}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Material(
          child: InkWell(
            onTap: () => context.push(slide.route),
            child: Stack(
              fit: StackFit.expand,
              children: [
                FoodPhoto(slide.image, folder: slide.folder),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xCC000000), Color(0x22000000)],
                    ),
                  ),
                ),
                // Text scales down to fit the slide at large accessibility sizes
                // instead of overflowing; the card itself keeps a fixed height.
                LayoutBuilder(
                  builder: (context, box) => Padding(
                    padding: const EdgeInsets.all(18),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomLeft,
                        child: SizedBox(
                          width: (box.maxWidth - 36).clamp(0, double.infinity),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (slide.eyebrow.isNotEmpty)
                                Text(
                                  slide.eyebrow.toUpperCase(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white70,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                slide.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 7,
                                  ),
                                  child: Text(
                                    slide.cta,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
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
          ),
        ),
      ),
    );
  }
}
