import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../app_route_observer.dart';
import '../../constants/app_brand.dart';
import '../../constants/network_tokens.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/bridge.dart';
import '../../services/model_status_api.dart';
import '../../services/platform_caps.dart';
import '../../services/rpc_endpoint_validator.dart';
import '../../services/rpc_settings_store.dart';
import '../../services/session_duration_store.dart';
import '../../theme.dart';
import '../../utils/token_amount.dart';
import '../../widgets/crypto_token_icons.dart';
import '../../widgets/session_confirmation_sheet.dart';
import '../chat/chat_screen.dart';
import '../chat/conversation_transcript_screen.dart';
import '../settings/about_screen.dart';
import '../settings/expert_screen.dart';
import '../settings/backup_reset_screen.dart';
import '../settings/sessions_screen.dart';
import '../settings/wallet_screen.dart';
import '../../widgets/session_close_flow.dart';
import '../../widgets/send_token_sheet.dart';


/// Primary line for history / continue cards: saved topic, else model name.
String conversationHeadline(Map<String, dynamic> c) {
  final t = (c['title'] as String?)?.trim() ?? '';
  if (t.isNotEmpty) return t;
  return c['model_name'] as String? ?? 'Chat';
}

/// Subtitle: model, secure vs standard, session state (+ minutes left when [session_ends_at] set), relative time.
String conversationMetaLine(
  Map<String, dynamic> c,
  String Function(Map<String, dynamic>) rel,
) {
  final model = c['model_name'] as String? ?? 'Model';
  final tee = c['is_tee'] == true;
  final sid = c['session_id'];
  final hasSession = sid is String && sid.isNotEmpty;
  final endsAt = (c['session_ends_at'] as num?)?.toInt();
  final String sessionBit;
  if (!hasSession) {
    sessionBit = 'Session closed';
  } else if (endsAt != null && endsAt > 0) {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final left = endsAt - nowSec;
    if (left <= 0) {
      sessionBit = 'Session ended';
    } else {
      final minutes = (left + 59) ~/ 60;
      sessionBit = minutes <= 1 ? '~1 min left' : '~$minutes min left';
    }
  } else {
    sessionBit = 'On-chain open';
  }
  return '$model · ${tee ? 'Secure' : 'Standard'} · $sessionBit · ${rel(c)}';
}

/// Top-level isolate entry — must be a top-level / static function so
/// [compute] can ship it across the isolate boundary. Sums active stake for
/// the supplied session IDs via the Go bridge.
Map<String, dynamic> _sumActiveSessionStakesSync(List<String> ids) =>
    GoBridge().sumActiveSessionStakes(ids);

class HomeScreen extends StatefulWidget {
  final Future<void> Function()? onWalletErased;
  final Future<void> Function()? onRpcChanged;
  final Future<void> Function()? onFactoryReset;

