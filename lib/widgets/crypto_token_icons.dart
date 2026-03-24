import 'package:flutter/material.dart';

/// Base chain badge (bottom-right inlay) — square chip, `assets/branding/base_chip.png`.
class BaseNetworkBadge extends StatelessWidget {
  const BaseNetworkBadge({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(size * 0.22);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: r,
        border: Border.all(color: const Color(0xFF0F172A), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/branding/base_chip.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        alignment: Alignment.center,
      ),
    );
  }
}

/// Ethereum diamond on classic ETH blue (`tools/branding/compose_token_squares.py`).
class EthTokenIcon extends StatelessWidget {
  const EthTokenIcon({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        'assets/branding/token_eth_base_square.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// MOR token on Morpheus green gradient square (same script).
class MorTokenIcon extends StatelessWidget {
  const MorTokenIcon({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        'assets/branding/token_mor_base_square.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// MetaMask-style: primary token + Base inlay at bottom-right.
class TokenWithBaseInlay extends StatelessWidget {
  const TokenWithBaseInlay({
    super.key,
    required this.token,
    this.diameter = 44,
    this.badgeDiameter = 18,
  });

  final Widget token;
  final double diameter;
  final double badgeDiameter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: diameter + 2,
      height: diameter + 2,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          SizedBox(width: diameter, height: diameter, child: token),
          Positioned(
            right: -1,
            bottom: -1,
            child: BaseNetworkBadge(size: badgeDiameter),
          ),
        ],
      ),
    );
  }
}
