import 'package:flutter/material.dart';

import '../services/invite_service.dart';
import '../services/orbitdb_service.dart';
import '../workspace_home_page.dart';

class AcceptInviteScreen extends StatefulWidget {
  final ResolvedInvite invite;
  final String userAddress;
  final Future<void> Function() onComplete;
  final Future<void> Function()? onCancel;

  const AcceptInviteScreen({
    super.key,
    required this.invite,
    required this.userAddress,
    required this.onComplete,
    this.onCancel,
  });

  @override
  State<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends State<AcceptInviteScreen> {
  bool _isJoining = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final invite = widget.invite;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F365F),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Workspace Invitation',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontFamily: 'Inter',
                color: Colors.white,
                fontSize: 20,
                letterSpacing: 0.0,
                fontWeight: FontWeight.w600,
              ) ?? const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
        ),
        actions: [
          TextButton(
            onPressed: _isJoining
                ? null
                : () async {
                    final navigator = Navigator.of(context);
                    if (widget.onCancel != null) {
                      await widget.onCancel!();
                    }
                    if (!mounted) {
                      return;
                    }
                    navigator.pop();
                  },
            child: Text(
              'Dismiss',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'Inter',
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 16,
                    letterSpacing: 0.0,
                    fontWeight: FontWeight.w500,
                  ) ?? TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                // Header Icon
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F365F).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.group_add,
                      size: 48,
                      color: Color(0xFF0F365F),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Join ${invite.workspaceName}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontFamily: 'Inter',
                        color: Colors.black,
                        fontSize: 24,
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.bold,
                      ) ?? const TextStyle(
                        color: Colors.black,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You will gain access to the workspace and channel above. Your wallet address will be added as a member.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFamily: 'Inter',
                        color: Colors.black87,
                        fontSize: 14,
                        letterSpacing: 0.0,
                      ) ?? const TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                      ),
                ),
                const SizedBox(height: 32),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF0F365F).withOpacity(0.3),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F365F).withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow(Icons.person_outline, 'Invited by',
                          invite.linkData.inviterAddress),
                      const SizedBox(height: 20),
                      _infoRow(
                          Icons.tag_outlined, 'Default channel', invite.channelName),
                      const SizedBox(height: 20),
                      _infoRow(
                          Icons.link, 'Workspace link', invite.linkData.workspaceSlug),
                      if (!invite.slugMatchesWorkspace) ...[
                        const SizedBox(height: 20),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange[200]!,
                              width: 1,
                            ),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.orange[700],
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Heads up: the workspace name changed after this invite was created.',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        fontFamily: 'Inter',
                                        color: Colors.orange[800],
                                        fontSize: 13,
                                        letterSpacing: 0.0,
                                      ) ?? TextStyle(
                                        color: Colors.orange[800],
                                        fontSize: 13,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                if (_error != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red[300]!,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.red[700],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _error!,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontFamily: 'Inter',
                                  color: Colors.red[800],
                                  fontSize: 14,
                                  letterSpacing: 0.0,
                                  fontWeight: FontWeight.w500,
                                ) ?? TextStyle(
                                  color: Colors.red[800],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isJoining ? null : _handleJoinWorkspace,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F365F),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      minimumSize: const Size(double.infinity, 56),
                      alignment: Alignment.center,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isJoining
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'Join Workspace',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontFamily: 'Inter',
                                  color: Colors.white,
                                  fontSize: 16,
                                  letterSpacing: 0.0,
                                  fontWeight: FontWeight.bold,
                                ) ?? const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F365F).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF0F365F),
            size: 20,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'Inter',
                      color: Colors.grey[600],
                      fontSize: 12,
                      letterSpacing: 0.0,
                      fontWeight: FontWeight.w500,
                    ) ?? TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontFamily: 'Inter',
                      color: Colors.black,
                      fontSize: 16,
                      letterSpacing: 0.0,
                      fontWeight: FontWeight.w600,
                    ) ?? const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleJoinWorkspace() async {
    setState(() {
      _isJoining = true;
      _error = null;
    });

    try {
      final success = await InviteService.applyInviteForUser(
        invite: widget.invite,
        inviteeAddress: widget.userAddress,
      );

      if (!success) {
        throw Exception('Unable to save workspace for your account.');
      }

      await OrbitDBService.saveLoginSession(
        widget.userAddress,
        widget.invite.workspaceName,
        widget.invite.channelName,
      );

      await widget.onComplete();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => TeamHomePage(
            workspaceName: widget.invite.workspaceName,
            channelName: widget.invite.channelName,
          ),
        ),
        (route) => false,
      );
    } catch (error) {
      setState(() {
        _error = error.toString();
        _isJoining = false;
      });
    }
  }
}

