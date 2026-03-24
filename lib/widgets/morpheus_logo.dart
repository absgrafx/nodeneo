import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Morpheus mark from `Morpheus-Marketplace-APP/public/images/`.
class MorpheusLogo extends StatelessWidget {
  const MorpheusLogo({
    super.key,
    this.size = 28,
    this.variant = MorpheusLogoVariant.white,
  });

  final double size;
  final MorpheusLogoVariant variant;

  @override
  Widget build(BuildContext context) {
    final path = switch (variant) {
      MorpheusLogoVariant.white => 'assets/branding/morpheus_logo_white.svg',
      MorpheusLogoVariant.green => 'assets/branding/morpheus_logo_green.svg',
    };
    return SvgPicture.asset(
      path,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

enum MorpheusLogoVariant { white, green }
