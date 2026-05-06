import 'package:flutter/material.dart';

import '../services/network_reachability.dart';
import '../theme.dart';

/// Persistent inline notice that pins to the top of any screen that talks to
/// the network. While [NetworkReachability.onlineNotifier] reports `false` we
/// render an amber bar with a wifi-off icon, copy explaining the impact, and
/// a tappable "Retry" affordance that re-probes via [NetworkReachability.recheck].
///
/// Uses [SizedBox.shrink] when online (or unknown) so callers can drop the
/// widget unconditionally at the top of their layout without worrying about
/// state — there's no layout footprint when it's not active.
///
/// Placement contract: callers are responsible for rendering this **above**
/// any scrolling content, not inside the scroll view, so that pulling the
/// list down doesn't hide the persistent indicator.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool?>(
      valueListenable: NetworkReachability.onlineNotifier,
      builder: (context, online, _) {
        // `null` = not yet probed. We deliberately render nothing in that
        // state; the cold-start `_initSDK` path sets it before the home
        // screen is reachable, and pre-probe assumptions (online vs offline)
        // would either lie or alarm.
        if (online != false) return const SizedBox.shrink();
        return Material(
          color: NeoTheme.amber.withValues(alpha: 0.18),
          child: InkWell(
            onTap: () => NetworkReachability.recheck(),
            child: SafeArea(
              top: false,
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.wifi_off_rounded,
                      size: 16,
                      color: NeoTheme.amber.withValues(alpha: 0.95),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'You\'re offline. Some data may be out of date.',
                        style: TextStyle(
                          color: Color(0xFFFDE68A),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Retry',
                      style: TextStyle(
                        color: NeoTheme.amber.withValues(alpha: 0.95),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.refresh_rounded,
                      size: 14,
                      color: NeoTheme.amber.withValues(alpha: 0.95),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
