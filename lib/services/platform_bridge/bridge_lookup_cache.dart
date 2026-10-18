part of '../platform_bridge.dart';

class _BridgeCacheEntry {
  final Map<String, dynamic> value;
  final DateTime expiresAt;
  final int bytes;

  const _BridgeCacheEntry({
    required this.value,
    required this.expiresAt,
    required this.bytes,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class _BridgeListCacheEntry {
  final List<Map<String, dynamic>> value;
  final DateTime expiresAt;
  final int bytes;

  const _BridgeListCacheEntry({
    required this.value,
    required this.expiresAt,
    required this.bytes,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class _BridgeInFlight<T> {
  final String requestId;
  final String scopeKey;
  final Future<T> future;

  const _BridgeInFlight({
    required this.requestId,
    required this.scopeKey,
    required this.future,
  });
}
