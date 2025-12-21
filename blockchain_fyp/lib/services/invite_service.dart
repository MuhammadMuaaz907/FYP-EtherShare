import 'dart:async';
import 'dart:io';

import 'package:email_validator/email_validator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'invite_link_manager.dart';
import 'distributed_service.dart';

/// Centralised utility for creating and sharing workspace invitations.
///
/// This service builds consistent invite links/messages and exposes helpers
/// for sharing via the system share sheet or email composer.
class InviteService {
  InviteService._();

  static const String _deepLinkScheme = 'ethershare';
  static const String _deepLinkHost = 'invite';
  static const String _webInviteBase = 'https://ethershare.app/invite';

  /// Builds the primary HTTPS invitation link (App/Universal Link).
  static String buildWorkspaceInviteLink({
    required String workspaceName,
    required String inviterAddress,
  }) {
    final slug = _workspaceSlug(workspaceName);
    final inviter = inviterAddress.trim().isEmpty
        ? 'unknown'
        : inviterAddress.trim().toLowerCase();

    // Properly encode URL parameters
    final encodedSlug = Uri.encodeComponent(slug);
    final encodedInviter = Uri.encodeComponent(inviter);

    final link = '$_webInviteBase?workspace=$encodedSlug&inviter=$encodedInviter';
    
    debugPrint('🔗 Generated invite link: $link');
    debugPrint('   Workspace: $workspaceName -> Slug: $slug');
    debugPrint('   Inviter: $inviterAddress');
    
    return link;
  }

  /// Builds the custom scheme fallback link for legacy contexts.
  static String buildWorkspaceInviteFallback({
    required String workspaceName,
    required String inviterAddress,
  }) {
    final slug = _workspaceSlug(workspaceName);
    final inviter = inviterAddress.trim().isEmpty
        ? 'unknown'
        : inviterAddress.trim().toLowerCase();

    // Properly encode URL parameters
    final encodedSlug = Uri.encodeComponent(slug);
    final encodedInviter = Uri.encodeComponent(inviter);

    return '$_deepLinkScheme://$_deepLinkHost?workspace=$encodedSlug&inviter=$encodedInviter';
  }

  /// Shares an invitation using the native share sheet.
  ///
  /// Returns the share outcome including status and invite link.
  static Future<InviteShareOutcome> shareWorkspaceInvite({
    required String workspaceName,
    required String inviterAddress,
    Rect? shareOrigin,
  }) async {
    final link = buildWorkspaceInviteLink(
      workspaceName: workspaceName,
      inviterAddress: inviterAddress,
    );
    final fallback = buildWorkspaceInviteFallback(
      workspaceName: workspaceName,
      inviterAddress: inviterAddress,
    );

    final subject = _emailSubject(workspaceName);
    final message = _shareMessage(
      workspaceName: workspaceName,
      inviterAddress: inviterAddress,
      inviteLink: link,
      fallbackLink: fallback,
    );

    final ShareResult result = await Share.shareWithResult(
      message,
      subject: subject,
      sharePositionOrigin: shareOrigin,
    );

    return InviteShareOutcome(
      status: _mapShareStatus(result.status),
      link: link,
    );
  }

  /// Copies the invite link to the clipboard.
  static Future<String> copyInviteLinkToClipboard({
    required String workspaceName,
    required String inviterAddress,
  }) async {
    final link = buildWorkspaceInviteLink(
      workspaceName: workspaceName,
      inviterAddress: inviterAddress,
    );

    await Clipboard.setData(ClipboardData(text: link));
    return link;
  }

  /// Launches the default mail client with a pre-populated invitation.
  ///
  /// Returns true if the composer could be opened.
  static Future<bool> launchEmailComposer({
    required List<String> recipients,
    required String workspaceName,
    required String inviterAddress,
  }) async {
    if (recipients.isEmpty) {
      return false;
    }

    final cleanRecipients = recipients
        .map((email) => email.trim())
        .where((email) => email.isNotEmpty)
        .toList();

    if (cleanRecipients.isEmpty) {
      return false;
    }

    final subject = _emailSubject(workspaceName);
    final body = _emailBody(
      workspaceName: workspaceName,
      inviterAddress: inviterAddress,
    );

    final query = _encodeQueryParameters({
      'subject': subject,
      'body': body,
    });

    final mailUri = Uri(
      scheme: 'mailto',
      path: cleanRecipients.join(','),
      query: query,
    );

    if (!await canLaunchUrl(mailUri)) {
      return false;
    }

    return launchUrl(mailUri);
  }

