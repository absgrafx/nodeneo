import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Native signature for the synchronous `SendPromptStream` chunk callback.
typedef NeoStreamDeltaNative = Void Function(Pointer<Utf8> text, Int32 isLast);

/// Native signature for the synchronous `SendPromptStream` completion callback.
typedef NeoCompletionNative = Void Function(Pointer<Utf8> resultJSON);

/// Async callback: Go passes only an int64 delta ID (not a string pointer).
/// Dart retrieves the text via the synchronous ReadStreamDelta FFI call.
typedef NeoAsyncSignalNative = Void Function(Int64 deltaId, Int32 isLast);

/// Async completion callback: same pattern, passes a result ID.
typedef NeoAsyncDoneNative = Void Function(Int64 resultId);

/// FFI bridge to the Go c-shared library (libnodeneo).
/// All Go functions return JSON strings; this bridge handles
/// marshalling and memory management.
class GoBridge {
  static GoBridge? _instance;
  late final DynamicLibrary _lib;
  /// Whether [init] has been called successfully.
  bool initialized = false;

  GoBridge._() {
    _lib = _openLibrary();
  }

  factory GoBridge() {
    _instance ??= GoBridge._();
    return _instance!;
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isMacOS) {
      // Prefer absolute bundle path — Dart's dlopen often does not resolve @rpath the same as the linker.
      final exe = Platform.resolvedExecutable;
      final macosIdx = exe.lastIndexOf('/MacOS/');
      if (macosIdx != -1) {
        final contentsDir = exe.substring(0, macosIdx);
        final bundlePath = '$contentsDir/Frameworks/libnodeneo.dylib';
        if (File(bundlePath).existsSync()) {
          return DynamicLibrary.open(bundlePath);
        }
      }
      try {
        return DynamicLibrary.open('@rpath/libnodeneo.dylib');
      } catch (_) {}
      return DynamicLibrary.open('libnodeneo.dylib');
    } else if (Platform.isIOS) {
      return DynamicLibrary.process();
    } else if (Platform.isAndroid) {
      return DynamicLibrary.open('libnodeneo.so');
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  // --- Native function typedefs ---

  late final _freeString = _lib.lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)>('FreeString');

