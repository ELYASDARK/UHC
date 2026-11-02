import 'package:flutter/material.dart';
import '../utils/content_direction.dart';

/// Resolve each paragraph independently while keeping stored content intact.
class ContentText extends StatelessWidget {
  const ContentText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: text
            .split('\n')
            .map((paragraph) => Text(
                  paragraph,
                  textDirection:
                      contentDirection(paragraph, Directionality.of(context)),
                  textAlign: TextAlign.start,
                  style: style,
                ))
            .toList(),
      );
}
