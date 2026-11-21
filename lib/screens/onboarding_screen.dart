import 'dart:async';

import 'package:flutter/material.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/permission_service.dart';
import 'home_screen.dart';

// Storage key marking that onboarding was completed or skipped.
const String kOnboardingDoneKey = 'onboarding_done';
const String _kOnboardingPageKey = 'onboarding_page';

// Simple data holder for one onboarding page.
class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String description;
  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.description,
  });
}

// First launch onboarding with 3 swipeable pages.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;
  // Blocks double taps on Skip and Get Started while finishing.
  bool _finishing = false;

  static const int _pageCount = 3;
  static const _duration = Duration(milliseconds: 320);
  static const _curve = Cubic(0.23, 1.0, 0.32, 1.0);

  static List<_OnboardingPageData> _pagesOf(AppLocalizations l10n) => [
        _OnboardingPageData(
          icon: Icons.library_music_outlined,
          title: l10n.onboardTitle1,
          description: l10n.onboardDesc1,
        ),
        _OnboardingPageData(
          icon: Icons.auto_awesome_outlined,
          title: l10n.onboardTitle2,
          description: l10n.onboardDesc2,
        ),
        _OnboardingPageData(
          icon: Icons.play_circle_outline,
          title: l10n.onboardTitle3,
          description: l10n.onboardDesc3,
        ),
      ];

  @override
  void initState() {
    super.initState();
    _restorePage();
  }

  Future<void> _restorePage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_kOnboardingPageKey) ?? 0;
      if (!mounted || saved <= 0 || saved >= _pageCount) return;
      setState(() => _index = saved);
      _controller.jumpToPage(saved);
    } catch (_) {
      // Page progress is optional; start at the first page.
    }
  }

  Future<void> _rememberPage(int page) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kOnboardingPageKey, page);
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Mark onboarding as done, ask for permissions now that the intro has been
  // explained, then open the home screen with the standard Material transition.
  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kOnboardingDoneKey, true);
    } catch (e) {
      debugPrint('Failed to save onboarding flag: $e');
    }
    unawaited(PermissionService.ensureEssentialPermissions());
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _next(bool reduceMotion) {
    if (_index < _pageCount - 1) {
      if (reduceMotion) {
        _controller.jumpToPage(_index + 1);
      } else {
        _controller.nextPage(duration: _duration, curve: _curve);
      }
    } else {
      _finish();
    }
  }

  Widget _page(
    _OnboardingPageData page,
    ColorScheme cs,
    bool reduceMotion,
    double maxHeight,
  ) {
    final iconSide = (maxHeight * 0.2).clamp(72.0, 120.0);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: iconSide,
          height: iconSide,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(page.icon,
              size: iconSide * 0.46, color: cs.onPrimaryContainer),
        ),
        const SizedBox(height: 32),
        Text(
          page.title,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          page.description,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
    if (reduceMotion) return content;
    // One-shot, paint-only entrance. The page itself is the child so the
    // PageView never rebuilds while the tween advances.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: const Cubic(0.2, 0.0, 0.0, 1.0),
      child: content,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 16),
          child: child,
        ),
      ),
    );
  }

  Widget _dots(ColorScheme cs, bool reduceMotion) {
    final widget = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final position = _controller.page ?? _index.toDouble();
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_pageCount, (i) {
            final selected = (position - i).abs().clamp(0.0, 1.0);
            final width = 8.0 + (1 - selected) * 16;
            return Container(
              key: ValueKey('dot_$i'),
              width: width,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Color.lerp(cs.surfaceContainerHighest, cs.primary,
                    1 - selected),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        );
      },
    );
    if (reduceMotion) return widget;
    return Semantics(
      label: '${_index + 1} / $_pageCount',
      child: widget,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pages = _pagesOf(l10n);
    final cs = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final isLast = _index == pages.length - 1;

    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          actions: [
            if (!isLast)
              TextButton(
                onPressed: _finish,
                child: Text(l10n.onboardSkip),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: PageView.builder(
                        controller: _controller,
                        itemCount: pages.length,
                        onPageChanged: (i) {
                          setState(() => _index = i);
                          _rememberPage(i);
                        },
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Center(
                            child: _page(pages[i], cs, reduceMotion,
                                constraints.maxHeight),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _dots(cs, reduceMotion),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => _next(reduceMotion),
                    child: Text(
                        isLast ? l10n.onboardGetStarted : l10n.onboardNext),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
