import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents parsed data from an invitation deep link.
class InviteLinkData {
  final String workspaceSlug;
  final String inviterAddress;

  const InviteLinkData({
    required this.workspaceSlug,
    required this.inviterAddress,
  });

  Map<String, dynamic> toJson() => {
        'workspaceSlug': workspaceSlug,
        'inviterAddress': inviterAddress,
      };

  static InviteLinkData? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final workspaceSlug = json['workspaceSlug'] as String?;
    final inviterAddress = json['inviterAddress'] as String?;

    if (workspaceSlug == null || workspaceSlug.isEmpty) {
      return null;
    }
    if (inviterAddress == null || inviterAddress.isEmpty) {
      return null;
    }

    return InviteLinkData(
      workspaceSlug: workspaceSlug,
      inviterAddress: inviterAddress,
    );
  }
}

/// Stores and notifies about pending invite links across app launches.
class InviteLinkManager {
  InviteLinkManager._();

  static const String _storageKey = 'pending_invite_link';
  static final InviteLinkManager instance = InviteLinkManager._();

  final ValueNotifier<InviteLinkData?> notifier = ValueNotifier(null);
  InviteLinkData? _pendingInvite;
  bool _isLoaded = false;

  InviteLinkData? get currentInvite => _pendingInvite;

  /// Parse an invite link string (deeplink or https fallback) to [InviteLinkData].
  static InviteLinkData? parseLink(String raw) {
    if (raw.isEmpty) {
      return null;
    }

    final trimmed = raw.trim();

    Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      return null;
    }

    if (!uri.hasAuthority && uri.scheme.isEmpty) {
      return null;
    }

    final scheme = uri.scheme.toLowerCase();
    String workspaceSlug;
    String inviterAddress;

    if (scheme == 'ethershare') {
      if (uri.host.toLowerCase() != 'invite') {
        return null;
      }
      workspaceSlug = uri.queryParameters['workspace'] ?? '';
      inviterAddress = uri.queryParameters['inviter'] ?? '';
    } else if (scheme == 'https') {
      if (uri.host.toLowerCase() != 'ethershare.app') {
        return null;
      }
      if (uri.pathSegments.isEmpty ||
          uri.pathSegments.first.toLowerCase() != 'invite') {
        return null;
      }
      workspaceSlug = uri.queryParameters['workspace'] ?? '';
      inviterAddress = uri.queryParameters['inviter'] ?? '';
    } else {
      return null;
    }

    if (workspaceSlug.isEmpty || inviterAddress.isEmpty) {
      return null;
    }

    return InviteLinkData(
      workspaceSlug: workspaceSlug,
      inviterAddress: inviterAddress,
    );
  }

  /// Loads any persisted invite from storage.
  Future<void> loadFromStorage() async {
    if (_isLoaded) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final map = jsonDecode(jsonString) as Map<String, dynamic>;
        _pendingInvite = InviteLinkData.fromJson(map);
      } catch (_) {
        _pendingInvite = null;
      }
    }
    notifier.value = _pendingInvite;
    _isLoaded = true;
  }

  /// Stores a new invite and persists it.
  Future<void> setPendingInvite(InviteLinkData invite) async {
    _pendingInvite = invite;
    notifier.value = invite;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(invite.toJson()));
  }

  /// Consumes the pending invite so it is no longer offered.
  Future<InviteLinkData?> consumePendingInvite() async {
    await loadFromStorage();
    final invite = _pendingInvite;
    if (invite == null) {
      return null;
    }
    await clearPendingInvite();
    return invite;
  }

  /// Clears any stored invite.
  Future<void> clearPendingInvite() async {
    _pendingInvite = null;
    notifier.value = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}

