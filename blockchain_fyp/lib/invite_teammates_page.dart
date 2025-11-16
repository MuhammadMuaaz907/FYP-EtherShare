import 'package:flutter/material.dart';

import 'add_by_email_page.dart';
import 'project_name_page.dart';
import 'services/invite_service.dart';

class InviteTeammatesPage extends StatefulWidget {
  final String workspaceName;
  final String userAddress;
  final bool isFromWorkspaceHome;

  const InviteTeammatesPage({
    super.key,
    required this.workspaceName,
    required this.userAddress,
    this.isFromWorkspaceHome = false,
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

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: Colors.black,
              size: 24,
            ),
            onPressed: () {
              Navigator.pop(context);
            },
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          actions: widget.isFromWorkspaceHome
              ? null
              : [
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: TextButton(
                      onPressed: () => _goToProjectName(context),
                      child: Text(
                        'SKIP',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontFamily: 'Inter',
                              color: const Color(0xFF0F365F),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.0,
                            ) ??
                            const TextStyle(
                              color: Color(0xFF0F365F),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ),
                ],
        ),
        body: SafeArea(
          top: true,
          child: Align(
            alignment: AlignmentDirectional(0, 0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Main Content
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        Text(
                          'Who else is on the ${workspaceName.isNotEmpty ? workspaceName : 'your'} team?',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontFamily: 'Inter',
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.0,
                              ) ?? const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Invite your teammates to your workspace.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontFamily: 'Inter',
                                letterSpacing: 0.0,
                              ) ?? const TextStyle(
                                fontSize: 16,
                              ),
                        ),
                        const SizedBox(height: 32),
                        
                        // Share a Link Button
                        SizedBox(
                          width: MediaQuery.of(context).size.width > 400 ? 370 : double.infinity,
                          child: OutlinedButton.icon(
                            key: _shareButtonKey,
                            onPressed: _isProcessingShare ? null : _handleShareInvite,
                            icon: _isProcessingShare
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF0F365F),
                                    ),
                                  )
                                : const Icon(Icons.link, color: Color(0xFF0F365F)),
                            label: Text(
                              _isProcessingShare ? 'Preparing...' : 'Share a Link',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontFamily: 'Inter',
                                    color: const Color(0xFF0F365F),
                                    fontSize: 16,
                                    letterSpacing: 0.0,
                                  ) ?? const TextStyle(
                                    color: Color(0xFF0F365F),
                                    fontSize: 16,
                                  ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF0F365F), width: 2),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        
                        // Add by email Button
                        SizedBox(
                          width: MediaQuery.of(context).size.width > 400 ? 370 : double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _handleAddByEmail,
                            icon: const Icon(Icons.email_outlined, color: Color(0xFF0F365F)),
                            label: Text(
                              'Add by email',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontFamily: 'Inter',
                                    color: const Color(0xFF0F365F),
                                    fontSize: 16,
                                    letterSpacing: 0.0,
                                  ) ?? const TextStyle(
                                    color: Color(0xFF0F365F),
                                    fontSize: 16,
                                  ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF0F365F), width: 2),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        
                        // Next/Done Button
                        SizedBox(
                          width: MediaQuery.of(context).size.width > 400 ? 370 : double.infinity,
                          height: 44,
                          child: FilledButton(
                            onPressed: widget.isFromWorkspaceHome
                                ? () => _handleDone(context)
                                : (_hasPerformedAction ? () => _goToProjectName(context) : null),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0F365F),
                              foregroundColor: Colors.white,
                              padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
                              elevation: 3,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              disabledBackgroundColor: const Color(0xFF0F365F),
                              disabledForegroundColor: Colors.white.withOpacity(0.6),
                            ),
                            child: Text(
                              widget.isFromWorkspaceHome ? 'Done' : 'Next',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontFamily: 'Inter',
                                    color: Colors.white,
                                    letterSpacing: 0.0,
                                  ) ?? const TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
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

  void _handleDone(BuildContext context) {
    // Navigate back to workspace home
    Navigator.pop(context, true); // Return true to indicate members were added
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