  late final _init = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Int64, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, int, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)>('Init');

  late final _shutdown = _lib.lookupFunction<
      Void Function(),
      void Function()>('Shutdown');

  late final _isReady = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('IsReady');

  late final _setEncryptionKey = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('SetEncryptionKey');

  late final _openWalletDatabase = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('OpenWalletDatabase');

  late final _listWalletDatabases = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('ListWalletDatabases');

  late final _exportBackup = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)>('ExportBackup');

  late final _importBackup = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>('ImportBackup');

  late final _getLogDir = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('GetLogDir');

  late final _setLogLevel = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('SetLogLevel');

  late final _getLogLevel = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('GetLogLevel');

  late final _setSessionMaintenanceInterval = _lib.lookupFunction<
      Pointer<Utf8> Function(Int64),
      Pointer<Utf8> Function(int)>('SetSessionMaintenanceInterval');

  late final _getProxyRouterVersion = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('GetProxyRouterVersion');

  late final _appLog = _lib.lookupFunction<
      Void Function(Pointer<Utf8>, Pointer<Utf8>),
      void Function(Pointer<Utf8>, Pointer<Utf8>)>('AppLog');

  late final _startExpertAPI = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>('StartExpertAPI');

  late final _stopExpertAPI = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('StopExpertAPI');

  late final _expertAPIStatus = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('ExpertAPIStatus');

  late final _createWallet = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('CreateWallet');

  late final _importWalletMnemonic = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('ImportWalletMnemonic');

  late final _importWalletPrivateKey = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('ImportWalletPrivateKey');

  late final _exportPrivateKey = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('ExportPrivateKey');

  late final _getWalletSummary = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('GetWalletSummary');

  late final _verifyRecoveryMnemonic = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('VerifyRecoveryMnemonic');

  late final _verifyRecoveryPrivateKey = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('VerifyRecoveryPrivateKey');

  late final _sendETH = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>('SendETH');

  late final _sendMOR = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>('SendMOR');

  late final _claimEmptyDraftForModel = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32),
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int)>('ClaimEmptyDraftForModel');

  late final _createConversation = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32),
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int)>('CreateConversation');

  late final _setConversationSession = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>('SetConversationSession');

  late final _setConversationTitle = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>('SetConversationTitle');

  late final _setConversationPinned = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Int32),
      Pointer<Utf8> Function(Pointer<Utf8>, int)>('SetConversationPinned');

  late final _getActiveModels = _lib.lookupFunction<
      Pointer<Utf8> Function(Int32),
      Pointer<Utf8> Function(int)>('GetActiveModels');

  late final _getRatedBids = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('GetRatedBids');

  late final _reusableSessionForModel = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('ReusableSessionForModel');

  late final _estimateOpenSessionStake = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Int64, Int32),
      Pointer<Utf8> Function(Pointer<Utf8>, int, int)>('EstimateOpenSessionStake');

  late final _openSession = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Int64, Int32),
      Pointer<Utf8> Function(Pointer<Utf8>, int, int)>('OpenSession');

  late final _closeSession = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('CloseSession');

  late final _getSession = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('GetSession');

  late final _getUnclosedUserSessions = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('GetUnclosedUserSessions');

  late final _sendPrompt = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32),
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int)>('SendPrompt');

  late final _sendPromptStream = _lib.lookupFunction<
      Pointer<Utf8> Function(
        Pointer<Utf8>,
        Pointer<Utf8>,
        Pointer<Utf8>,
        Int32,
        Pointer<NativeFunction<NeoStreamDeltaNative>>,
      ),
      Pointer<Utf8> Function(
        Pointer<Utf8>,
        Pointer<Utf8>,
        Pointer<Utf8>,
        int,
        Pointer<NativeFunction<NeoStreamDeltaNative>>,
      )>('SendPromptStream');

  late final _sendPromptStreamAsync = _lib.lookupFunction<
      Void Function(
        Pointer<Utf8>,
        Pointer<Utf8>,
        Pointer<Utf8>,
        Int32,
        Pointer<NativeFunction<NeoAsyncSignalNative>>,
        Pointer<NativeFunction<NeoAsyncDoneNative>>,
      ),
      void Function(
        Pointer<Utf8>,
        Pointer<Utf8>,
        Pointer<Utf8>,
        int,
        Pointer<NativeFunction<NeoAsyncSignalNative>>,
        Pointer<NativeFunction<NeoAsyncDoneNative>>,
      )>('SendPromptStreamAsync');

  late final _sendPromptWithOptionsAsync = _lib.lookupFunction<
      Void Function(
        Pointer<Utf8>,
        Pointer<Utf8>,
        Pointer<Utf8>,
        Pointer<Utf8>,
        Int32,
        Pointer<NativeFunction<NeoAsyncSignalNative>>,
        Pointer<NativeFunction<NeoAsyncDoneNative>>,
      ),
      void Function(
        Pointer<Utf8>,
        Pointer<Utf8>,
        Pointer<Utf8>,
        Pointer<Utf8>,
        int,
        Pointer<NativeFunction<NeoAsyncSignalNative>>,
        Pointer<NativeFunction<NeoAsyncDoneNative>>,
      )>('SendPromptWithOptionsAsync');

  /// Synchronous fetch of a stored delta/result string by ID.
  /// Go returns a C string; safe to read immediately (synchronous FFI).
  late final _readStreamDelta = _lib.lookupFunction<
      Pointer<Utf8> Function(Int64),
      Pointer<Utf8> Function(int)>('ReadStreamDelta');

  late final _deleteConversation = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('DeleteConversation');

  late final _getConversations = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('GetConversations');

  late final _getMessages = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('GetMessages');

  late final _setPreference = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>('SetPreference');

  late final _getPreference = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('GetPreference');

  // --- Conversation Tuning ---

  late final _setConversationTuning = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>('SetConversationTuning');

  late final _getConversationTuning = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('GetConversationTuning');

  // --- Gateway ---

  late final _startGateway = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Int32),
      Pointer<Utf8> Function(Pointer<Utf8>, int)>('StartGateway');

  late final _stopGateway = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('StopGateway');

  late final _gatewayStatus = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('GatewayStatus');

  // --- API Keys ---

  late final _generateAPIKey = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('GenerateAPIKey');

  late final _listAPIKeys = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('ListAPIKeys');

  late final _revokeAPIKey = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('RevokeAPIKey');

  // --- Helpers ---

  /// Call a Go function that returns a C string, read it, free it, parse JSON.
  String _callString(Pointer<Utf8> Function() fn) {
    final ptr = fn();
    final result = ptr.toDartString();
    _freeString(ptr);
    return result;
  }

  Map<String, dynamic> _callJSON(Pointer<Utf8> Function() fn) {
    return jsonDecode(_callString(fn)) as Map<String, dynamic>;
  }

  /// Check if a JSON result contains an error.
  void _throwIfError(Map<String, dynamic> result) {
    if (result.containsKey('error')) {
      throw GoBridgeException(result['error'] as String);
    }
  }

  // --- Public API ---

  /// Initialize the SDK. Must be called before any other method.
  Map<String, dynamic> init({
    required String dataDir,
    required String ethNodeURL,
    required int chainID,
    required String diamondAddr,
    required String morTokenAddr,
    required String blockscoutURL,
  }) {
    final dDir = dataDir.toNativeUtf8();
    final url = ethNodeURL.toNativeUtf8();
    final diamond = diamondAddr.toNativeUtf8();
    final mor = morTokenAddr.toNativeUtf8();
    final scout = blockscoutURL.toNativeUtf8();

    final ptr = _init(dDir, url, chainID, diamond, mor, scout);
    final result = ptr.toDartString();
    _freeString(ptr);

    calloc.free(dDir);
    calloc.free(url);
    calloc.free(diamond);
    calloc.free(mor);
    calloc.free(scout);

    final json = jsonDecode(result) as Map<String, dynamic>;
    final st = json['status'] as String?;
    initialized = st == 'ok' || st == 'already_initialized';
    return json;
  }

  /// Tear down native state. Safe to call after a failed [init]: if we never
  /// initialized successfully, skips native calls (avoids dlsym on missing iOS symbols).
  void shutdown() {
    if (!initialized) return;
    try {
      _shutdown();
    } catch (_) {
      // Native teardown failed; still drop Dart-side flag.
    } finally {
      initialized = false;
    }
  }

  bool get isReady => _isReady() != 0;

  // --- Wallet ---

  Map<String, dynamic> createWallet() {
    final result = _callJSON(_createWallet);
    _throwIfError(result);
    return result;
  }

  /// Install AES-256-GCM encryption for chat message content.
  /// [keyHex] must be a 64-char hex string (32 bytes, e.g. SHA-256 of mnemonic).
  void setEncryptionKey(String keyHex) {
    final k = keyHex.toNativeUtf8();
    final ptr = _setEncryptionKey(k);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(k);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
  }

  /// Opens (or creates) a wallet-scoped DB: nodeneo_{fingerprint}.db.
  /// Migrates legacy nodeneo.db on first call for a wallet.
  Map<String, dynamic> openWalletDatabase(String fingerprint) {
    final fp = fingerprint.toNativeUtf8();
    final ptr = _openWalletDatabase(fp);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(fp);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json;
  }

  /// Returns list of wallet DBs found in the data directory.
  List<dynamic> listWalletDatabases() {
    final ptr = _listWalletDatabases();
    final result = ptr.toDartString();
    _freeString(ptr);
    return jsonDecode(result) as List<dynamic>;
  }

  /// Export all conversations, messages, and preferences to an encrypted backup file.
  Map<String, dynamic> exportBackup(String outputPath, String passphrase, String appVersion, String walletPrefix) {
    final op = outputPath.toNativeUtf8();
    final pp = passphrase.toNativeUtf8();
    final av = appVersion.toNativeUtf8();
    final wp = walletPrefix.toNativeUtf8();
    final ptr = _exportBackup(op, pp, av, wp);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(op);
    calloc.free(pp);
    calloc.free(av);
    calloc.free(wp);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json;
  }

  /// Import an encrypted backup file, destructively replacing current data.
  Map<String, dynamic> importBackup(String inputPath, String passphrase) {
    final ip = inputPath.toNativeUtf8();
    final pp = passphrase.toNativeUtf8();
    final ptr = _importBackup(ip, pp);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(ip);
    calloc.free(pp);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json;
  }

  /// Returns structured version info for the embedded proxy-router SDK.
  /// JSON keys: version, commit, is_fork, upstream_tag, fork_commits
  Map<String, dynamic> getProxyRouterVersion() {
    final ptr = _getProxyRouterVersion();
    final result = ptr.toDartString();
    _freeString(ptr);
    return jsonDecode(result) as Map<String, dynamic>;
  }

  /// Returns the absolute path to the log directory (dataDir/logs/).
  String getLogDir() {
    final ptr = _getLogDir();
    final result = ptr.toDartString();
    _freeString(ptr);
    return result;
  }

  /// Changes the Go-side log level. Valid: debug, info, warn, error.
  void setLogLevel(String level) {
    final l = level.toNativeUtf8();
    final ptr = _setLogLevel(l);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(l);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
  }

  /// Returns the current Go-side log level (e.g. "info").
  String getLogLevel() {
    final ptr = _getLogLevel();
    final result = ptr.toDartString();
    _freeString(ptr);
    return result;
  }

  /// Sets how often the SDK checks for expired sessions and auto-closes them.
  /// [seconds]: interval in seconds; 0 disables auto-close. Default is 900 (15 min).
  void setSessionMaintenanceInterval(int seconds) {
    final ptr = _setSessionMaintenanceInterval(seconds);
    final result = ptr.toDartString();
    _freeString(ptr);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
  }

  /// Write a Flutter-side log entry to nodeneo.log (unified with Go SDK logs).
  /// [level]: "debug", "info", "warn", "error".
  void appLog(String level, String message) {
    final l = level.toNativeUtf8();
    final m = message.toNativeUtf8();
    _appLog(l, m);
    calloc.free(l);
    calloc.free(m);
  }

  /// Start the Expert Mode API server (native proxy-router swagger + REST).
  /// [address] is "host:port", e.g. "127.0.0.1:8082" or "0.0.0.0:8082".
  /// [publicURL] sets the Swagger host for CORS, e.g. "http://192.168.1.42:8082".
  Map<String, dynamic> startExpertAPI(String address, String publicURL) {
    final a = address.toNativeUtf8();
    final p = publicURL.toNativeUtf8();
    final ptr = _startExpertAPI(a, p);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(a);
    calloc.free(p);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json;
  }

  /// Stop the Expert Mode local API server.
  void stopExpertAPI() {
    final ptr = _stopExpertAPI();
    final result = ptr.toDartString();
    _freeString(ptr);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
  }

  /// Returns {"running": bool, "port": int}.
  Map<String, dynamic> expertAPIStatus() {
    final ptr = _expertAPIStatus();
    final result = ptr.toDartString();
    _freeString(ptr);
    return jsonDecode(result) as Map<String, dynamic>;
  }

  Map<String, dynamic> importWalletMnemonic(String mnemonic) {
    final m = mnemonic.toNativeUtf8();
    final ptr = _importWalletMnemonic(m);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(m);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json;
  }

  Map<String, dynamic> importWalletPrivateKey(String hexKey) {
    final k = hexKey.toNativeUtf8();
    final ptr = _importWalletPrivateKey(k);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(k);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json;
  }

  Map<String, dynamic> exportPrivateKey() {
    final result = _callJSON(_exportPrivateKey);
    _throwIfError(result);
    return result;
  }

  Map<String, dynamic> getWalletSummary() {
    return _callJSON(_getWalletSummary);
  }

  /// True if the recovery phrase matches the loaded wallet (read-only; does not re-import).
  bool verifyRecoveryMnemonic(String mnemonic) {
    final m = mnemonic.toNativeUtf8();
    final ptr = _verifyRecoveryMnemonic(m);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(m);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json['ok'] == true;
  }

  /// True if the hex private key matches the loaded wallet (read-only).
  bool verifyRecoveryPrivateKey(String hexKey) {
    final k = hexKey.toNativeUtf8();
    final ptr = _verifyRecoveryPrivateKey(k);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(k);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json['ok'] == true;
  }

  /// Sends native ETH. [amountWei] is wei as a decimal integer string.
  Map<String, dynamic> sendETH({required String toAddress, required String amountWei}) {
    final to = toAddress.toNativeUtf8();
    final amt = amountWei.toNativeUtf8();
    final ptr = _sendETH(to, amt);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(to);
    calloc.free(amt);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json;
  }

  /// Sends MOR (18 decimals). [amountWei] is smallest units as decimal string.
  Map<String, dynamic> sendMOR({required String toAddress, required String amountWei}) {
    final to = toAddress.toNativeUtf8();
    final amt = amountWei.toNativeUtf8();
    final ptr = _sendMOR(to, amt);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(to);
    calloc.free(amt);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json;
  }

  /// Reuses the latest message-less draft for [modelId] if any (see Go [ClaimEmptyDraftForModel]).
  Map<String, dynamic> claimEmptyDraftForModel({
    required String modelId,
    required String modelName,
    String provider = '',
    bool isTEE = false,
  }) {
    final mid = modelId.toNativeUtf8();
    final mname = modelName.toNativeUtf8();
    final prov = provider.toNativeUtf8();
    final ptr = _claimEmptyDraftForModel(mid, mname, prov, isTEE ? 1 : 0);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(mid);
    calloc.free(mname);
    calloc.free(prov);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json;
  }

  /// Creates a local SQLite conversation (required before [sendPrompt] persists messages).
  void createConversation({
    required String conversationId,
    required String modelId,
    required String modelName,
    String provider = '',
    bool isTEE = false,
  }) {
    final cid = conversationId.toNativeUtf8();
    final mid = modelId.toNativeUtf8();
    final mname = modelName.toNativeUtf8();
    final prov = provider.toNativeUtf8();
    final ptr = _createConversation(cid, mid, mname, prov, isTEE ? 1 : 0);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(cid);
    calloc.free(mid);
    calloc.free(mname);
    calloc.free(prov);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
  }

  /// Associates an open on-chain session with a local conversation (for resume from home / history).
  void setConversationSession({required String conversationId, required String sessionId}) {
    final cid = conversationId.toNativeUtf8();
    final sid = sessionId.toNativeUtf8();
    final ptr = _setConversationSession(cid, sid);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(cid);
    calloc.free(sid);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
  }

  void setConversationTitle({required String conversationId, required String title}) {
    final cid = conversationId.toNativeUtf8();
    final t = title.toNativeUtf8();
    final ptr = _setConversationTitle(cid, t);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(cid);
    calloc.free(t);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
  }

  void setConversationPinned({required String conversationId, required bool pinned}) {
    final cid = conversationId.toNativeUtf8();
    final ptr = _setConversationPinned(cid, pinned ? 1 : 0);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(cid);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
  }

  /// Deletes local messages and the conversation row. Attempts on-chain [CloseSession] when
  /// [session_id] was set; see returned [close_warning] if that step failed.
  Map<String, dynamic> deleteConversation(String conversationId) {
    final cid = conversationId.toNativeUtf8();
    final ptr = _deleteConversation(cid);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(cid);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json;
  }

  // --- Models ---

  List<dynamic> getActiveModels({bool teeOnly = false}) {
    final ptr = _getActiveModels(teeOnly ? 1 : 0);
    final result = ptr.toDartString();
    _freeString(ptr);
    final decoded = jsonDecode(result);
    if (decoded is Map && decoded.containsKey('error')) {
      throw GoBridgeException(decoded['error'] as String);
    }
    return decoded as List<dynamic>;
  }

  List<dynamic> getRatedBids(String modelID) {
    final id = modelID.toNativeUtf8();
    final ptr = _getRatedBids(id);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(id);
    final decoded = jsonDecode(result);
    if (decoded is Map && decoded.containsKey('error')) {
      throw GoBridgeException(decoded['error'] as String);
    }
    return decoded as List<dynamic>;
  }

  /// Active on-chain session for [modelID] if one exists and is not past [ends_at] (see Go).
  Map<String, dynamic> reusableSessionForModel(String modelID) {
    final id = modelID.toNativeUtf8();
    final ptr = _reusableSessionForModel(id);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(id);
    final decoded = jsonDecode(result);
    if (decoded is Map && decoded.containsKey('error')) {
      throw GoBridgeException(decoded['error'] as String);
    }
    return decoded as Map<String, dynamic>;
  }

  /// On-chain MOR stake for opening with the top-scored bid ([EstimateOpenSessionStake] in Go).
  Map<String, dynamic> estimateOpenSessionStake(
    String modelID,
    int durationSeconds, {
    bool directPayment = false,
  }) {
    final id = modelID.toNativeUtf8();
    final ptr = _estimateOpenSessionStake(id, durationSeconds, directPayment ? 1 : 0);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(id);
    final decoded = jsonDecode(result);
    if (decoded is Map && decoded.containsKey('error')) {
      throw GoBridgeException(decoded['error'] as String);
    }
    return decoded as Map<String, dynamic>;
  }

  // --- Sessions ---

  Map<String, dynamic> openSession(String modelID, int durationSeconds, {bool directPayment = false}) {
    final id = modelID.toNativeUtf8();
    final ptr = _openSession(id, durationSeconds, directPayment ? 1 : 0);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(id);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json;
  }

  Map<String, dynamic> closeSession(String sessionID) {
    final id = sessionID.toNativeUtf8();
    final ptr = _closeSession(id);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(id);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json;
  }

  Map<String, dynamic> getSession(String sessionID) {
    final id = sessionID.toNativeUtf8();
    final ptr = _getSession(id);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(id);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json;
  }

  /// Open on-chain sessions for the wallet (not closed on-chain yet).
  List<dynamic> listUnclosedSessions() {
    final ptr = _getUnclosedUserSessions();
    final result = ptr.toDartString();
    _freeString(ptr);
    final decoded = jsonDecode(result);
    if (decoded is Map && decoded.containsKey('error')) {
      throw GoBridgeException(decoded['error'] as String);
    }
    // Go `json.Marshal` of nil slice is JSON `null`; treat as empty list.
    if (decoded == null) return <dynamic>[];
    if (decoded is! List) {
      throw GoBridgeException(
        'GetUnclosedUserSessions: expected JSON array, got ${decoded.runtimeType}',
      );
    }
    return List<dynamic>.from(decoded);
  }

  // --- Chat ---

  /// [stream]: when true, ask the provider for SSE/token streaming; when false, non-streaming completion.
  Map<String, dynamic> sendPrompt(
    String sessionID,
    String conversationID,
    String prompt, {
    bool stream = true,
  }) {
    final sid = sessionID.toNativeUtf8();
    final cid = conversationID.toNativeUtf8();
    final p = prompt.toNativeUtf8();
    final ptr = _sendPrompt(sid, cid, p, stream ? 1 : 0);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(sid);
    calloc.free(cid);
    calloc.free(p);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json;
  }

  /// Like [sendPrompt], but invokes [onDelta] for each streamed chunk from the provider.
  ///
  /// [onDelta] may run on a background thread; copy [delta] synchronously before awaiting.
  /// The returned map matches [sendPrompt] (includes `response` with the full assistant text).
  Map<String, dynamic> sendPromptWithStream(
    String sessionID,
    String conversationID,
    String prompt, {
    bool stream = true,
    required void Function(String delta, bool isLast) onDelta,
  }) {
    final sid = sessionID.toNativeUtf8();
    final cid = conversationID.toNativeUtf8();
    final p = prompt.toNativeUtf8();

    final callable = NativeCallable<NeoStreamDeltaNative>.listener(
      (Pointer<Utf8> text, int isLast) {
        final piece = text.toDartString();
        onDelta(piece, isLast != 0);
      },
    );

    try {
      final ptr = _sendPromptStream(
        sid,
        cid,
        p,
        stream ? 1 : 0,
        callable.nativeFunction,
      );
      final result = ptr.toDartString();
      _freeString(ptr);
      final json = jsonDecode(result) as Map<String, dynamic>;
      _throwIfError(json);
      return json;
    } finally {
      calloc.free(sid);
      calloc.free(cid);
      calloc.free(p);
      callable.close();
    }
  }

  /// Fetch a delta string from Go's store by ID. Synchronous FFI — the C
  /// string is read immediately before Go can touch the memory.
  String _fetchDelta(int deltaId) {
    final ptr = _readStreamDelta(deltaId);
    final text = ptr.toDartString();
    malloc.free(ptr); // Go used C.CString; free after copy
    return text;
  }

  /// Non-blocking streaming variant. Returns a [Future] that completes with
  /// the final result JSON when the prompt finishes. Delta callbacks fire in
  /// real-time on the Dart event loop because the FFI call returns immediately
  /// (Go runs the work in a goroutine).
  ///
  /// Go stores delta text in a thread-safe map and passes only the int64 key
  /// through the NativeCallable.listener callback. Dart retrieves the actual
  /// text via the synchronous [_fetchDelta] call, avoiding the use-after-free
  /// race inherent in passing C string pointers through async message ports.
  Future<Map<String, dynamic>> sendPromptStreamAsync(
    String sessionID,
    String conversationID,
    String prompt, {
    bool stream = true,
    required void Function(String delta, bool isLast) onDelta,
  }) {
    final completer = Completer<Map<String, dynamic>>();

    final sid = sessionID.toNativeUtf8();
    final cid = conversationID.toNativeUtf8();
    final p = prompt.toNativeUtf8();

    late final NativeCallable<NeoAsyncSignalNative> deltaCallable;
    late final NativeCallable<NeoAsyncDoneNative> completionCallable;

    deltaCallable = NativeCallable<NeoAsyncSignalNative>.listener(
      (int deltaId, int isLast) {
        final piece = _fetchDelta(deltaId);
        onDelta(piece, isLast != 0);
      },
    );

    completionCallable = NativeCallable<NeoAsyncDoneNative>.listener(
      (int resultId) {
        final result = _fetchDelta(resultId);
        deltaCallable.close();
        completionCallable.close();
        calloc.free(sid);
        calloc.free(cid);
        calloc.free(p);

        try {
          final json = jsonDecode(result) as Map<String, dynamic>;
          if (json.containsKey('error')) {
            completer.completeError(GoBridgeException(json['error'] as String));
          } else {
            completer.complete(json);
          }
        } catch (e) {
          completer.completeError(e);
        }
      },
    );

    _sendPromptStreamAsync(
      sid,
      cid,
      p,
      stream ? 1 : 0,
      deltaCallable.nativeFunction,
      completionCallable.nativeFunction,
    );

    return completer.future;
  }

  /// Non-blocking streaming with tuning parameters. [options] is a map with
  /// keys like "temperature", "top_p", "max_tokens", "frequency_penalty",
  /// "presence_penalty". Omitted keys use provider defaults.
  Future<Map<String, dynamic>> sendPromptWithOptionsAsync(
    String sessionID,
    String conversationID,
    String prompt, {
    bool stream = true,
    Map<String, dynamic>? options,
    required void Function(String delta, bool isLast) onDelta,
  }) {
    final completer = Completer<Map<String, dynamic>>();

    final sid = sessionID.toNativeUtf8();
    final cid = conversationID.toNativeUtf8();
    final p = prompt.toNativeUtf8();
    final o = (options != null ? jsonEncode(options) : '{}').toNativeUtf8();

    late final NativeCallable<NeoAsyncSignalNative> deltaCallable;
    late final NativeCallable<NeoAsyncDoneNative> completionCallable;

    deltaCallable = NativeCallable<NeoAsyncSignalNative>.listener(
      (int deltaId, int isLast) {
        final piece = _fetchDelta(deltaId);
        onDelta(piece, isLast != 0);
      },
    );

    completionCallable = NativeCallable<NeoAsyncDoneNative>.listener(
      (int resultId) {
        final result = _fetchDelta(resultId);
        deltaCallable.close();
        completionCallable.close();
        calloc.free(sid);
        calloc.free(cid);
        calloc.free(p);
        calloc.free(o);

        try {
          final json = jsonDecode(result) as Map<String, dynamic>;
          if (json.containsKey('error')) {
            completer.completeError(GoBridgeException(json['error'] as String));
          } else {
            completer.complete(json);
          }
        } catch (e) {
          completer.completeError(e);
        }
      },
    );

    _sendPromptWithOptionsAsync(
      sid,
      cid,
      p,
      o,
      stream ? 1 : 0,
      deltaCallable.nativeFunction,
      completionCallable.nativeFunction,
    );

    return completer.future;
  }

  // --- Conversations ---

  List<dynamic> getConversations() {
    final result = _callString(_getConversations);
    final decoded = jsonDecode(result);
    if (decoded is Map && decoded.containsKey('error')) {
      throw GoBridgeException(decoded['error'] as String);
    }
    return (decoded ?? []) as List<dynamic>;
  }

  List<dynamic> getMessages(String conversationID) {
    final id = conversationID.toNativeUtf8();
    final ptr = _getMessages(id);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(id);
    final decoded = jsonDecode(result);
    if (decoded is Map && decoded.containsKey('error')) {
      throw GoBridgeException(decoded['error'] as String);
    }
    return (decoded ?? []) as List<dynamic>;
  }

  // --- Preferences ---

  void setPreference(String key, String value) {
    final k = key.toNativeUtf8();
    final v = value.toNativeUtf8();
    final ptr = _setPreference(k, v);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(k);
    calloc.free(v);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
  }

  String getPreference(String key) {
    final k = key.toNativeUtf8();
    final ptr = _getPreference(k);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(k);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json['value'] as String? ?? '';
  }

  // --- Conversation Tuning ---

  /// Store tuning params (JSON blob) for a conversation.
  void setConversationTuning({required String conversationId, required String tuningJSON}) {
    final cid = conversationId.toNativeUtf8();
    final t = tuningJSON.toNativeUtf8();
    final ptr = _setConversationTuning(cid, t);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(cid);
    calloc.free(t);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
  }

  /// Returns the stored tuning params JSON blob (empty string if not set).
  String getConversationTuning(String conversationId) {
    final cid = conversationId.toNativeUtf8();
    final ptr = _getConversationTuning(cid);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(cid);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json['tuning_params'] as String? ?? '';
  }

  // --- Gateway ---

  /// Start the OpenAI-compatible gateway HTTP server.
  /// [address] is "host:port", e.g. "127.0.0.1:8083" or "0.0.0.0:8083".
  Map<String, dynamic> startGateway(String address, {bool cloudflaredQuickTunnel = false}) {
    final a = address.toNativeUtf8();
    final ptr = _startGateway(a, cloudflaredQuickTunnel ? 1 : 0);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(a);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json;
  }

  /// Stop the gateway HTTP server.
  void stopGateway() {
    final ptr = _stopGateway();
    final result = ptr.toDartString();
    _freeString(ptr);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
  }

  /// Returns {"running": bool, "address": "..."}.
  Map<String, dynamic> gatewayStatus() {
    final ptr = _gatewayStatus();
    final result = ptr.toDartString();
    _freeString(ptr);
    return jsonDecode(result) as Map<String, dynamic>;
  }

  // --- API Keys ---

  /// Generate a new API key. Returns {"id", "key", "prefix", "name"}.
  /// The "key" field is the full secret — shown once and never again.
  Map<String, dynamic> generateAPIKey(String name) {
    final n = name.toNativeUtf8();
    final ptr = _generateAPIKey(n);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(n);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
    return json;
  }

  /// List all active API keys (no secrets exposed).
  List<dynamic> listAPIKeys() {
    final result = _callString(_listAPIKeys);
    final decoded = jsonDecode(result);
    if (decoded is Map && decoded.containsKey('error')) {
      throw GoBridgeException(decoded['error'] as String);
    }
    return (decoded ?? []) as List<dynamic>;
  }

  /// Revoke an API key by ID, immediately blocking access.
  void revokeAPIKey(String id) {
    final i = id.toNativeUtf8();
    final ptr = _revokeAPIKey(i);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(i);
    final json = jsonDecode(result) as Map<String, dynamic>;
    _throwIfError(json);
  }
}

class GoBridgeException implements Exception {
  final String message;
  GoBridgeException(this.message);

  @override
  String toString() => 'GoBridgeException: $message';
}
