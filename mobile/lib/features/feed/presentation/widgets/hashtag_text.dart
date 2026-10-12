import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// `#` + 2–30 letters, digits or underscores, not glued to a preceding word.
final _hashtag = RegExp(r'(^|[^\p{L}\p{M}\p{N}_&])#([\p{L}\p{M}\p{N}_]{2,30})',
    unicode: true);

/// Post text with #hashtags highlighted; tapping one calls [onTag] with the
/// lowercase tag (no `#`). Without [onTag] tags are only highlighted.
class HashtagText extends StatefulWidget {
  const HashtagText(this.text, {super.key, this.style, this.onTag});

  final String text;
  final TextStyle? style;
  final ValueChanged<String>? onTag;

  @override
  State<HashtagText> createState() => _HashtagTextState();
}

class _HashtagTextState extends State<HashtagText> {
  final _recognizers = <TapGestureRecognizer>[];

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final text = widget.text;
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in _hashtag.allMatches(text)) {
      final tagStart = match.start + match.group(1)!.length;
      if (tagStart > cursor) spans.add(TextSpan(text: text.substring(cursor, tagStart)));
      final tag = match.group(2)!;
      TapGestureRecognizer? recognizer;
      if (widget.onTag != null) {
        recognizer = TapGestureRecognizer()
          ..onTap = () => widget.onTag!(tag.toLowerCase());
        _recognizers.add(recognizer);
      }
      spans.add(TextSpan(
        text: '#$tag',
        recognizer: recognizer,
        style: const TextStyle(
            color: Color(0xFF7357E8), fontWeight: FontWeight.w700),
      ));
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(TextSpan(children: spans), style: widget.style);
  }
}
