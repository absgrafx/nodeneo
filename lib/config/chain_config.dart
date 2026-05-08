/// Build-time injected RPC URL (e.g. a premium Alchemy endpoint).
/// Pass via: flutter run --dart-define=ETH_RPC_URL=https://...
/// Empty/absent is fine — public RPCs are used as fallback.
const String _buildTimeRpc =
    String.fromEnvironment('ETH_RPC_URL', defaultValue: '');

/// Whether a build-time dedicated RPC was injected.
bool get hasBuildTimeRpc => _buildTimeRpc.isNotEmpty;

/// Public fallback RPCs (used only when no dedicated/custom node is set).
///
/// Comma-separated HTTPS JSON-RPC URLs; Go SDK round-robins and retries.
/// Each entry must be a Base mainnet (chain id 8453) endpoint that
/// returns valid JSON-RPC responses with no auth — anything that 401s
/// or rate-limits aggressively will fail the round-robin.
const String publicFallbackRpcUrls = 'https://mainnet.base.org,'
    'https://base.publicnode.com,'
    'https://base-rpc.publicnode.com,'
    'https://1rpc.io/base,'
    'https://base.drpc.org,'
    'https://base.public.blockpi.network/v1/rpc/public';

/// When a build-time dedicated RPC is provided, use ONLY that endpoint
/// (no round-robin across public nodes that may have different sync states).
/// Public RPCs are only used as the full fallback set when no dedicated node exists.
final String defaultBaseMainnetRpcUrls =
    _buildTimeRpc.isEmpty ? publicFallbackRpcUrls : _buildTimeRpc;

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