  /// Sends an invitation email directly using configured SMTP credentials.
  static Future<InviteEmailSendResult> sendWorkspaceInviteEmail({
    required String recipientEmail,
    required String workspaceName,
    required String inviterAddress,
    String? inviterDisplayName,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final email = recipientEmail.trim();

    if (!EmailValidator.validate(email)) {
      return InviteEmailSendResult(
        status: InviteEmailStatus.invalidEmail,
        recipientEmail: email,
        message: 'Enter a valid email address.',
      );
    }

    final smtpUsername = dotenv.env['SMTP_USERNAME'] ?? '';
    final smtpPassword = dotenv.env['SMTP_PASSWORD'] ?? '';
    final smtpHost = dotenv.env['SMTP_HOST'] ?? '';
    final smtpPortRaw = dotenv.env['SMTP_PORT'] ?? '';
    final smtpSecureRaw = dotenv.env['SMTP_SECURE'] ?? 'true';

    if (smtpUsername.isEmpty ||
        smtpPassword.isEmpty ||
        smtpHost.isEmpty ||
        smtpPortRaw.isEmpty) {
      return InviteEmailSendResult(
        status: InviteEmailStatus.missingConfiguration,
        recipientEmail: email,
        message:
            'SMTP configuration missing. Please define SMTP_USERNAME, SMTP_PASSWORD, SMTP_HOST, SMTP_PORT in your environment.',
      );
    }

    final smtpPort = int.tryParse(smtpPortRaw) ?? 587;
    final useSecure = smtpSecureRaw.toLowerCase() != 'false';

    final useImplicitSsl = useSecure && (smtpPort == 465);

    final smtpServer = SmtpServer(
      smtpHost,
      username: smtpUsername,
      password: smtpPassword,
      port: smtpPort,
      ssl: useImplicitSsl,
      allowInsecure: !useSecure,
    );

    final fromEmail =
        (dotenv.env['SMTP_FROM_EMAIL'] ?? smtpUsername).trim();
    final fromName =
        (dotenv.env['SMTP_FROM_NAME'] ?? 'EtherShare').trim();

    final subject = _emailSubject(workspaceName);
    final inviteLink = buildWorkspaceInviteLink(
      workspaceName: workspaceName,
      inviterAddress: inviterAddress,
    );
    final fallbackLink = buildWorkspaceInviteFallback(
      workspaceName: workspaceName,
      inviterAddress: inviterAddress,
    );
    final friendlyInviter = inviterDisplayName?.trim().isNotEmpty == true
        ? inviterDisplayName!.trim()
        : inviterAddress.trim().isNotEmpty
            ? inviterAddress
            : 'Your teammate';

    final htmlBody = _inviteEmailHtml(
      workspaceName: workspaceName,
      inviter: friendlyInviter,
      inviteLink: inviteLink,
      fallbackLink: fallbackLink,
    );
    final textBody = _inviteEmailPlainText(
      workspaceName: workspaceName,
      inviter: friendlyInviter,
      inviteLink: inviteLink,
      fallbackLink: fallbackLink,
    );

    final message = Message()
      ..from = Address(fromEmail, fromName)
      ..recipients.add(email)
      ..subject = subject
      ..text = textBody
      ..html = htmlBody;

    try {
      await send(message, smtpServer).timeout(timeout);
      return InviteEmailSendResult(
        status: InviteEmailStatus.sent,
        recipientEmail: email,
        message: 'Invitation sent to $email.',
      );
    } on TimeoutException {
      return InviteEmailSendResult(
        status: InviteEmailStatus.timeout,
        recipientEmail: email,
        message: 'Email send timed out. Check your connection and try again.',
      );
    } on MailerException catch (error) {
      return InviteEmailSendResult(
        status: InviteEmailStatus.failed,
        recipientEmail: email,
        message:
            'Unable to send invite email. ${error.problems.map((p) => p.msg).join(', ')}',
      );
    } on HandshakeException {
      return InviteEmailSendResult(
        status: InviteEmailStatus.handshakeFailure,
        recipientEmail: email,
        message:
            'Secure connection failed. Verify SMTP_HOST/PORT and TLS settings (e.g. use port 587 with SMTP_SECURE=false for STARTTLS or port 465 with SMTP_SECURE=true).',
      );
    } catch (error) {
      return InviteEmailSendResult(
        status: InviteEmailStatus.failed,
        recipientEmail: email,
        message: 'Unexpected error while sending invite: $error',
      );
    }
  }

  static String _workspaceSlug(String workspaceName) {
    final trimmed = workspaceName.trim();

    if (trimmed.isEmpty) {
      return 'workspace';
    }

    final slug = trimmed
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');

    return slug.isEmpty ? 'workspace' : slug;
  }

  static String _emailSubject(String workspaceName) {
    final name = workspaceName.trim().isEmpty ? 'our workspace' : workspaceName;
    return 'Join $name on EtherShare';
  }

  static String _shareMessage({
    required String workspaceName,
    required String inviterAddress,
    required String inviteLink,
    required String fallbackLink,
  }) {
    final name = workspaceName.trim().isEmpty ? 'our workspace' : workspaceName;

    return '''
Join us on EtherShare!

$name is collaborating on EtherShare and we’d love to have you onboard.
Tap the link below. If it doesn’t open automatically, open EtherShare, Create Workspace screen par “Join existing workspace” button select karo, aur wahan link paste karo.

Primary link:
$inviteLink

Copy & paste backup:
$fallbackLink

Sent by $inviterAddress
'''.trim();
  }

  static String _emailBody({
    required String workspaceName,
    required String inviterAddress,
  }) {
    final inviteLink = buildWorkspaceInviteLink(
      workspaceName: workspaceName,
      inviterAddress: inviterAddress,
    );
    final fallbackLink = buildWorkspaceInviteFallback(
      workspaceName: workspaceName,
      inviterAddress: inviterAddress,
    );

    final inviter = inviterAddress.trim().isEmpty ? 'our team' : inviterAddress;
    final name = workspaceName.trim().isEmpty ? 'our workspace' : workspaceName;

    return '''
Hi,

$inviter invited you to collaborate in $name on EtherShare.

Tap the button or link below. If it doesn’t open automatically:
1. EtherShare app kholo.
2. Create Workspace screen par “Join existing workspace” choose karo.
3. Link paste karke continue karo.

Primary link:
$inviteLink

Copy & paste backup:
$fallbackLink

If you weren’t expecting this invite, you can safely ignore this email.

Thanks,
EtherShare Team
'''.trim();
  }

  static String _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map(
          (entry) =>
              '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
        )
        .join('&');
  }

