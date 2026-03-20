import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// FFI bridge to the Go c-shared library (libredpill).
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
      // App bundle: Contents/Frameworks/libredpill.dylib (via @rpath set by Xcode)
      try {
        return DynamicLibrary.open('@rpath/libredpill.dylib');
      } catch (_) {}
      // Explicit path inside bundle
      final exe = Platform.resolvedExecutable;
      final contentsDir = exe.substring(0, exe.lastIndexOf('/MacOS/'));
      final bundlePath = '$contentsDir/Frameworks/libredpill.dylib';
      try {
        return DynamicLibrary.open(bundlePath);
      } catch (_) {}
      return DynamicLibrary.open('libredpill.dylib');
    } else if (Platform.isIOS) {
      return DynamicLibrary.process();
    } else if (Platform.isAndroid) {
      return DynamicLibrary.open('libredpill.so');
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

  void shutdown() {
    _shutdown();
    initialized = false;
  }

  bool get isReady => _isReady() != 0;

  // --- Wallet ---

  Map<String, dynamic> createWallet() {
    final result = _callJSON(_createWallet);
    _throwIfError(result);
    return result;
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
}

class GoBridgeException implements Exception {
  final String message;
  GoBridgeException(this.message);

  @override
  String toString() => 'GoBridgeException: $message';
}
