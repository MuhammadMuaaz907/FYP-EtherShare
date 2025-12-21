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
      debugPrint('❌ Parse link: Empty link provided');
      return null;
    }

    // Clean and trim the link
    var trimmed = raw.trim();
    
    // Remove any extra whitespace or newlines
    trimmed = trimmed.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    // Handle cases where user might have copied link with extra text
    // Try to extract URL if it's embedded in text
    final urlPattern = RegExp(
      r'(https?://[^\s]+|ethershare://[^\s]+)',
      caseSensitive: false,
    );
    final match = urlPattern.firstMatch(trimmed);
    if (match != null) {
      trimmed = match.group(1)!;
    }

    debugPrint('🔍 Parsing invite link: $trimmed');

    Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (e) {
      debugPrint('❌ Parse link: Invalid URI format - $e');
      return null;
    }

    if (!uri.hasAuthority && uri.scheme.isEmpty) {
      debugPrint('❌ Parse link: No authority or scheme');
      return null;
    }

    final scheme = uri.scheme.toLowerCase();
    String workspaceSlug;
    String inviterAddress;

    if (scheme == 'ethershare') {
      if (uri.host.toLowerCase() != 'invite') {
        debugPrint('❌ Parse link: Invalid host for ethershare scheme: ${uri.host}');
        return null;
      }
      workspaceSlug = uri.queryParameters['workspace'] ?? '';
      inviterAddress = uri.queryParameters['inviter'] ?? '';
    } else if (scheme == 'https' || scheme == 'http') {
      // Support both ethershare.app and any domain (for flexibility)
      if (uri.pathSegments.isEmpty ||
          uri.pathSegments.first.toLowerCase() != 'invite') {
        debugPrint('❌ Parse link: Invalid path for https scheme: ${uri.path}');
        return null;
      }
      workspaceSlug = uri.queryParameters['workspace'] ?? '';
      inviterAddress = uri.queryParameters['inviter'] ?? '';
    } else {
      debugPrint('❌ Parse link: Unsupported scheme: $scheme');
      return null;
    }

    // Decode URL-encoded parameters
    workspaceSlug = Uri.decodeComponent(workspaceSlug);
    inviterAddress = Uri.decodeComponent(inviterAddress);

    // Trim and validate
    workspaceSlug = workspaceSlug.trim();
    inviterAddress = inviterAddress.trim();

    debugPrint('📋 Parsed link data:');
    debugPrint('   Workspace Slug: $workspaceSlug');
    debugPrint('   Inviter Address: $inviterAddress');

    if (workspaceSlug.isEmpty || inviterAddress.isEmpty) {
      debugPrint('❌ Parse link: Missing workspace slug or inviter address');
      return null;
    }

    if (inviterAddress == 'unknown') {
      debugPrint('⚠️ Parse link: Inviter address is "unknown"');
    }

    debugPrint('✅ Link parsed successfully');
    
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

