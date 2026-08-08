import 'package:flutter/material.dart';
import 'package:hiddify/gen/assets.gen.dart';

class YundoBrandLogo extends StatelessWidget {
  const YundoBrandLogo({super.key, required this.size, this.imageKey});

  final double size;
  final Key? imageKey;

  @override
  Widget build(BuildContext context) => Assets.images.appIcon.image(
    key: imageKey,
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
  );
}
