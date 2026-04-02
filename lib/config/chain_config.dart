/// Build-time injected RPC URL (e.g. a premium Alchemy endpoint).
/// Pass via: flutter run --dart-define=ETH_RPC_URL=https://...
/// Empty/absent is fine — public RPCs are always appended as fallback.
const String _buildTimeRpc =
    String.fromEnvironment('ETH_RPC_URL', defaultValue: '');

/// Base mainnet defaults (no user RPC override).
///
/// Comma-separated HTTPS JSON-RPC URLs; Go SDK round-robins and retries.
/// If a build-time ETH_RPC_URL is provided it is prepended so it's tried first.
/// Keep in sync with `.ai-docs/testing_notes.md` when changing.
const String _publicRpcUrls = 'https://mainnet.base.org,'
    'https://base.publicnode.com,'
    'https://base-rpc.publicnode.com,'
    'https://1rpc.io/base,'
    'https://base.drpc.org,'
    'https://base.therpc.io,'
    'https://base.public.blockpi.network/v1/rpc/public';

final String defaultBaseMainnetRpcUrls =
    _buildTimeRpc.isEmpty ? _publicRpcUrls : '$_buildTimeRpc,$_publicRpcUrls';

const int defaultBaseChainId = 8453;
const String defaultDiamondAddr = '0x6aBE1d282f72B474E54527D93b979A4f64d3030a';
const String defaultMorTokenAddr = '0x7431aDa8a591C955a994a21710752EF9b882b8e3';
const String defaultBlockscoutApiV2 = 'https://base.blockscout.com/api/v2';

/// Blockscout **web** base (transaction pages), not the REST API v2 URL above.
const String defaultBlockscoutWebOrigin = 'https://base.blockscout.com';

/// Returns `https://base.blockscout.com/tx/0x…` for opening in a browser.
String blockscoutTransactionUrl(String txHash) {
  final h = txHash.trim();
  if (h.isEmpty) return '';
  final hex = (h.startsWith('0x') || h.startsWith('0X')) ? h : '0x$h';
  return '$defaultBlockscoutWebOrigin/tx/$hex';
}