  static InviteShareStatus _mapShareStatus(ShareResultStatus status) {
    switch (status) {
      case ShareResultStatus.success:
        return InviteShareStatus.shared;
      case ShareResultStatus.dismissed:
        return InviteShareStatus.dismissed;
      case ShareResultStatus.unavailable:
      default:
        return InviteShareStatus.unavailable;
    }
  }

  static String _inviteEmailHtml({
    required String workspaceName,
    required String inviter,
    required String inviteLink,
    required String fallbackLink,
  }) {
    final safeWorkspace =
        workspaceName.trim().isEmpty ? 'our EtherShare workspace' : workspaceName;

    return '''
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <title>Join $safeWorkspace on EtherShare</title>
  </head>
  <body style="background-color:#0f172a;margin:0;padding:24px;font-family:Arial,sans-serif;color:#f8fafc;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 auto;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;background-color:#1e293b;border-radius:16px;padding:32px;">
            <tr>
              <td style="text-align:center;">
                <h1 style="color:#38bdf8;margin-bottom:16px;">You're invited to $safeWorkspace</h1>
                <p style="font-size:16px;line-height:1.6;color:#e2e8f0;">
                  $inviter has invited you to collaborate securely on EtherShare.
                </p>
                <p style="font-size:16px;line-height:1.6;color:#e2e8f0;">
                  Tap the button below to accept the invite. If it doesn’t open automatically, follow the quick steps underneath.
                </p>
                <a href="$inviteLink"
                   style="display:inline-block;margin:24px auto;padding:14px 32px;background-color:#38bdf8;color:#0f172a;
                   text-decoration:none;font-weight:bold;border-radius:999px;">
                  Join Workspace
                </a>
                <div style="text-align:left;margin-top:24px;">
                  <p style="font-size:14px;color:#94a3b8;margin:0 0 8px;">
                    Agar tapping se EtherShare launch nahin hoti:
                  </p>
                  <ol style="font-size:14px;color:#cbd5f5;padding-left:20px;margin:0 0 16px;">
                    <li>EtherShare app kholo.</li>
                    <li>Create Workspace screen par <strong>Join existing workspace</strong> choose karo.</li>
                    <li>Niche diya gaya link paste karo aur continue karo.</li>
                  </ol>
                  <p style="font-size:14px;color:#cbd5f5;word-break:break-all;margin:0;">
                    Primary link:<br/>$inviteLink
                  </p>
                  <p style="font-size:13px;color:#94a3b8;word-break:break-all;margin:12px 0 0;">
                    Copy &amp; paste backup:<br/>$fallbackLink
                  </p>
                </div>
                <hr style="border:none;border-top:1px solid #334155;margin:32px 0;" />
                <p style="font-size:13px;color:#64748b;">
                  If you weren't expecting this invitation, you can safely ignore this email.
                </p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>
''';
  }

