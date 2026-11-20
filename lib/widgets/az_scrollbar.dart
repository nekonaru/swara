import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:swara/l10n/gen/app_localizations.dart';

const List<String> kAllLetters = [
  '#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L',
  'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
];

class _PopupData {
  final String letter;
  final double globalY;
  const _PopupData(this.letter, this.globalY);
}

/// Minimalist A-Z scrollbar: a thin line on the right edge of the screen.
/// The letter popup follows the finger position (Y) and disappears when the finger is lifted.
class AzScrollbar extends StatefulWidget {
  final Set<String> availableLetters;
  final void Function(String letter) onLetterSelected;

  const AzScrollbar({
    super.key,
    required this.availableLetters,
    required this.onLetterSelected,
  });

  @override
  State<AzScrollbar> createState() => _AzScrollbarState();
}

class _AzScrollbarState extends State<AzScrollbar>
    with SingleTickerProviderStateMixin {
  final _scrollbarKey = GlobalKey();
  final _popupData = ValueNotifier<_PopupData?>(null);
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  OverlayEntry? _overlayEntry;
  DateTime _lastHaptic = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastSemanticLetter;

  // TalkBack cannot drag the thin rail, so expose stepping through the
  // available letters as increase/decrease actions.
  void _stepLetter(int delta) {
    final letters =
        kAllLetters.where(widget.availableLetters.contains).toList();
    if (letters.isEmpty) return;
    final current = _lastSemanticLetter == null
        ? (delta > 0 ? -1 : letters.length)
        : letters.indexOf(_lastSemanticLetter!);
    final next = (current + delta).clamp(0, letters.length - 1);
    _lastSemanticLetter = letters[next];
    HapticFeedback.selectionClick();
    widget.onLetterSelected(letters[next]);
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _removeOverlay();
    _popupData.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  String? _nearest(int idx) {
    for (int i = idx; i < kAllLetters.length; i++) {
      if (widget.availableLetters.contains(kAllLetters[i])) return kAllLetters[i];
    }
    for (int i = idx; i >= 0; i--) {
      if (widget.availableLetters.contains(kAllLetters[i])) return kAllLetters[i];
    }
    return null;
  }

  void _onTouch(Offset local, double height) {
    final idx = (local.dy / (height / kAllLetters.length))
        .floor()
        .clamp(0, kAllLetters.length - 1);
    final t = _nearest(idx);
    if (t == null) return;

    // Compute the global Y position so the popup can follow the finger
    final RenderBox? box =
        _scrollbarKey.currentContext?.findRenderObject() as RenderBox?;
    final double globalY =
        box != null ? box.localToGlobal(local).dy : local.dy;

    if (_overlayEntry == null) _showOverlay();

    final current = _popupData.value;
    _popupData.value = _PopupData(t, globalY);

    if (current?.letter != t) {
      // Throttle haptics: only when the letter changes plus a minimum ~50ms gap
      // so fast drags do not flood haptics.
      final now = DateTime.now();
      if (now.difference(_lastHaptic).inMilliseconds >= 50) {
        _lastHaptic = now;
        HapticFeedback.selectionClick();
      }
      widget.onLetterSelected(t);
    }
  }

  void _showOverlay() {
    final scaleAnim = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutBack));

    _overlayEntry = OverlayEntry(
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final screenH = MediaQuery.of(ctx).size.height;

        return ValueListenableBuilder<_PopupData?>(
          valueListenable: _popupData,
          builder: (_, data, __) {
            if (data == null) return const SizedBox.shrink();

            // Clamp so the popup stays on screen
            final top = (data.globalY - 32).clamp(60.0, screenH - 80.0);

            return Positioned(
              right: 44,
              top: top,
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: ScaleTransition(
                    scale: scaleAnim,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30),
                          bottomLeft: Radius.circular(30),
                          // bottomRight is sharp like a speech bubble pointing right
                          bottomRight: Radius.circular(4),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          data.letter,
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    try {
      final overlay = Overlay.maybeOf(context);
      if (overlay == null || !mounted) return;
      overlay.insert(_overlayEntry!);
      _fadeCtrl.forward();
    } catch (_) {
      _overlayEntry = null;
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onRelease() {
    if (!mounted) return;
    _fadeCtrl.reverse().then((_) {
      // Guard: do not touch the ValueNotifier or overlay after dispose.
      if (!mounted) return;
      _removeOverlay();
      _popupData.value = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: _scrollbarKey,
      width: 20,
      child: LayoutBuilder(builder: (context, constraints) {
        return Semantics(
          label: AppLocalizations.of(context)!.aZIndex,
          onIncrease: () => _stepLetter(1),
          onDecrease: () => _stepLetter(-1),
          child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (d) =>
              _onTouch(d.localPosition, constraints.maxHeight),
          onVerticalDragUpdate: (d) =>
              _onTouch(d.localPosition, constraints.maxHeight),
          onVerticalDragEnd: (_) => _onRelease(),
          onTapDown: (d) =>
              _onTouch(d.localPosition, constraints.maxHeight),
          onTapUp: (_) => _onRelease(),
          child: Center(
            child: Container(
              width: 3,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color:
                    Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        );
      }),
    );
  }
}