  const HomeScreen({
    super.key,
    this.onWalletErased,
    this.onRpcChanged,
    this.onFactoryReset,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  static const int _walletBalanceDecimals = 5;

  Timer? _sessionRefreshTimer;
  bool _maxPrivacy = false;
  String _address = '';
  String _ethBalance = '—';
  String _morBalance = '—';
  String _rawEthWei = '0';
  String _rawMorWei = '0';
  bool _rpcChecking = true;
  bool? _rpcReachable;
  ModelStatusResponse? _statusApi;
  List<ModelStatusEntry> _models = [];
  bool _loadingModels = false;
  String? _modelsError;
  List<Map<String, dynamic>> _historyConvos = [];
  List<Map<String, dynamic>> _activeResumeChats = [];

  /// Sum of on-chain stake across `_activeResumeChats` — the "Active (Staked)"
  /// figure shown on the wallet card. Computed via the targeted
  /// [GoBridge.sumActiveSessionStakes] FFI (one eth_call per local session).
  /// `null` until the first scan completes; does not block the UI.
  String? _activeStakeWei;
  int _activeStakeComputationId = 0;

  /// Network-global calibration cached from a single `EstimateOpenSessionStake`
  /// call. The stake formula is:
  ///
  ///     stake = (supply × price_per_second × duration) ÷ emissions_budget
  ///
  /// `supply` and `budget` are identical for every model and change slowly,
  /// so caching them once per home refresh lets us derive any model's stake
  /// for any duration from the `min_price_mor_hr` already in the status API
  /// response — pure BigInt math, no extra FFI calls.
  BigInt? _supplyWei;
  BigInt? _budgetWei;

  /// Default session length for affordability gating on the home screen,
  /// read from [SessionDurationStore] during the compute pass so tile
  /// greying reflects the same duration the modal defaults to.
  int _defaultDurationSeconds = SessionDurationStore.defaultSeconds;

  int _affordabilityComputationId = 0;

  /// Tri-state phase for affordability:
  ///
  ///   * `_affordabilityLoading = true` — calibration hasn't finished yet;
  ///     tiles render muted as a loading cue ("light up when known good").
  ///   * `_affordabilityLoading = false, _affordabilityResolved = true` —
  ///     calibration succeeded; the cache is authoritative.
  ///   * `_affordabilityLoading = false, _affordabilityResolved = false` —
  ///     calibration failed (RPC down / no bids); render everything bright
  ///     and disable the "show only affordable" filter so the user isn't
  ///     stranded looking at a greyed-out or empty list.
  bool _affordabilityLoading = true;
  bool _affordabilityResolved = false;

  /// User toggle: when true, show unaffordable models (greyed) alongside
  /// affordable ones. Default (false) hides unaffordable rows to keep the
  /// list focused on what can actually start right now.
  bool _showUnaffordable = false;

  @override
  void initState() {
    super.initState();
    _loadWallet();
    _refreshRpcReachability();
    _loadModels();
    _loadConversations();
    // Idle refresh: conversations (for expiry/closed reconciliation) plus
    // wallet balance so the model list's affordability verdicts don't go
    // stale after off-screen balance changes (e.g. direct on-chain transfers).
    _sessionRefreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted) return;
      _loadConversations();
      _loadWallet();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      neoRouteObserver.unsubscribe(this);
      neoRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _sessionRefreshTimer?.cancel();
    neoRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadConversations();
    _loadWallet();
    _refreshRpcReachability();
    _loadModels();
  }

  Future<void> _refreshRpcReachability() async {
    if (!mounted) return;
    setState(() {
      _rpcChecking = true;
    });
    try {
      final raw = await RpcSettingsStore.instance.effectiveRpcUrl();
      final ok = await RpcEndpointValidator.anyReachable(raw);
      if (mounted) {
        setState(() {
          _rpcReachable = ok;
          _rpcChecking = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _rpcReachable = false;
          _rpcChecking = false;
        });
      }
    }
  }

  /// Conversations: SQLite order is pinned first, then updated_at (see Go ListConversations).
  void _loadConversations() {
    try {
      final bridge = GoBridge();
      final raw = bridge.getConversations();
      final list = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is Map) list.add(Map<String, dynamic>.from(e));
      }
      final active = list
          .where((m) {
            final sid = m['session_id'];
            return sid is String && sid.isNotEmpty;
          })
          .take(12)
          .toList();
      if (mounted) {
        setState(() {
          _historyConvos = list;
          _activeResumeChats = active;
        });
        // NOTE: We deliberately do NOT fire `_computeActiveStake` from
        // here. At app start `_loadConversations` is called alongside
        // `_loadWallet` from initState; launching a second compute()
        // isolate into the Go/FFI dylib while `_loadWallet`'s isolate is
        // still negotiating its first RPC call was starving the wallet
        // balance path and leaving the card stuck at 0 MOR / 0 ETH for
        // ~45 s (one full idle-refresh cycle). The staked-MOR suffix is
        // a nice-to-have decoration on the card; the liquid balance is
        // the primary signal. We compute the stake sum only after
        // [_loadWallet] has completed once (see [_loadWallet]) and on
        // the periodic idle refresh — this restores the pre-staked-MOR
        // startup behavior byte-for-byte while still surfacing the
        // staked amount within a few seconds of launch.
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _historyConvos = [];
          _activeResumeChats = [];
          _activeStakeWei = '0';
        });
      }
    }
  }

  /// Sum the on-chain stakes of the locally-known open sessions for the
  /// "(X.XX Staked)" figure on the wallet card. One targeted `getSession`
  /// eth_call per session — bounded by the 12-row cap in [_loadConversations]
  /// — so this runs happily on idle refreshes and didPopNext without blocking
  /// the UI. Off-device sessions aren't counted; the Wallet → "Where's My
  /// MOR?" scan remains the source of truth.
  Future<void> _computeActiveStake(List<Map<String, dynamic>> active) async {
    final runId = ++_activeStakeComputationId;
    if (active.isEmpty) {
      if (!mounted || runId != _activeStakeComputationId) return;
      setState(() => _activeStakeWei = '0');
      return;
    }
    final ids = <String>[];
    for (final c in active) {
      final sid = c['session_id'];
      if (sid is String && sid.isNotEmpty) ids.add(sid);
    }
    // Off-isolate: the underlying Go call iterates active sessions and
    // hits `getSessionData()` per ID, which is an RPC read and can block
    // for seconds on a slow endpoint. Running this inline on the UI
    // isolate freezes frames for that duration. The runId guard above
    // handles isolates returning out-of-order.
    try {
      final result = await compute(_sumActiveSessionStakesSync, ids);
      if (!mounted || runId != _activeStakeComputationId) return;
      final wei = result['stake_wei'] as String? ?? '0';
      setState(() => _activeStakeWei = wei);
    } catch (_) {
      // Keep the previous value on transient failure so the card doesn't
      // flicker between "X staked" and "(unknown)".
    }
  }

  String _relativeUpdated(Map<String, dynamic> c) {
    final u = (c['updated_at'] as num?)?.toInt();
    if (u == null) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(u * 1000);
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${t.month}/${t.day}';
  }

  /// True when either balance is literally zero. We stopped gating on a
  /// "recommended watermark" (5 MOR / 0.001 ETH) because the affordability
  /// filter + Show all toggle on the model list already protect the user
  /// from picking something they can't afford. The overlay is now only for
  /// the "literally nothing in the wallet" case where no chat can start.
  bool get _walletEmpty {
    final eth = BigInt.tryParse(_rawEthWei) ?? BigInt.zero;
    final mor = BigInt.tryParse(_rawMorWei) ?? BigInt.zero;
    return eth == BigInt.zero || mor == BigInt.zero;
  }

  bool get _morZero =>
      (BigInt.tryParse(_rawMorWei) ?? BigInt.zero) == BigInt.zero;
  bool get _ethZero =>
      (BigInt.tryParse(_rawEthWei) ?? BigInt.zero) == BigInt.zero;

  Future<void> _loadWallet() async {
    // Wrapped in compute() so that the synchronous FFI → Go →
    // `client.GetBalance()` RPC round trip runs off the UI isolate. On
    // slow RPC responses (or cold-start, first-hop failover) this call
    // can block for several seconds — running it inline freezes the
    // whole UI for that duration, which makes the wallet card appear
    // stuck at the default "0" placeholder until the 45 s idle timer
    // fires a second fetch. The background isolate keeps frames flowing.
    try {
      final summary = await compute(
        (_) => GoBridge().getWalletSummary(),
        null,
      );
      if (!mounted) return;

      // `getWalletSummary` on the Go side returns "eth_balance":"0",
      // "mor_balance":"0" along with a non-empty "error" field when the
      // RPC round-trip fails (private-key load, getTransactOpts, or the
      // two BalanceAt calls). If we naively apply those zeros to state
      // we paint a confident "0.00000 MOR / 0.00000 ETH" — which also
      // trips the `_walletEmpty` overlay — for a wallet that is
      // actually healthy, just momentarily unreachable. Treat the error
      // case as transient: log it, keep the previously-rendered balance
      // (or the initial "—" placeholder), and let the 45 s idle timer
      // retry. This restores the pre-staked-MOR "fast paint" feel while
      // also making genuinely-flaky RPCs visible in the debug console.
      final errMsg = summary['error'];
      if (errMsg is String && errMsg.isNotEmpty) {
        debugPrint('[wallet] getWalletSummary error (keeping prior '
            'balance): $errMsg');
        setState(() {
          _address = summary['address'] as String? ?? _address;
        });
      } else {
        final rawEth = summary['eth_balance'] as String? ?? '0';
        final rawMor = summary['mor_balance'] as String? ?? '0';
        setState(() {
          _address = summary['address'] as String? ?? '';
          _rawEthWei = rawEth;
          _rawMorWei = rawMor;
          _ethBalance = formatWeiFixedDecimals(rawEth, _walletBalanceDecimals);
          _morBalance = formatWeiFixedDecimals(rawMor, _walletBalanceDecimals);
        });
      }

      // Now that the liquid wallet balance has painted (or we've logged
      // a retryable error above), it's safe to kick off the staked-MOR
      // scan in a second compute() isolate. Firing this here — instead
      // of from _loadConversations — guarantees the wallet balance
      // isolate has already returned before we start contending with it
      // for the Go/FFI dylib.
      if (_activeResumeChats.isNotEmpty) {
        unawaited(_computeActiveStake(_activeResumeChats));
      } else {
        _activeStakeWei = '0';
      }
    } catch (e) {
      debugPrint('[wallet] _loadWallet threw: $e');
    }
  }

  Future<void> _loadModels() async {
    // Only flip into the muted "loading" state on the very first load (when
    // we have no cached calibration yet). Subsequent refreshes preserve the
    // last known-good supply/budget so tiles don't flicker and — more
    // importantly — so the Show-all filter stays functional while we
    // re-fetch. If calibration below fails transiently (RPC blip, no bids
    // cached right this instant), we keep the old values so toggles remain
    // usable. See [_computeAffordability] for the matching preserve-on-fail
    // logic.
    final hasCalibration = _supplyWei != null && _budgetWei != null;
    setState(() {
      _loadingModels = true;
      _modelsError = null;
      if (!hasCalibration) {
        _affordabilityLoading = true;
        _affordabilityResolved = false;
      }
    });
    try {
      final resp = await fetchModelStatus();
      if (!mounted) return;
      var list = resp.models;
      if (_maxPrivacy) {
        list = list.where((m) => m.isTEE).toList();
      }
      _sortModelsAlpha(list);
      setState(() {
        _statusApi = resp;
        _models = list;
        _loadingModels = false;
      });
    } catch (e) {
      // Fallback: use Go bridge model list (less metadata but always works).
      try {
        final bridge = GoBridge();
        final raw = bridge.getActiveModels(teeOnly: _maxPrivacy);
        if (!mounted) return;
        final fallback = raw.map((m) {
          final map = m as Map<String, dynamic>;
          return ModelStatusEntry(
            id: map['id'] as String? ?? '',
            name: map['name'] as String? ?? 'Unknown',
            status: 'operational',
            type: (map['model_type'] as String? ?? 'LLM').toUpperCase(),
            tags: (map['tags'] as List<dynamic>?)?.cast<String>() ?? [],
            providers: 0,
            minPriceMorHr: 0,
          );
        }).toList();
        _sortModelsAlpha(fallback);
        setState(() {
          _statusApi = null;
          _models = fallback;
          _loadingModels = false;
        });
      } catch (fallbackErr) {
        if (!mounted) return;
        setState(() {
          _modelsError = fallbackErr.toString();
          _loadingModels = false;
        });
      }
    }
    unawaited(_computeAffordability());
  }

  /// Case-insensitive alpha sort on model name. Affordability does **not**
  /// affect ordering — unaffordable models are rendered muted in place so
  /// users can always find a known model by name without it jumping around
  /// as balances / default duration change.
  void _sortModelsAlpha(List<ModelStatusEntry> list) {
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Calibrate the stake formula once, cache the globals, and let per-model
  /// stake be derived on the fly via [_hourlyStakeWeiFor] / [_isAffordable].
  ///
  /// The Go estimator does a per-model `GetRatedBids` RPC round trip, so
  /// calling it N times is slow and scroll-hostile. But the formula is
  /// linear in `price_per_second`:
  ///
  ///     stake = (supply × price_per_second × duration) ÷ emissions_budget
  ///
  /// `supply` and `emissions_budget` are global; once we know them we can
  /// compute any model's stake locally using `min_price_mor_hr` (lowest bid
  /// across providers) from the status API response. One FFI call per home
  /// refresh, everything else is pure math, affordability re-renders
  /// automatically whenever the wallet balance changes.
  Future<void> _computeAffordability() async {
    final runId = ++_affordabilityComputationId;
    final seconds = await SessionDurationStore.instance.readSeconds();
    if (!mounted || runId != _affordabilityComputationId) return;

    final bridge = GoBridge();

    // Calibration: iterate until we get a model with bids + a valid
    // supply/budget. Transient RPC failures fall through to the next model.
    BigInt? supplyWei;
    BigInt? budgetWei;
    for (final m in _models) {
      if (m.id.isEmpty || m.type != 'LLM') continue;
      try {
        final est = bridge.estimateOpenSessionStake(
          m.id,
          seconds,
          directPayment: false,
        );
        final sup = BigInt.tryParse((est['mor_supply_wei'] as String?) ?? '');
        final bud =
            BigInt.tryParse((est['emissions_budget_wei'] as String?) ?? '');
        if (sup != null && bud != null && bud > BigInt.zero) {
          supplyWei = sup;
          budgetWei = bud;
          break;
        }
      } catch (_) {
        // Try the next model.
      }
      await Future<void>.delayed(Duration.zero);
      if (!mounted || runId != _affordabilityComputationId) return;
    }

    if (!mounted || runId != _affordabilityComputationId) return;
    setState(() {
      // Preserve previously-calibrated globals on transient failure so the
      // Show-all / affordability filter doesn't silently disable itself when
      // an RPC hiccup returns no usable bids for any sampled model. The
      // wallet balance is the only input that actually changes frame-to-
      // frame; the stake formula (supply / emissions_budget) is effectively
      // constant across a short window.
      if (supplyWei != null && budgetWei != null) {
        _supplyWei = supplyWei;
        _budgetWei = budgetWei;
      }
      _defaultDurationSeconds = seconds;
      _affordabilityLoading = false;
      _affordabilityResolved = _supplyWei != null && _budgetWei != null;
    });
  }

  /// Hourly stake (wei) for [m] using the cached globals.
  /// Returns null when globals are unknown or the model has no price (e.g.
  /// Go bridge fallback path). Cheap — pure BigInt math.
  BigInt? _hourlyStakeWeiFor(ModelStatusEntry m) {
    final supply = _supplyWei;
    final budget = _budgetWei;
    if (supply == null || budget == null || budget == BigInt.zero) return null;
    if (m.minPriceMorHr <= 0) return null;
    // price_per_hour (wei) = minPriceMorHr × 1e18
    // hourly stake       = supply × price_per_hour ÷ budget
    final priceWeiPerHour = BigInt.from((m.minPriceMorHr * 1e18).round());
    return (supply * priceWeiPerHour) ~/ budget;
  }

  /// Stake (wei) for [m] over [seconds]. Linear scaling from the hourly rate.
  BigInt? _stakeWeiFor(ModelStatusEntry m, int seconds) {
    final hourly = _hourlyStakeWeiFor(m);
    if (hourly == null) return null;
    return hourly * BigInt.from(seconds) ~/ BigInt.from(3600);
  }

  /// Label for the right side of the `MODELS` header row.
  ///
  /// The provider count from the status API is network-wide ("active
  /// providers") — it is only accurate for the **unfiltered** list. The API
  /// exposes only a count of providers per model, not provider IDs, so we
  /// can't dedupe across a subset to say "this TEE-only list is served by 2
  /// providers". Rather than lie, we drop the provider roll-up whenever any
  /// filter narrows the view and fall back to model counts.
  ///
  /// Priority:
  ///   1. `N of M affordable` — when the Show-all filter is hiding rows.
  ///   2. `N TEE models` — when Privacy is on (TEE subset).
  ///   3. `N across P providers` — full unfiltered list (provider count valid).
  ///   4. `N available` — when we're on the Go-bridge fallback (no API).
  String _modelsHeaderCountLabel() {
    if (_loadingModels) return 'loading...';
    final total = _models.length;
    final filterActive = _affordabilityResolved && !_showUnaffordable;
    if (filterActive) {
      final visible = _visibleModels().length;
      if (visible < total) {
        return _maxPrivacy
            ? '$visible of $total TEE affordable'
            : '$visible of $total affordable';
      }
    }
    if (_maxPrivacy) {
      return total == 1 ? '1 TEE model' : '$total TEE models';
    }
    if (_statusApi != null) {
      return '$total across ${_statusApi!.activeProviders} providers';
    }
    return '$total available';
  }

  /// The subset of `_models` that would render in the list right now, given
  /// the current Show-all toggle + calibration state. Kept as a single source
  /// of truth so the header count and the list stay in lock-step.
  ///
  /// When calibration has resolved and the user hasn't flipped Show-all on,
  /// hide unaffordable entries. While loading or when calibration failed,
  /// show everything (muted vs bright is handled by the tile itself).
  List<ModelStatusEntry> _visibleModels() {
    if (_affordabilityResolved && !_showUnaffordable) {
      return _models.where(_isAffordable).toList();
    }
    return _models;
  }

  /// Affordability verdict at render time. Optimistic when stake is unknown
  /// (Go fallback path models, missing calibration) so the tile stays
  /// tappable — the modal will do the authoritative check on tap.
  bool _isAffordable(ModelStatusEntry m) {
    final stake = _stakeWeiFor(m, _defaultDurationSeconds);
    if (stake == null) return true;
    final bal = BigInt.tryParse(_rawMorWei) ?? BigInt.zero;
    return bal >= stake;
  }

  /// "68.70 MOR/hr" style label for the tile. Falls back to the status API's
  /// provider rate when calibration hasn't resolved yet so tiles never
  /// render a naked nothing during the brief compute window.
  String? _hourlyStakeLabelFor(ModelStatusEntry m) {
    final hourly = _hourlyStakeWeiFor(m);
    if (hourly == null) {
      // Pre-calibration: show provider rate so tiles aren't bare. This is
      // the same number the status API exposes; once calibration lands,
      // we swap it for the honest hourly stake.
      if (m.minPriceMorHr <= 0) return null;
      if (m.minPriceMorHr < 0.001) return '<0.001 MOR/hr';
      if (m.minPriceMorHr < 0.01) {
        return '${m.minPriceMorHr.toStringAsFixed(4)} MOR/hr';
      }
      return '${m.minPriceMorHr.toStringAsFixed(2)} MOR/hr';
    }
    return '${formatWeiFixedDecimals(hourly.toString(), 2)} MOR/hr';
  }

  Future<void> _openModelChat(BuildContext context, ModelStatusEntry m) async {
    if (m.type != 'LLM') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Chat is only for LLM models (this one is ${m.type}).'),
        ),
      );
      return;
    }
    if (m.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Model has no id — cannot open session.')),
      );
      return;
    }
    final id = m.id;
    final name = m.name;
    final tags = m.tags;
    final isTEE = tags.any((t) => t.toUpperCase().contains('TEE'));

    // Pre-chat confirmation: model + duration + stake preview. We pass the
    // hourly stake we already computed on the home screen so the modal's
    // numbers match the tile's label by construction (lowest-price bid ×
    // supply ÷ budget), and so there's zero additional FFI on tap.
    final navigator = Navigator.of(context);
    final decision = await showSessionConfirmation(
      context: context,
      modelId: id,
      modelName: name,
      modelType: m.type,
      isTEE: isTEE,
      hourlyStakeWei: _hourlyStakeWeiFor(m),
      walletMorWei: BigInt.tryParse(_rawMorWei) ?? BigInt.zero,
      initialDurationSeconds: _defaultDurationSeconds,
    );
    if (decision == null || !mounted) return;

    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          modelId: id,
          modelName: name,
          isTEE: isTEE,
          sessionDurationSecondsOverride: decision.durationSeconds,
        ),
      ),
    );
    if (mounted) {
      _loadWallet();
      _loadConversations();
    }
  }

  void _openResumeChat(BuildContext context, Map<String, dynamic> c) {
    final id = c['id'] as String? ?? '';
    final mid = c['model_id'] as String? ?? '';
    final name = c['model_name'] as String? ?? 'Chat';
    final sid = c['session_id'] as String? ?? '';
    final isTee = c['is_tee'] == true;
    if (id.isEmpty || mid.isEmpty || sid.isEmpty) return;
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ChatScreen(
              modelId: mid,
              modelName: name,
              isTEE: isTee,
              resumeConversationId: id,
              resumeSessionId: sid,
            ),
          ),
        )
        .then((_) {
          if (mounted) {
            _loadWallet();
            _loadConversations();
          }
        });
  }

  void _openTranscript(BuildContext context, Map<String, dynamic> c) {
    final id = c['id'] as String? ?? '';
    final mid = c['model_id'] as String? ?? '';
    final name = c['model_name'] as String? ?? 'Chat';
    final isTee = c['is_tee'] == true;
    final sid = c['session_id'] as String? ?? '';
    if (id.isEmpty) return;
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ConversationTranscriptScreen(
              conversationId: id,
              modelId: mid,
              modelName: name,
              isTEE: isTee,
              onChainSessionId: sid.trim().isEmpty ? null : sid.trim(),
            ),
          ),
        )
        .then((_) {
          if (mounted) _loadConversations();
        });
  }

  Future<void> _confirmDeleteConversation(
    BuildContext context,
    Map<String, dynamic> c,
  ) async {
    final id = c['id'] as String? ?? '';
    if (id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
          'Removes this thread from this device and submits an on-chain close if a session is still open '
          '(same as close — stake returns per contract rules). If the network refuses the close, the thread '
          'is still removed locally and you can retry from Settings > Wallet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final res = GoBridge().deleteConversation(id);
      _loadConversations();
      final warn = res['close_warning'] as String?;
      if (context.mounted && warn != null && warn.trim().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Conversation removed locally. On-chain close failed — check Wallet in Settings or retry.\n$warn',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _renameConversationDialog(
    BuildContext context,
    Map<String, dynamic> c,
  ) async {
    final id = c['id'] as String? ?? '';
    if (id.isEmpty) return;
    final ctrl = TextEditingController(text: conversationHeadline(c));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename thread'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Topic title',
            hintText: 'Shown in history — model stays in subtitle',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        GoBridge().setConversationTitle(
          conversationId: id,
          title: ctrl.text.trim(),
        );
        _loadConversations();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
  }

  void _togglePin(Map<String, dynamic> c) {
    final id = c['id'] as String? ?? '';
    if (id.isEmpty) return;
    try {
      final next = c['pinned'] != true;
      GoBridge().setConversationPinned(conversationId: id, pinned: next);
      _loadConversations();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Close on-chain session for this thread; Go clears SQLite session_id on success.
  Future<void> _closeOnChainSessionForConversation(
    BuildContext context,
    Map<String, dynamic> c,
  ) async {
    final sid = c['session_id'] as String? ?? '';
    if (sid.isEmpty) return;
    final ok = await confirmCloseOnChainSession(context);
    if (ok != true || !mounted || !context.mounted) return;
    try {
      await runCloseOnChainSessionFlow(context, sid);
      if (!mounted) return;
      _loadConversations();
      // Stake is returned to the wallet on close — refresh so affordability
      // verdicts reflect the restored balance without waiting for the idle
      // tick or a full route pop.
      _loadWallet();
    } on GoBridgeException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _onSettingsTap(BuildContext context, String key) async {
    Navigator.of(context).pop(); // close the drawer first
    if (key == 'sessions') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const SessionsScreen(),
        ),
      );
    } else if (key == 'wallet') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const WalletScreen(),
        ),
      );
    } else if (key == 'expert') {
      final rpcChanged = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => const ExpertScreen(),
        ),
      );
      if (rpcChanged == true) {
        await widget.onRpcChanged?.call();
      }
    } else if (key == 'backup') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => BackupResetScreen(
            onWalletErased: widget.onWalletErased,
            onFactoryReset: widget.onFactoryReset,
          ),
        ),
      );
    } else if (key == 'about') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const AboutScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      drawer: _HistoryChatsDrawer(
        theme: theme,
        conversations: _historyConvos,
        onOpenTranscript: (c) => _openTranscript(context, c),
        onCloseActiveSession: (c) =>
            _closeOnChainSessionForConversation(context, c),
        onDeleteConversation: (c) => _confirmDeleteConversation(context, c),
        onRename: (c) => _renameConversationDialog(context, c),
        onTogglePin: _togglePin,
        relativeTime: _relativeUpdated,
      ),
      endDrawer: _SettingsDrawer(
        theme: theme,
        onTap: (key) => _onSettingsTap(context, key),
      ),
      appBar: AppBar(
        automaticallyImplyLeading: true,
        toolbarHeight: 72,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/branding/wordmark_v2.png',
              height: 36,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 2),
            Text(
              AppBrand.tagline,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.0,
                color: NeoTheme.emerald.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
        actions: [
          if (PlatformCaps.isDesktop)
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh, size: 22),
              onPressed: () {
                _loadWallet();
                _loadModels();
                _loadConversations();
              },
            ),
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.more_horiz, size: 24),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: NeoTheme.green,
          onRefresh: () async {
            _loadWallet();
            _loadModels();
            _loadConversations();
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _WalletCard(
                        fullAddress: _address,
                        ethBalance: _ethBalance,
                        morBalance: _morBalance,
                        activeStakeWei: _activeStakeWei,
                        rpcChecking: _rpcChecking,
                        rpcReachable: _rpcReachable,
                        onOpenExpert: () async {
                          final rpcChanged = await Navigator.of(context).push<bool>(
                            MaterialPageRoute<bool>(
                              builder: (_) => const ExpertScreen(),
                            ),
                          );
                          if (rpcChanged == true) {
                            await widget.onRpcChanged?.call();
                          }
                        },
                        onSendMor: () {
                          showSendTokenSheet(
                            context,
                            sendMor: true,
                            onSent: () {
                              if (mounted) _loadWallet();
                            },
                          );
                        },
                        onSendEth: () {
                          showSendTokenSheet(
                            context,
                            sendMor: false,
                            onSent: () {
                              if (mounted) _loadWallet();
                            },
                          );
                        },
                        onOpenWheresMyMor: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const WalletScreen(autoRunScan: true),
                            ),
                          );
                          // Returning from the wallet screen may have
                          // closed expired sessions or reshuffled state;
                          // refresh so the card reflects reality.
                          if (mounted) {
                            _loadWallet();
                            _loadConversations();
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),

              // Resume chats: render above the models section *regardless*
              // of wallet balance — an existing on-chain session already has
              // its stake locked, so a user with a near-empty wallet can
              // still reopen and finish their chat. Only the model list
              // below gets masked by the empty-wallet overlay.
              if (_activeResumeChats.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildResumeChatsSection(context, theme),
                ),

              if (_walletEmpty) ...[
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _FundWalletOverlay(
                    address: _address,
                    morMissing: _morZero,
                    ethMissing: _ethZero,
                    hasActiveChats: _activeResumeChats.isNotEmpty,
                  ),
                ),
              ] else ...[
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _PrivacyToggle(
                              enabled: _maxPrivacy,
                              onChanged: (val) {
                                setState(() => _maxPrivacy = val);
                                _loadModels();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ShowAllToggle(
                              enabled: _showUnaffordable,
                              onChanged: (val) =>
                                  setState(() => _showUnaffordable = val),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('MODELS', style: theme.textTheme.labelSmall),
                          Text(
                            _modelsHeaderCountLabel(),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 16,
                            color: NeoTheme.green.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'START A NEW CHAT by selecting a model',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: NeoTheme.green.withValues(alpha: 0.85),
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                          if (_statusApi != null)
                            Tooltip(
                              message: 'Border color shows 6-hour availability:\nGreen ≥ 99%  ·  Yellow ≥ 85%  ·  Red < 85%',
                              preferBelow: false,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.monitor_heart_outlined, size: 12, color: theme.hintColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Availability',
                                    style: TextStyle(fontSize: 10, color: theme.hintColor, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                SliverFillRemaining(
                  hasScrollBody: true,
                  child: _buildModelList(),
                ),
              ],
            ],
          ),
        ),
        ),
        ),
      ),
    );
  }

  /// "Continue chatting" section: rendered above the models list
  /// regardless of wallet balance so users with an active on-chain session
  /// can always reach/resume their chat. Stake for an open session is
  /// already locked in the diamond — no new MOR is needed to reopen it.
  Widget _buildResumeChatsSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              Icons.forum_outlined,
              size: 16,
              color: NeoTheme.green.withValues(alpha: 0.9),
            ),
            const SizedBox(width: 8),
            Text(
              'CONTINUE CHATTING',
              style: theme.textTheme.labelSmall?.copyWith(
                color: NeoTheme.green.withValues(alpha: 0.85),
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Tap to resume. Use ✕ to close on-chain (same as reclaim flow).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.hintColor,
            fontSize: 11,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _activeResumeChats.length,
          separatorBuilder: (context, i) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final c = _activeResumeChats[i];
            final name = conversationHeadline(c);
            final tee = c['is_tee'] == true;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openResumeChat(context, c),
                child: Ink(
                  decoration: BoxDecoration(
                    color: NeoTheme.mainPanelFill,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: NeoTheme.mainPanelOutline()),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Close on-chain session',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          icon: Icon(
                            Icons.close_rounded,
                            size: 22,
                            color: Colors.red.shade400,
                          ),
                          onPressed: () =>
                              _closeOnChainSessionForConversation(context, c),
                        ),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: tee
                                ? NeoTheme.green.withValues(alpha: 0.18)
                                : NeoTheme.mainPanelFill,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: tee
                                  ? NeoTheme.green.withValues(alpha: 0.35)
                                  : const Color(0xFF374151),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              tee ? '🛡️' : '💬',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                conversationMetaLine(c, _relativeUpdated),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF6B7280),
                                  fontSize: 10,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: theme.hintColor,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildModelList() {
    if (_loadingModels) {
      return const Center(
        child: CircularProgressIndicator(color: NeoTheme.green),
      );
    }
    if (_modelsError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              'Could not load models',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _modelsError!,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (_models.isEmpty) {
      return _EmptyState(maxPrivacy: _maxPrivacy);
    }
    final visible = _visibleModels();
    if (visible.isEmpty) {
      return _NoAffordableState(
        onShowAll: () => setState(() => _showUnaffordable = true),
      );
    }
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (ctx, i) {
        final m = visible[i];
        final bool affordable;
        if (_affordabilityLoading) {
          affordable = false; // loading cue — tile renders muted
        } else if (!_affordabilityResolved) {
          affordable = true; // calibration failed — don't mislead
        } else {
          affordable = _isAffordable(m);
        }
        return _ModelTile(
          entry: m,
          affordable: affordable,
          priceLabel: _hourlyStakeLabelFor(m),
          onTap: () => _openModelChat(ctx, m),
        );
      },
    );
  }
}

