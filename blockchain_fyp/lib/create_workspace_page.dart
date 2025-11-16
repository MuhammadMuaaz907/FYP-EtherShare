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
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          top: true,
          child: Align(
            alignment: AlignmentDirectional(0, 0),
        child: SingleChildScrollView(
          child: Column(
                mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
                  // Header Section
                  Container(
                    width: double.infinity,
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                        topLeft: Radius.circular(0),
                        topRight: Radius.circular(0),
                      ),
                    ),
                    alignment: AlignmentDirectional(0, 0),
                    child: Text(
                      'Get Started',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontFamily: 'Inter',
                            color: Colors.black,
                            fontSize: 22,
                            letterSpacing: 0.0,
                            fontWeight: FontWeight.bold,
                          ) ?? const TextStyle(
                            color: Colors.black,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  
                  // Illustration
                  Align(
                    alignment: AlignmentDirectional(0, 0),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(0, 40, 0, 25),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          'https://storage.googleapis.com/flutterflow-io-6f20.appspot.com/projects/ether-4gst3t/assets/gndl7qs1bd42/4594998.png',
                          width: 150,
                          height: 150,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            // Fallback to icon if network image fails
                            return Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                child: Icon(
                  Icons.rocket_launch,
                                size: 80,
                                color: Colors.grey[400],
                              ),
                            );
                          },
                        ),
                      ),
                ),
              ),
                  
                  // "Ready to launch" Text
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 20),
                    child: Text(
                'Ready to launch',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 20,
                            letterSpacing: 0.0,
                          ) ?? const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                ),
              ),
                  ),
                  
                  // Subtext
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 20),
                child: Text(
                      'You\'re all set to start a new workspace for your organization',
                  textAlign: TextAlign.center,
                      maxLines: 2,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamily: 'Inter',
                            letterSpacing: 0.0,
                          ) ?? const TextStyle(
                            fontSize: 14,
                          ),
                ),
              ),
                  
                  // Create a New Workspace Button
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width > 400 ? 370 : MediaQuery.of(context).size.width * 0.9,
                      height: 44,
                      child: FilledButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            WorkspaceNamePage(userAddress: widget.userAddress),
                      ),
                    );
                  },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0F365F),
                    foregroundColor: Colors.white,
                          padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
                          elevation: 3,
                    shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                        child: Text(
                          'Create a New Workspace',
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
                  ),
                  
                  // Join with Invite Link Button
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width > 400 ? 370 : MediaQuery.of(context).size.width * 0.9,
                      height: 44,
                      child: FilledButton(
                  onPressed: _isJoining ? null : _handleJoinExistingWorkspace,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0F365F),
                          foregroundColor: Colors.white,
                          padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                  ),
                  child: _isJoining
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                ),
                              )
                            : Text(
                                'Join with Invite Link',
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
                    ),
                  ],
                ),
              ),
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
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F365F).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.link,
                  color: Color(0xFF0F365F),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Join Workspace',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontFamily: 'Inter',
                        color: Colors.black,
                        fontSize: 20,
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.bold,
                      ) ?? const TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the invite link to join an existing workspace',
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
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                autofocus: true,
                minLines: 1,
                maxLines: 3,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'Inter',
                      color: Colors.black,
                      letterSpacing: 0.0,
                    ) ?? const TextStyle(
                      color: Colors.black,
                    ),
                decoration: InputDecoration(
                  hintText: 'https://ethershare.app/invite?...',
                  hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFamily: 'Inter',
                        color: Colors.grey[400],
                        letterSpacing: 0.0,
                      ) ?? TextStyle(
                        color: Colors.grey[400],
                      ),
                  prefixIcon: const Icon(
                    Icons.link,
                    color: Color(0xFF0F365F),
                    size: 20,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF0F365F),
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Cancel',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'Inter',
                      color: Colors.grey[600],
                      fontSize: 16,
                      letterSpacing: 0.0,
                      fontWeight: FontWeight.w500,
                    ) ?? TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, textController.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F365F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Continue',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'Inter',
                      color: Colors.white,
                      fontSize: 16,
                      letterSpacing: 0.0,
                      fontWeight: FontWeight.w600,
                    ) ?? const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
              ),
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