import 'package:flutter/material.dart';

import '../theme.dart';

/// Accordion-style card that groups a section behind a tappable header
/// with an optional [status] pill and animated expand/collapse body.
class SectionCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final Widget? status;
  final Widget child;
  final bool initiallyExpanded;
  final Color accentColor;
  final VoidCallback? onExpand;

  const SectionCard({
    super.key,
    required this.icon,
    required this.title,
    this.status,
    required this.child,
    this.initiallyExpanded = false,
    this.accentColor = NeoTheme.emerald,
    this.onExpand,
  });

  @override
  State<SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<SectionCard>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late AnimationController _ctrl;
  late Animation<double> _heightFactor;
  late Animation<double> _iconTurns;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
      value: _expanded ? 1.0 : 0.0,
    );
    _heightFactor = _ctrl.drive(CurveTween(curve: Curves.easeInOut));
    _iconTurns = _ctrl.drive(
      Tween<double>(begin: 0.0, end: 0.5)
          .chain(CurveTween(curve: Curves.easeInOut)),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      _expanded ? _ctrl.forward() : _ctrl.reverse();
    });
    if (_expanded) widget.onExpand?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, bodyChild) {
        final accent = widget.accentColor;
        final borderColor = _expanded
            ? accent.withValues(alpha: 0.25)
            : const Color(0xFF2A2A2A);

        return Container(
          decoration: BoxDecoration(
            color: NeoTheme.eclipse,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _toggle,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(widget.icon,
                            size: 18,
                            color:
                                accent.withValues(alpha: 0.7)),
                        const SizedBox(width: 10),
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: NeoTheme.platinum,
                          ),
                        ),
                        const Spacer(),
                        if (widget.status != null) ...[
                          widget.status!,
                          const SizedBox(width: 8),
                        ],
                        RotationTransition(
                          turns: _iconTurns,
                          child: Icon(
                            Icons.expand_more_rounded,
                            size: 20,
                            color:
                                NeoTheme.platinum.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ClipRect(
                child: Align(
                  heightFactor: _heightFactor.value,
                  alignment: Alignment.topCenter,
                  child: bodyChild,
                ),
              ),
            ],
          ),
        );
      },
      child: Column(
        children: [
          Divider(
            height: 1,
            thickness: 1,
            color: NeoTheme.surfaceLight.withValues(alpha: 0.4),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// Small pill showing running/stopped or configuration status.
class StatusPill extends StatelessWidget {
  final bool active;
  final String label;

  const StatusPill({
    super.key,
    required this.active,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? NeoTheme.emerald : const Color(0xFF6B7280);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dark mono-spaced info box with a left accent bar.
class InfoBox extends StatelessWidget {
  final Widget child;
  final Color accentColor;

  const InfoBox({
    super.key,
    required this.child,
    this.accentColor = NeoTheme.emerald,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 3,
              color: accentColor.withValues(alpha: 0.45),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