// --- MAX Privacy Toggle ---

class _PrivacyToggle extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _PrivacyToggle({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => onChanged(!enabled),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  enabled ? '🛡️' : '🛡️',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    enabled ? 'PRIVACY' : 'Privacy',
                    overflow: TextOverflow.fade,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color:
                          enabled ? NeoTheme.green : const Color(0xFF9CA3AF),
                      fontSize: 11,
                      fontWeight:
                          enabled ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => launchUrl(
              Uri.parse('https://tech.mor.org/tee.html'),
              mode: LaunchMode.externalApplication,
            ),
            child: Icon(
              Icons.info_outline_rounded,
              size: 14,
              color: NeoTheme.green.withValues(alpha: enabled ? 0.7 : 0.4),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => onChanged(!enabled),
            child: _AnimatedToggleSwitch(enabled: enabled, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

/// Show-unaffordable toggle. Off (default) filters unaffordable models out
/// of the list so the user only sees what they can start right now; on
/// shows everything alphabetical, with unaffordable rows rendered muted in
/// place. Lives next to [_PrivacyToggle] on the models header row.
class _ShowAllToggle extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ShowAllToggle({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => onChanged(!enabled),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  enabled
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_outlined,
                  size: 14,
                  color: enabled
                      ? NeoTheme.green
                      : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    enabled ? 'SHOW ALL' : 'Show all',
                    overflow: TextOverflow.fade,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color:
                          enabled ? NeoTheme.green : const Color(0xFF9CA3AF),
                      fontSize: 11,
                      fontWeight:
                          enabled ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => onChanged(!enabled),
            child:
                _AnimatedToggleSwitch(enabled: enabled, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

class _AnimatedToggleSwitch extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _AnimatedToggleSwitch({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!enabled),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 48,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: enabled ? NeoTheme.green : const Color(0xFF374151),
          borderRadius: BorderRadius.circular(14),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Empty state ---

/// Shown when the "show only affordable" filter hides every model — the
/// user has models loaded but none are affordable at the current default
/// session duration. Offers a direct way back to the full list.
class _NoAffordableState extends StatelessWidget {
  final VoidCallback onShowAll;
  const _NoAffordableState({required this.onShowAll});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('💤', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            const Text(
              'Nothing affordable right now',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Your MOR balance is below every model’s stake for the '
              'current default session length. Add MOR, shorten the '
              'default session in Preferences, or show the full list.',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 12, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onShowAll,
              icon: const Icon(Icons.visibility_rounded, size: 16),
              label: const Text('Show all models'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool maxPrivacy;
  const _EmptyState({required this.maxPrivacy});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(maxPrivacy ? '🛡️' : '📡', style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            maxPrivacy
                ? 'No MAX Security providers available'
                : 'No models available',
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            maxPrivacy
                ? 'Try disabling MAX Privacy to see all providers'
                : 'Check your network connection',
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// --- Fund Wallet Overlay ---

class _FundWalletOverlay extends StatelessWidget {
  final String address;

  /// Wallet has zero MOR — can't stake for a new session.
  final bool morMissing;

  /// Wallet has zero ETH — can't pay gas on Base.
  final bool ethMissing;

  /// When true, an on-chain session is still open; the overlay mentions
  /// that those chats are unaffected and resumable above.
  final bool hasActiveChats;

  const _FundWalletOverlay({
    required this.address,
    required this.morMissing,
    required this.ethMissing,
    this.hasActiveChats = false,
  });

  /// Title + supporting text, tailored to which balance is empty.
  /// Existing sessions can continue regardless of balance; the copy calls
  /// that out when relevant so the overlay doesn't feel like a dead end.
  ({String title, String body}) _copy() {
    if (morMissing && ethMissing) {
      return (
        title: 'Your wallet is empty',
        body: 'Add MOR (stake for inference) and ETH (gas on Base) '
            'to this address to start a new chat.',
      );
    }
    if (morMissing) {
      return (
        title: 'No MOR in your wallet',
        body: 'Add MOR to this address so you can stake for a new '
            'inference session.',
      );
    }
    return (
      title: 'No ETH in your wallet',
      body: 'Add a small amount of ETH (Base) to this address to '
          'cover on-chain gas.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copy = _copy();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          decoration: BoxDecoration(
            color: NeoTheme.mainPanelFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: NeoTheme.amber.withValues(alpha: 0.35),
              width: 1.3,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NeoTheme.amber.withValues(alpha: 0.10),
                  border: Border.all(
                    color: NeoTheme.amber.withValues(alpha: 0.30),
                    width: 1.5,
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.account_balance_wallet_outlined,
                      size: 28, color: NeoTheme.amber),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                copy.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: NeoTheme.amber,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                copy.body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF9CA3AF),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF374151)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        address.isEmpty ? '—' : address,
                        style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 11,
                          color: Color(0xFFF9FAFB),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Copy address',
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(36, 36),
                        padding: const EdgeInsets.all(6),
                      ),
                      onPressed: address.isEmpty
                          ? null
                          : () {
                              Clipboard.setData(ClipboardData(text: address));
                              ScaffoldMessenger.of(context)
                                ..clearSnackBars()
                                ..showSnackBar(
                                  const SnackBar(
                                    content: Text('Wallet address copied'),
                                    behavior: SnackBarBehavior.floating,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                            },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                hasActiveChats
                    ? 'Active chats above keep working. Models will appear '
                        'once funds arrive — pull to refresh.'
                    : 'Models will appear here once funds arrive. Pull to '
                        'refresh or tap ⋯ → Refresh.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6B7280),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Wallet Card ---

class _WalletCard extends StatefulWidget {
  final String fullAddress;
  final String ethBalance;
  final String morBalance;

  /// Sum of on-chain stake (in wei, as a decimal string) across the user's
  /// locally-known open sessions. `null` means "not yet computed" — the UI
  /// simply omits the `(X.XX Staked)` suffix instead of showing a zero that
  /// could be misleading. Set to `"0"` explicitly when the scan finishes
  /// with nothing staked.
  final String? activeStakeWei;
  final bool rpcChecking;
  final bool? rpcReachable;
  final Future<void> Function()? onOpenExpert;
  final VoidCallback onSendMor;
  final VoidCallback onSendEth;

  /// Jumps to Wallet → "Where's My MOR?" with the scan auto-running.
  final VoidCallback? onOpenWheresMyMor;

  const _WalletCard({
    required this.fullAddress,
    required this.ethBalance,
    required this.morBalance,
    required this.activeStakeWei,
    required this.rpcChecking,
    required this.rpcReachable,
    required this.onOpenExpert,
    required this.onSendMor,
    required this.onSendEth,
    required this.onOpenWheresMyMor,
  });

  static String _shorten(String addr) {
    if (addr.length < 12) return addr;
    return '${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}';
  }

  /// Purple accent used for "Active (Staked)" everywhere (home card +
  /// Wallet → Where's My MOR). Matches the `Color(0xFFA855F7)` used in the
  /// Wallet screen's `_morBucket`.
  static const Color stakedAccent = Color(0xFFA855F7);

  /// Returns the formatted "(X.XX Staked)" suffix for the supplied wei
  /// string, or `null` if there's nothing to show (unresolved or zero).
  /// Kept on the widget so both the collapsed header and the expanded
  /// balance chip stay in sync.
  static String? formatStakedSuffix(String? activeStakeWei) {
    if (activeStakeWei == null) return null;
    final wei = BigInt.tryParse(activeStakeWei);
    if (wei == null || wei == BigInt.zero) return null;
    return formatWeiFixedDecimals(activeStakeWei, 2);
  }

  @override
  State<_WalletCard> createState() => _WalletCardState();
}

class _WalletCardState extends State<_WalletCard>
    with SingleTickerProviderStateMixin {
  static const double _tokenVisualSize = 44;

  late bool _expanded;
  late AnimationController _ctrl;
  late Animation<double> _heightFactor;

  @override
  void initState() {
    super.initState();
    _expanded = false;
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
      value: _expanded ? 1.0 : 0.0,
    );
    _heightFactor = _ctrl.drive(CurveTween(curve: Curves.easeInOut));
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final addressStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'JetBrains Mono',
      letterSpacing: 0.35,
      fontSize: 13,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.92),
    ) ?? const TextStyle(fontSize: 13);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, expandedBody) {
        return Card(
          color: NeoTheme.mainPanelFill,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: NeoTheme.mainPanelOutline(), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header — always visible, tappable to toggle
              InkWell(
                onTap: _toggle,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  // Asymmetric horizontal padding: the copy IconButton on
                  // the left already contributes ~6px of its own padding, and
                  // the chevron on the right is small and low-contrast. A
                  // smaller right inset keeps the ETH balance from looking
                  // stranded against the card edge without cramping the copy
                  // button.
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Copy full address',
                        icon: Icon(
                          Icons.copy_rounded,
                          size: 18,
                          color: widget.fullAddress.isEmpty
                              ? theme.disabledColor
                              : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(32, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.all(4),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: widget.fullAddress.isEmpty
                            ? null
                            : () {
                                Clipboard.setData(ClipboardData(text: widget.fullAddress));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Wallet address copied'),
                                    behavior: SnackBarBehavior.floating,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                      ),
                      // Address: a truncated "0x…" is always short (13
                      // chars after _shorten), so we let it claim its
                      // natural width instead of sharing a flex slot with
                      // the balances. That means the balance Wrap below
                      // gets ALL the remaining row width to fill, and
                      // WrapAlignment.end can push content to the right
                      // edge with no "unused flex slot" gap in the middle.
                      Text(
                        widget.fullAddress.isEmpty
                            ? '—'
                            : _WalletCard._shorten(widget.fullAddress),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: addressStyle.copyWith(fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      // Balance cluster takes ALL remaining width via
                      // Expanded (== Flexible flex:1 tight). Wrap fills
                      // that full width and WrapAlignment.end pins
                      // MOR / staked / ETH flush-right against the
                      // chevron. On narrow widths the cluster waterfalls
                      // onto a second line, still right-aligned — each
                      // value+unit pair is atomic (_BalanceInline) so a
                      // break only happens between pairs, not mid-number.
                      Expanded(
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 2,
                          children: [
                            _BalanceInline(
                              value: widget.morBalance,
                              unit: 'MOR',
                              valueColor: NeoTheme.green.withValues(alpha: 0.9),
                              unitColor: NeoTheme.green.withValues(alpha: 0.6),
                            ),
                            if (_WalletCard.formatStakedSuffix(
                                    widget.activeStakeWei) !=
                                null)
                              Text(
                                '(+${_WalletCard.formatStakedSuffix(widget.activeStakeWei)} staked)',
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: _WalletCard.stakedAccent
                                      .withValues(alpha: 0.75),
                                ),
                              ),
                            _BalanceInline(
                              value: widget.ethBalance,
                              unit: 'ETH',
                              valueColor:
                                  NeoTheme.ethBlue.withValues(alpha: 0.9),
                              unitColor:
                                  NeoTheme.ethBlue.withValues(alpha: 0.6),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 2),
                      RotationTransition(
                        turns: _ctrl.drive(
                          Tween<double>(begin: 0.0, end: 0.5)
                              .chain(CurveTween(curve: Curves.easeInOut)),
                        ),
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: NeoTheme.platinum.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Expanded body — animated
              ClipRect(
                child: Align(
                  heightFactor: _heightFactor.value,
                  alignment: Alignment.topCenter,
                  child: expandedBody,
                ),
              ),
            ],
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status row: previously duplicated the full wallet address here
            // (which is already shown — ellipsized — in the collapsed header).
            // We now use this slot purely for the two status pills: the new
            // purple "Where's My MOR?" deep-link and the existing RPC pill.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (widget.onOpenWheresMyMor != null)
                  _WheresMyMorPill(onTap: widget.onOpenWheresMyMor!),
                const Spacer(),
                Tooltip(
                  message: widget.rpcChecking
                      ? 'Checking whether your Base RPC URL(s) respond...'
                      : widget.rpcReachable == true
                          ? 'At least one configured Base RPC URL is reachable (same list the app uses).'
                          : 'No configured Base RPC URL responded. Tap to open Expert settings.',
                  child: _WalletRpcStatusPill(
                    rpcChecking: widget.rpcChecking,
                    rpcReachable: widget.rpcReachable,
                    onOpenExpert: widget.onOpenExpert,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Click a balance to send',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.hintColor,
                fontSize: 10,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _BalanceChip(
                    expand: true,
                    symbol: NetworkTokens.morSymbol,
                    value: widget.morBalance,
                    color: NeoTheme.green,
                    helperText: AppBrand.morBalanceHelper,
                    stakedSuffix: _WalletCard.formatStakedSuffix(widget.activeStakeWei),
                    stakedColor: _WalletCard.stakedAccent,
                    onTap: widget.onSendMor,
                    token: TokenWithBaseInlay(
                      token: MorTokenIcon(size: _tokenVisualSize),
                      diameter: _tokenVisualSize,
                      badgeDiameter: 17,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BalanceChip(
                    expand: true,
                    symbol: NetworkTokens.ethSymbol,
                    value: widget.ethBalance,
                    color: NeoTheme.ethBlue,
                    helperText: AppBrand.ethBalanceHelper,
                    onTap: widget.onSendEth,
                    token: TokenWithBaseInlay(
                      token: EthTokenIcon(size: _tokenVisualSize),
                      diameter: _tokenVisualSize,
                      badgeDiameter: 17,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Purple pill that deep-links into Wallet → "Where's My MOR?" with the
/// scan auto-running. Styled to match the `_WalletRpcStatusPill` it sits
/// next to in the expanded wallet card.
class _WheresMyMorPill extends StatelessWidget {
  final VoidCallback onTap;

  const _WheresMyMorPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accent = _WalletCard.stakedAccent;
    return Tooltip(
      message: 'Scan the chain for your MOR across wallet, active stakes, and on-hold.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: NeoTheme.mainPanelFill,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_rounded, size: 11, color: accent),
                const SizedBox(width: 4),
                Text(
                  "WHERE'S MY MOR?",
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Drawer: local SQLite chat history (on-chain open/close + close action inline).
class _HistoryChatsDrawer extends StatelessWidget {
  final ThemeData theme;
  final List<Map<String, dynamic>> conversations;
  final void Function(Map<String, dynamic> c) onOpenTranscript;
  final void Function(Map<String, dynamic> c) onCloseActiveSession;
  final void Function(Map<String, dynamic> c) onDeleteConversation;
  final void Function(Map<String, dynamic> c) onRename;
  final void Function(Map<String, dynamic> c) onTogglePin;
  final String Function(Map<String, dynamic> c) relativeTime;

  const _HistoryChatsDrawer({
    required this.theme,
    required this.conversations,
    required this.onOpenTranscript,
    required this.onCloseActiveSession,
    required this.onDeleteConversation,
    required this.onRename,
    required this.onTogglePin,
    required this.relativeTime,
  });

  @override
  Widget build(BuildContext context) {
    final drawerWidth = min(420.0, MediaQuery.sizeOf(context).width * 0.92);
    return Drawer(
      width: drawerWidth,
      backgroundColor: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DrawerHeader(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chats & Sessions',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap a row to open history. Swipe right to pin · swipe left for close session (if open) or delete. '
                    'Rename with the pencil.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                'LOCAL HISTORY',
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.8,
                  color: theme.hintColor,
                ),
              ),
            ),
            Expanded(
              child: conversations.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No saved conversations yet.\nOpen a model to start chatting.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
                            height: 1.4,
                          ),
                        ),
                      ),
                    )
                  : _HistoryConversationList(
                      theme: theme,
                      conversations: conversations,
                      onOpenTranscript: onOpenTranscript,
                      onCloseActiveSession: onCloseActiveSession,
                      onDeleteConversation: onDeleteConversation,
                      onRename: onRename,
                      onTogglePin: onTogglePin,
                      relativeTime: relativeTime,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single list: pinned rows first (SQLite order), pin icon only — no section headers.
class _HistoryConversationList extends StatelessWidget {
  final ThemeData theme;
  final List<Map<String, dynamic>> conversations;
  final void Function(Map<String, dynamic> c) onOpenTranscript;
  final void Function(Map<String, dynamic> c) onCloseActiveSession;
  final void Function(Map<String, dynamic> c) onDeleteConversation;
  final void Function(Map<String, dynamic> c) onRename;
  final void Function(Map<String, dynamic> c) onTogglePin;
  final String Function(Map<String, dynamic> c) relativeTime;

  const _HistoryConversationList({
    required this.theme,
    required this.conversations,
    required this.onOpenTranscript,
    required this.onCloseActiveSession,
    required this.onDeleteConversation,
    required this.onRename,
    required this.onTogglePin,
    required this.relativeTime,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      itemCount: conversations.length,
      separatorBuilder: (context, index) =>
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.35)),
      itemBuilder: (ctx, i) {
        final c = conversations[i];
        return _HistoryConversationTile(
          theme: theme,
          c: c,
          onOpenTranscript: onOpenTranscript,
          onCloseActiveSession: onCloseActiveSession,
          onDeleteConversation: onDeleteConversation,
          onRename: onRename,
          onTogglePin: onTogglePin,
          relativeTime: relativeTime,
        );
      },
    );
  }
}

class _HistoryConversationTile extends StatelessWidget {
  const _HistoryConversationTile({
    required this.theme,
    required this.c,
    required this.onOpenTranscript,
    required this.onCloseActiveSession,
    required this.onDeleteConversation,
    required this.onRename,
    required this.onTogglePin,
    required this.relativeTime,
  });

  final ThemeData theme;
  final Map<String, dynamic> c;
  final void Function(Map<String, dynamic> c) onOpenTranscript;
  final void Function(Map<String, dynamic> c) onCloseActiveSession;
  final void Function(Map<String, dynamic> c) onDeleteConversation;
  final void Function(Map<String, dynamic> c) onRename;
  final void Function(Map<String, dynamic> c) onTogglePin;
  final String Function(Map<String, dynamic> c) relativeTime;

  @override
  Widget build(BuildContext context) {
    final headline = conversationHeadline(c);
    final cid = c['id'] as String? ?? '';
    final sid = c['session_id'];
    final hasSession = sid is String && sid.isNotEmpty;
    final isPinned = c['pinned'] == true;
    final showPinIcon = isPinned;
    final isTee = c['is_tee'] == true;
    final isApi = c['source'] == 'api';
    return Slidable(
      key: ValueKey('drawer-$cid'),
      groupTag: 'history-drawer',
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.22,
        children: [
          SlidableAction(
            onPressed: (_) => onTogglePin(c),
            backgroundColor: Colors.amber.shade800,
            foregroundColor: Colors.white,
            icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            label: isPinned ? 'Unpin' : 'Pin',
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: hasSession ? 0.44 : 0.22,
        children: [
          if (hasSession)
            SlidableAction(
              onPressed: (_) => onCloseActiveSession(c),
              backgroundColor: const Color(0xFFEA580C),
              foregroundColor: Colors.white,
              icon: Icons.link_off_rounded,
              label: 'Close',
            ),
          SlidableAction(
            onPressed: (_) => onDeleteConversation(c),
            backgroundColor: Colors.red.shade800,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Icon(
          hasSession ? Icons.play_circle_outline : Icons.history,
          color: hasSession
              ? NeoTheme.green.withValues(alpha: 0.9)
              : theme.colorScheme.onSurface.withValues(alpha: 0.45),
        ),
        title: Row(
          children: [
            if (showPinIcon) ...[
              Icon(Icons.push_pin, size: 15, color: Colors.amber.shade600),
              const SizedBox(width: 6),
            ],
            if (isTee) ...[
              const Text('🛡️', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 5),
            ],
            if (isApi) ...[
              Icon(Icons.smart_toy_outlined, size: 15, color: NeoTheme.green.withValues(alpha: 0.7)),
              const SizedBox(width: 5),
            ],
            Expanded(
              child: Text(
                headline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            conversationMetaLine(c, relativeTime),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, height: 1.3),
          ),
        ),
        trailing: IconButton(
          tooltip: 'Rename topic',
          icon: Icon(Icons.edit_outlined, color: theme.hintColor, size: 22),
          onPressed: () => onRename(c),
        ),
        onTap: () {
          Navigator.pop(context);
          onOpenTranscript(c);
        },
      ),
    );
  }
}

/// JSON-RPC reachability for the same URL list [RpcSettingsStore.effectiveRpcUrl] uses (not a live socket to Go).
class _WalletRpcStatusPill extends StatelessWidget {
  final bool rpcChecking;
  final bool? rpcReachable;
  final Future<void> Function()? onOpenExpert;

  const _WalletRpcStatusPill({
    required this.rpcChecking,
    required this.rpcReachable,
    required this.onOpenExpert,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rpcChecking) {
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.hintColor,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'RPC…',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.hintColor,
                fontSize: 9,
              ),
            ),
          ],
        ),
      );
    }
    final ok = rpcReachable == true;
    final borderColor = ok
        ? NeoTheme.green.withValues(alpha: 0.35)
        : NeoTheme.red.withValues(alpha: 0.45);
    final bg = ok ? NeoTheme.mainPanelFill : const Color(0xFF1F1518);
    final fg = ok
        ? NeoTheme.green
        : NeoTheme.red.withValues(alpha: 0.95);
    final label = ok ? 'CONNECTED' : 'NO RPC';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: !ok && onOpenExpert != null
            ? () => onOpenExpert!()
            : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact "value + unit" pair used in the collapsed wallet card header.
///
/// Rendered as a single RichText so MOR / ETH / the staked hint can be laid
/// out in a Wrap — wrapping only happens *between* pairs, never mid-number
/// ("15.27929" will never be broken off from "MOR"). The value is the bold,
/// fully-opaque glyph; the unit follows in the same color at lower
/// opacity and slightly smaller size, matching the legacy two-Text design.
class _BalanceInline extends StatelessWidget {
  final String value;
  final String unit;
  final Color valueColor;
  final Color unitColor;

  const _BalanceInline({
    required this.value,
    required this.unit,
    required this.valueColor,
    required this.unitColor,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      text: TextSpan(children: [
        TextSpan(
          text: value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
        TextSpan(
          text: ' $unit',
          style: TextStyle(fontSize: 11, color: unitColor),
        ),
      ]),
    );
  }
}

class _BalanceChip extends StatelessWidget {
  final String symbol;
  final String value;
  final Color color;
  final String? helperText;
  final Widget token;
  final VoidCallback onTap;
  final bool expand;

  /// Optional secondary amount shown in [stakedColor] immediately after
  /// [value] — used for the MOR tile's "(X.XX Staked)" purple hint.
  /// Rendered with `Wrap` so it falls to the next line on narrow widths
  /// instead of ellipsizing the liquid balance.
  final String? stakedSuffix;
  final Color? stakedColor;

  const _BalanceChip({
    required this.symbol,
    required this.value,
    required this.color,
    required this.token,
    required this.onTap,
    this.helperText,
    this.expand = false,
    this.stakedSuffix,
    this.stakedColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoration = BoxDecoration(
      color: NeoTheme.mainPanelFill,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
    );
    final liquidStyle = TextStyle(
      color: color,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      fontFamily: 'JetBrains Mono',
    );
    final stakedStyle = TextStyle(
      color: stakedColor ?? color,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      fontFamily: 'JetBrains Mono',
    );
    // Liquid balance: wrapped in FittedBox(scaleDown) so values like
    // "0.01063" never get ellipsized to "0.010..." on narrow iPhone widths
    // where the chip column is ~70px wide — the text scales down one or
    // two percent instead, which is imperceptible and keeps the decimals
    // honest. Left-aligned inside FittedBox so the number stays flush with
    // the chip symbol above it.
    final Widget liquidValue = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(value, maxLines: 1, style: liquidStyle),
    );
    // When a staked suffix is present we use Wrap so '49.80986 MOR (110.24
    // Staked)' falls to a second line gracefully on narrow phones rather
    // than truncating the liquid balance. Each child is itself scale-safe
    // so neither the liquid balance nor the staked hint can overflow.
    final Widget amountWidget = stakedSuffix == null
        ? liquidValue
        : Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 6,
            runSpacing: 2,
            children: [
              liquidValue,
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('($stakedSuffix Staked)',
                    maxLines: 1, style: stakedStyle),
              ),
            ],
          );
    // Upper block: just the symbol header + amount(s). The helper text is
    // pulled OUT of this column so it can span the FULL chip width below
    // (not the narrow right-of-icon slot).
    final amountColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          symbol,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        amountWidget,
      ],
    );
    final Widget? helperRow =
        (helperText != null && helperText!.isNotEmpty)
            ? Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  helperText!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                    fontSize: 9,
                    height: 1.25,
                  ),
                ),
              )
            : null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          decoration: decoration,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize:
                      expand ? MainAxisSize.max : MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    token,
                    const SizedBox(width: 10),
                    if (expand)
                      Expanded(child: amountColumn)
                    else
                      Flexible(child: amountColumn),
                  ],
                ),
                if (helperRow != null) helperRow,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Model Tile ---

class _SettingsDrawer extends StatelessWidget {
  final ThemeData theme;
  final void Function(String key) onTap;

  const _SettingsDrawer({required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final drawerWidth = min(360.0, MediaQuery.sizeOf(context).width * 0.85);
    return Drawer(
      width: drawerWidth,
      backgroundColor: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DrawerHeader(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Settings',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Manage your preferences, wallet, network, and data.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _SettingsDrawerItem(
              icon: Icons.tune_rounded,
              title: 'Preferences',
              subtitle: 'Prompt · Tuning · Security',
              onTap: () => onTap('sessions'),
            ),
            _SettingsDrawerItem(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Wallet',
              subtitle: 'Keys · Sessions · Staked MOR',
              onTap: () => onTap('wallet'),
            ),
            _SettingsDrawerItem(
              icon: PlatformCaps.isMobile ? Icons.link_rounded : Icons.terminal,
              title: PlatformCaps.isMobile ? 'Network' : 'Expert Mode',
              subtitle: PlatformCaps.isMobile
                  ? 'Blockchain RPC'
                  : 'Network · API · Gateway',
              onTap: () => onTap('expert'),
            ),
            _SettingsDrawerItem(
              icon: Icons.backup_outlined,
              title: 'Backup & Reset',
              subtitle: 'Backup · Restore · Reset',
              onTap: () => onTap('backup'),
            ),
            _SettingsDrawerItem(
              icon: Icons.info_outline,
              title: 'Version & Logs',
              subtitle: 'About · Log viewer',
              onTap: () => onTap('about'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsDrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsDrawerItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 24, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: theme.hintColor.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  final ModelStatusEntry entry;
  final VoidCallback onTap;

  /// When false, the wallet cannot cover the on-chain stake for the
  /// current default session duration. The tile stays tappable (the
  /// confirmation modal lets the user pick a shorter duration) but is
  /// rendered muted so it clearly reads as "not ready to go".
  final bool affordable;

  /// Pre-formatted hourly stake label (e.g. `"68.70 MOR/hr"`). This is the
  /// number the user must **lock** per hour of chat — same formula the
  /// confirmation modal uses, so the tile and modal agree by construction.
  /// Parent passes null when the stake can't be computed (no price / no
  /// calibration) so the tile simply omits the label.
  final String? priceLabel;

  const _ModelTile({
    required this.entry,
    required this.onTap,
    this.affordable = true,
    this.priceLabel,
  });

  static Color _healthColor(double? pct) {
    if (pct == null) return NeoTheme.mainPanelOutline();
    if (pct >= 99.0) return NeoTheme.green;
    if (pct >= 85.0) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTEE = entry.isTEE;
    final price = priceLabel;
    final borderColor = _healthColor(entry.uptime6h);

    final card = Card(
      color: NeoTheme.mainPanelFill,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: affordable
              ? borderColor.withValues(alpha: 0.55)
              : borderColor.withValues(alpha: 0.22),
          width: 1.3,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // --- Icon ---
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: isTEE
                      ? NeoTheme.green.withValues(alpha: 0.18)
                      : NeoTheme.mainPanelFill,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: isTEE
                        ? NeoTheme.green.withValues(alpha: 0.35)
                        : const Color(0xFF374151),
                  ),
                ),
                child: Center(
                  child: Text(isTEE ? '🛡️' : '🤖', style: const TextStyle(fontSize: 14)),
                ),
              ),
              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.name,
                            style: theme.textTheme.titleMedium?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        if (price != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(price, style: TextStyle(fontSize: 10, color: theme.hintColor)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (entry.type.isNotEmpty)
                          Text(
                            entry.type,
                            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ...entry.tags
                            .where((t) => t.toLowerCase() != entry.type.toLowerCase())
                            .take(3)
                            .map((tag) => Padding(
                                  padding: const EdgeInsets.only(left: 5),
                                  child: Text(
                                    tag,
                                    style: TextStyle(
                                      color: tag.toLowerCase() == 'tee'
                                          ? NeoTheme.green.withValues(alpha: 0.7)
                                          : const Color(0xFF6B7280),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                )),
                        const Spacer(),
                        if (entry.providers > 0) ...[
                          Icon(Icons.dns_outlined, size: 11, color: theme.hintColor),
                          const SizedBox(width: 2),
                          Text(
                            '${entry.providers}',
                            style: TextStyle(fontSize: 10, color: theme.hintColor),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return affordable ? card : Opacity(opacity: 0.45, child: card);
  }
}

