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
      backgroundColor: const Color(0xFF1A2236),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Workspace Invitation',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
            child: const Text(
              'Dismiss',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Text(
              'Join ${invite.workspaceName}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF232B3E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow(Icons.person_outline, 'Invited by',
                      invite.linkData.inviterAddress),
                  const SizedBox(height: 16),
                  _infoRow(
                      Icons.tag_outlined, 'Default channel', invite.channelName),
                  const SizedBox(height: 16),
                  _infoRow(
                      Icons.link, 'Workspace link', invite.linkData.workspaceSlug),
                  if (!invite.slugMatchesWorkspace) ...[
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.orange.withAlpha(26),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: const Text(
                        'Heads up: the workspace name changed after this invite was created.',
                        style: TextStyle(color: Colors.orangeAccent),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'You will gain access to the workspace and channel above. Your wallet address will be added as a member.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const Spacer(),
            if (_error != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(31),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isJoining ? null : _handleJoinWorkspace,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF23C16B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
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
                    : const Text('Join Workspace'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white70),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
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