  static String _inviteEmailPlainText({
    required String workspaceName,
    required String inviter,
    required String inviteLink,
    required String fallbackLink,
  }) {
    final safeWorkspace =
        workspaceName.trim().isEmpty ? 'our EtherShare workspace' : workspaceName;

    return '''
$inviter invited you to collaborate in $safeWorkspace on EtherShare.

Tap the link below. Agar direct open na ho, EtherShare app mein Create Workspace screen par “Join existing workspace” button se link paste karo.

Primary link:
$inviteLink

Copy & paste backup:
$fallbackLink

If you weren't expecting this invitation, you can safely ignore this email.
'''.trim();
  }

  /// Resolves an invite link by fetching workspace details from MongoDB
  /// Returns ResolvedInvite if workspace found, null otherwise
  static Future<ResolvedInvite?> resolveInvite(InviteLinkData data) async {
    try {
      debugPrint('🔍 Resolving invite:');
      debugPrint('   Workspace Slug: ${data.workspaceSlug}');
      debugPrint('   Inviter Address: ${data.inviterAddress}');
      
      // Normalize slug and inviter address
      final normalizedSlug = data.workspaceSlug.trim().toLowerCase();
      final normalizedInviter = data.inviterAddress.trim().toLowerCase();
      
      // Resolve workspace by slug and inviter address
      final workspace = await DistributedService.resolveWorkspaceBySlug(
        workspaceSlug: normalizedSlug,
        inviterAddress: normalizedInviter,
      );
      
      if (workspace == null) {
        debugPrint('❌ Workspace not found for invite link');
        debugPrint('   Searched for slug: $normalizedSlug');
        debugPrint('   With inviter: $normalizedInviter');
        debugPrint('💡 Possible issues:');
        debugPrint('   1. Workspace does not exist');
        debugPrint('   2. Inviter address mismatch');
        debugPrint('   3. Slug generation mismatch');
        return null;
      }
      
      final workspaceName = workspace['name']?.toString() ?? '';
      final workspaceId = workspace['workspace_id']?.toString() ?? '';
      
      if (workspaceName.isEmpty || workspaceId.isEmpty) {
        debugPrint('❌ Invalid workspace data returned from backend');
        debugPrint('   Workspace name: $workspaceName');
        debugPrint('   Workspace ID: $workspaceId');
        return null;
      }
      
      // Generate slug from workspace name to verify match
      final expectedSlug = _workspaceSlug(workspaceName).toLowerCase();
      final providedSlug = normalizedSlug;
      final slugMatches = expectedSlug == providedSlug;
      
      if (!slugMatches) {
        debugPrint('⚠️ Slug mismatch detected:');
        debugPrint('   Expected slug (from workspace name): $expectedSlug');
        debugPrint('   Provided slug (from link): $providedSlug');
        debugPrint('   Workspace name: $workspaceName');
        // Still proceed, but log the mismatch
      }
      
      debugPrint('✅ Workspace resolved successfully:');
      debugPrint('   Workspace Name: $workspaceName');
      debugPrint('   Workspace ID: $workspaceId');
      debugPrint('   Slug Match: $slugMatches');
      
      return ResolvedInvite(
        linkData: data,
        workspaceName: workspaceName,
        channelName: 'general', // Default channel
        slugMatchesWorkspace: slugMatches,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ Error resolving invite: $e');
      debugPrint('   Stack trace: $stackTrace');
      return null;
    }
  }

  /// Applies an invite by adding the user to the workspace in MongoDB
  /// Returns true if successful, false otherwise
  static Future<bool> applyInviteForUser({
    required ResolvedInvite invite,
    required String inviteeAddress,
  }) async {
    try {
      debugPrint('📝 Applying invite for user: $inviteeAddress');
      debugPrint('   Workspace: ${invite.workspaceName}');
      debugPrint('   Inviter: ${invite.linkData.inviterAddress}');
      
      // First, resolve workspace to get workspace_id
      final workspace = await DistributedService.resolveWorkspaceBySlug(
        workspaceSlug: invite.linkData.workspaceSlug,
        inviterAddress: invite.linkData.inviterAddress,
      );
      
      if (workspace == null) {
        debugPrint('❌ Cannot apply invite: workspace not found');
        return false;
      }
      
      final workspaceId = workspace['workspace_id']?.toString() ?? '';
      if (workspaceId.isEmpty) {
        debugPrint('❌ Invalid workspace ID');
        return false;
      }
      
      // Check if user is already a member
      final existingMembers = await DistributedService.getWorkspaceMembers(workspaceId);
      final isAlreadyMember = existingMembers.any(
        (member) => (member['memberAddress']?.toString() ?? '').toLowerCase() == inviteeAddress.toLowerCase(),
      );
      
      if (isAlreadyMember) {
        debugPrint('ℹ️ User is already a member of this workspace');
        return true; // Already a member, consider it successful
      }
      
      // Get user's display name from profile
      String? displayName;
      try {
        final profile = await DistributedService.getUserProfile(inviteeAddress);
        if (profile != null) {
          displayName = profile['username']?.toString();
        }
      } catch (e) {
        debugPrint('⚠️ Could not fetch user profile: $e');
      }
      
      // Add user as workspace member
      final success = await DistributedService.addWorkspaceMember(
        workspaceId: workspaceId,
        memberAddress: inviteeAddress,
        displayName: displayName,
      );
      
      if (success) {
        debugPrint('✅ User successfully added to workspace: $workspaceId');
      } else {
        debugPrint('❌ Failed to add user to workspace');
      }
      
      return success;
    } catch (e) {
      debugPrint('❌ Error applying invite: $e');
      return false;
    }
  }

}

/// High-level status for invite sharing.
enum InviteShareStatus { shared, dismissed, unavailable }

/// Result of invoking the share workflow.
class InviteShareOutcome {
  final InviteShareStatus status;
  final String link;

  const InviteShareOutcome({
    required this.status,
    required this.link,
  });
}

/// Status values for invite email sending flow.
enum InviteEmailStatus {
  sent,
  invalidEmail,
  missingConfiguration,
  timeout,
  handshakeFailure,
  failed,
}

/// Result returned after attempting to send an invitation email.
class InviteEmailSendResult {
  final InviteEmailStatus status;
  final String recipientEmail;
  final String? message;

  const InviteEmailSendResult({
    required this.status,
    required this.recipientEmail,
    this.message,
  });

  bool get isSuccess => status == InviteEmailStatus.sent;
}

/// Details extracted from OrbitDB for a shared workspace invite.
class ResolvedInvite {
  final InviteLinkData linkData;
  final String workspaceName;
  final String channelName;
  final bool slugMatchesWorkspace;

  const ResolvedInvite({
    required this.linkData,
    required this.workspaceName,
    required this.channelName,
    required this.slugMatchesWorkspace,
  });
}

/// Details extracted from OrbitDB for a shared workspace invite.
