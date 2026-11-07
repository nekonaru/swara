import 'package:flutter/material.dart';

/// Text that stays still and centered when it fits, and auto-scrolls (marquee)
/// back and forth when it is too long for the available width.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const MarqueeText(this.text, {super.key, this.style});

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final ScrollController _scrollController = ScrollController();
  // _loopId: increments every time the text changes - the old loop checks it and stops.
  int _loopId = 0;
  // _activeLoopId: ID of the loop currently running.
  // Used to prevent spawning a double loop when the widget rebuilds many times
  // with the SAME text (e.g. due to notifyListeners() from a background bulk scan).
  int? _activeLoopId;

  // Memo of the measured text width. LayoutBuilder rebuilds on every parent
  // frame; measuring with a fresh TextPainter each time was a full text
  // layout per frame for a permanent two line widget.
  double? _cachedTextWidth;
  String? _cachedForText;
  TextStyle? _cachedForStyle;

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _cachedTextWidth = null;
      _cachedForText = null;
      _cachedForStyle = null;
    }
    if (oldWidget.text != widget.text && _scrollController.hasClients) {
      _loopId++;          // cancel the old loop
      _activeLoopId = null; // free the slot so a new loop can spawn
      _scrollController.jumpTo(0);
    }
  }

  double _textWidth() {
    final cached = _cachedTextWidth;
    if (cached != null &&
        _cachedForText == widget.text &&
        _cachedForStyle == widget.style) {
      return cached;
    }
    final textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    _cachedTextWidth = textPainter.width;
    _cachedForText = widget.text;
    _cachedForStyle = widget.style;
    return textPainter.width;
  }

  Future<void> _runMarquee(double maxScroll, int myLoopId) async {
    // Prevent double-spawn: if a loop with the same loopId is already active, skip.
    if (_activeLoopId == myLoopId) return;
    _activeLoopId = myLoopId;

    // This loop may only run while myLoopId still matches the current _loopId.
    // Once the text changes (_loopId increases), this loop stops at the next check.
    while (mounted && _scrollController.hasClients && myLoopId == _loopId) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_scrollController.hasClients || myLoopId != _loopId) break;
      await _scrollController.animateTo(
        maxScroll,
        duration: Duration(milliseconds: (maxScroll * 30).clamp(1500, 8000).toInt()),
        curve: Curves.linear,
      );
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_scrollController.hasClients || myLoopId != _loopId) break;
      await _scrollController.animateTo(
        0,
        duration: Duration(milliseconds: (maxScroll * 30).clamp(1500, 8000).toInt()),
        curve: Curves.linear,
      );
    }

    // Loop finished or cancelled - free the slot so a new loopId can spawn
    if (_activeLoopId == myLoopId) _activeLoopId = null;
  }

  @override
  void dispose() {
    _loopId++; // make sure a loop that may still be running stops immediately
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final overflows = _textWidth() > constraints.maxWidth;

        if (!overflows) {
          // Text fits: render still, centered as usual
          return Center(
            child: Text(widget.text, style: widget.style, maxLines: 1, overflow: TextOverflow.ellipsis),
          );
        }

        // Text too long: start the marquee animation after this frame finishes.
        // Capture the current _loopId so only one loop is active per text.
        final currentLoopId = _loopId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients && currentLoopId == _loopId) {
            _runMarquee(_scrollController.position.maxScrollExtent, currentLoopId);
          }
        });

        return SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Text(widget.text, style: widget.style, maxLines: 1, softWrap: false),
        );
      },
    );
  }
}
