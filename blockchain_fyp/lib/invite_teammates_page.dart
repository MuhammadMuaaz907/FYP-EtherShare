import 'package:flutter/material.dart';

import 'add_by_email_page.dart';
import 'project_name_page.dart';
import 'services/invite_service.dart';

class InviteTeammatesPage extends StatefulWidget {
  final String workspaceName;
  final String userAddress;

  const InviteTeammatesPage({
    super.key,
    required this.workspaceName,
    required this.userAddress,
  });

  @override
  State<InviteTeammatesPage> createState() => _InviteTeammatesPageState();
}

class _InviteTeammatesPageState extends State<InviteTeammatesPage> {
  bool _hasPerformedAction = false;
  bool _isProcessingShare = false;
  final GlobalKey _shareButtonKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final workspaceName = widget.workspaceName;

    return Scaffold(
      backgroundColor: const Color(0xFF1A2236),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: () => _goToProjectName(context),
            child: const Text(
              'SKIP',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Text(
                  'Who else is on the ${workspaceName.isNotEmpty ? workspaceName : 'your'} team?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Invite your teammates to your workspace.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  key: _shareButtonKey,
                  onPressed: _isProcessingShare ? null : _handleShareInvite,
                  icon: _isProcessingShare
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white70,
                          ),
                        )
                      : const Icon(Icons.link, color: Colors.white70),
                  label: Text(
                    _isProcessingShare ? 'Preparing...' : 'Share a Link',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24, width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    backgroundColor: Colors.transparent,
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: _handleAddByEmail,
                  icon: const Icon(Icons.email_outlined, color: Colors.white70),
                  label: const Text('Add by email', style: TextStyle(color: Colors.white70, fontSize: 16)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24, width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    backgroundColor: Colors.transparent,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _hasPerformedAction ? () => _goToProjectName(context) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hasPerformedAction ? Colors.blueGrey[700] : Colors.blueGrey[900],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      disabledForegroundColor: Colors.white54,
                    ),
                    child: const Text('Next'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleShareInvite() async {
    setState(() {
      _isProcessingShare = true;
    });

    try {
      final origin = _shareButtonOrigin();
      final outcome = await InviteService.shareWorkspaceInvite(
        workspaceName: widget.workspaceName,
        inviterAddress: widget.userAddress,
        shareOrigin: origin,
      );

      if (!mounted) {
        return;
      }

      if (outcome.status == InviteShareStatus.shared) {
        _markActionCompleted();
        _showSnackBar('Invite link shared successfully.');
      } else {
        final link = await InviteService.copyInviteLinkToClipboard(
          workspaceName: widget.workspaceName,
          inviterAddress: widget.userAddress,
        );

        if (!mounted) {
          return;
        }

        _markActionCompleted();
        final reason = outcome.status == InviteShareStatus.dismissed
            ? 'Share cancelled'
            : 'Sharing unavailable';
        _showSnackBar(
          '$reason. Link copied to clipboard.\nOpen EtherShare and tap "Paste invite link" on the login screen, then paste:\n$link',
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      final link = await InviteService.copyInviteLinkToClipboard(
        workspaceName: widget.workspaceName,
        inviterAddress: widget.userAddress,
      );
      _showSnackBar(
        'Unable to open share sheet. Copy this link, then in EtherShare tap "Paste invite link" on the login screen:\n$link',
      );
      _markActionCompleted();
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingShare = false;
        });
      }
    }
  }

  Rect? _shareButtonOrigin() {
    final renderBox =
        _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return null;
    }
    final offset = renderBox.localToGlobal(Offset.zero);
    return offset & renderBox.size;
  }

  Future<void> _handleAddByEmail() async {
    final result = await Navigator.push<InviteEmailSendResult>(
      context,
      MaterialPageRoute(
        builder: (_) => AddByEmailPage(
          workspaceName: widget.workspaceName,
          userAddress: widget.userAddress,
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    if (result.isSuccess) {
      _markActionCompleted();
      _showSnackBar(
        result.message ?? 'Invitation email sent to ${result.recipientEmail}.',
      );
    } else if (result.message != null) {
      _showSnackBar(result.message!);
    }
  }

  void _goToProjectName(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectNamePage(
          workspaceName: widget.workspaceName,
          userAddress: widget.userAddress,
        ),
      ),
    );
  }

  void _markActionCompleted() {
    if (!_hasPerformedAction) {
      setState(() {
        _hasPerformedAction = true;
      });
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}