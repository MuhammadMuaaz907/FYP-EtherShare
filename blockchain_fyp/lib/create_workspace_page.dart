import 'package:flutter/material.dart';

import 'screens/accept_invite_screen.dart';
import 'services/invite_link_manager.dart';
import 'services/invite_service.dart';
import 'workspace_name_page.dart';

class CreateWorkspacePage extends StatefulWidget {
  final String userAddress;
  const CreateWorkspacePage({super.key, required this.userAddress});

  @override
  State<CreateWorkspacePage> createState() => _CreateWorkspacePageState();
}

class _CreateWorkspacePageState extends State<CreateWorkspacePage> {
  bool _isJoining = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2236),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Get Started',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 16),
                child: Icon(
                  Icons.rocket_launch,
                  size: 120,
                  color: Colors.white24,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Ready to launch',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'You’re all set to start a new workspace for your organization.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 280,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            WorkspaceNamePage(userAddress: widget.userAddress),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF23C16B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle:
                        const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Create a workspace'),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 280,
                child: OutlinedButton(
                  onPressed: _isJoining ? null : _handleJoinExistingWorkspace,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Colors.white30, width: 1.2),
                    foregroundColor: Colors.white,
                  ),
                  child: _isJoining
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Join an existing workspace'),
                ),
              ),
              const SizedBox(height: 36),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  children: [
                    const Text(
                      "We couldn't find existing workspaces for your email. If that's a mistake, ask your admin for an invitation or ",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                    GestureDetector(
                      onTap: () {
                        // TODO: Add your logic for trying another email address
                      },
                      child: const Text(
                        'try another email address.',
                        style: TextStyle(
                          color: Colors.lightBlueAccent,
                          fontSize: 14,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleJoinExistingWorkspace() async {
    final textController = TextEditingController();
    final link = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Join workspace'),
          content: TextField(
            controller: textController,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'https://ethershare.app/invite?...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, textController.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (!mounted || link == null || link.isEmpty) {
      return;
    }

    final parsed = InviteLinkManager.parseLink(link);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ye link valid nahin lag raha.'),
        ),
      );
      return;
    }

    setState(() {
      _isJoining = true;
    });

    try {
      await InviteLinkManager.instance.setPendingInvite(parsed);
      final resolved = await InviteService.resolveInvite(parsed);

      if (!mounted) {
        return;
      }

      if (resolved == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ye invite abhi kaam nahin kar raha. Admin se link dobara mang lo.'),
          ),
        );
        setState(() {
          _isJoining = false;
        });
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AcceptInviteScreen(
            invite: resolved,
            userAddress: widget.userAddress,
            onComplete: () async {
              await InviteLinkManager.instance.clearPendingInvite();
              if (mounted) {
                setState(() {
                  _isJoining = false;
                });
              }
            },
            onCancel: () async {
              if (mounted) {
                setState(() {
                  _isJoining = false;
                });
              }
            },
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isJoining = false;
        });
      }
    }
  }
}