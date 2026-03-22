import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

extension GradientExtension on Widget {
  Widget withPrimaryGradient(BuildContext context) {
    final gradient = context.watch<ThemeProvider>().primaryGradient;
    if (gradient == null) return this;
    
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: this,
    );
  }
}
