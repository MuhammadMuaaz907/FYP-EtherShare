import 'dart:async';
import 'package:flutter/material.dart';
import 'workspace_home_page.dart';
import 'services/distributed_service.dart';
import 'services/session_service.dart';

class ChannelPreviewPage extends StatefulWidget {
  final String workspaceName;
  final String channelName;
  final String userAddress;
  const ChannelPreviewPage(
      {super.key,
      required this.workspaceName,
      required this.channelName,
      required this.userAddress});

  @override
  State<ChannelPreviewPage> createState() => _ChannelPreviewPageState();
}

class _ChannelPreviewPageState extends State<ChannelPreviewPage> {
  bool _isLoading = false;
  bool _isProcessing = false; // Prevent multiple simultaneous calls

  /// Safely updates state only if widget is still mounted
  void _safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  Future<void> _createWorkspaceAndNavigate() async {
    // Prevent multiple simultaneous calls
    if (_isProcessing) {
      print('⚠️ Workspace creation already in progress, ignoring duplicate call');
      return;
    }

    _isProcessing = true;
    _safeSetState(() {
      _isLoading = true;
    });

    try {
      print('🚀 Starting workspace creation: ${widget.workspaceName} for user: ${widget.userAddress}');
      
      // Step 1: Create workspace with timeout
      if (!mounted) {
        _isProcessing = false;
        return;
      }
      
      String? workspaceId;
      try {
        workspaceId = await DistributedService.createWorkspace(
          workspaceName: widget.workspaceName,
          inviterAddress: widget.userAddress,
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException('Workspace creation timed out. Please check your network connection.');
          },
        );
      } catch (e) {
        print('❌ Workspace creation error: $e');
        _isProcessing = false;
        
        if (!mounted) return;
        
        String errorMessage = 'Failed to create workspace. Please try again.';
        if (e.toString().contains('already have a workspace')) {
          errorMessage = 'You already have a workspace with this name. Please choose a different name.';
        } else if (e.toString().contains('timeout') || e.toString().contains('Timeout')) {
          errorMessage = 'Connection timeout. Please check your network and try again.';
        } else if (e.toString().contains('Connection')) {
          errorMessage = 'Network error. Please check your connection.';
        }
        
        _safeSetState(() {
          _isLoading = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }
        return;
      }
      
      if (workspaceId == null || !mounted) {
        _isProcessing = false;
        _safeSetState(() {
          _isLoading = false;
        });
        return;
      }
      
      print('✅ Workspace created: $workspaceId');
      
      // Step 2: Add creator as member (non-blocking - don't fail if this times out)
      if (mounted) {
        _safeSetState(() {
          // Keep loading state
        });
        
        try {
          // Get creator's display name (with timeout)
          String? creatorDisplayName;
          try {
            final profile = await DistributedService.getUserProfile(widget.userAddress).timeout(
              const Duration(seconds: 5),
              onTimeout: () => null,
            ).catchError((e) {
              print('⚠️ Error fetching profile for member: $e');
              return null;
            });
            
            if (profile != null) {
              creatorDisplayName = profile['username']?.toString();
            }
          } catch (e) {
            print('⚠️ Error getting creator profile: $e');
          }
          
          // Add member (with timeout, but don't fail if this fails)
          await DistributedService.addWorkspaceMember(
            workspaceId: workspaceId,
            memberAddress: widget.userAddress,
            displayName: creatorDisplayName,
          ).timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              print('⚠️ Add member timed out, continuing anyway');
              return false;
            },
          ).catchError((e) {
            print('⚠️ Failed to add creator as member (non-critical): $e');
            return false;
          });
          
          print('✅ Creator added as workspace member');
        } catch (e) {
          print('⚠️ Error adding creator as member (non-critical): $e');
          // Continue anyway - workspace is created
        }
      }
      
      if (!mounted) {
        _isProcessing = false;
        return;
      }
      
      // Step 3: Save login session
      try {
        await SessionService.saveLoginSession(
          widget.userAddress,
          widget.workspaceName,
          widget.channelName.isNotEmpty ? widget.channelName : 'general',
        );
        print('✅ Login session saved');
      } catch (e) {
        print('⚠️ Error saving session: $e');
        // Continue anyway
      }
      
      if (!mounted) {
        _isProcessing = false;
        return;
      }
      
      // Step 4: Navigate to workspace home
      _isProcessing = false;
      _safeSetState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        // Use pushReplacement to replace current screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TeamHomePage(
              workspaceName: widget.workspaceName,
              channelName: widget.channelName.isNotEmpty ? widget.channelName : 'general',
            ),
          ),
        );
      }
    } catch (e) {
      print('❌ Unexpected error in workspace creation: $e');
      _isProcessing = false;
      _safeSetState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An unexpected error occurred. Please try again.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1284E4),
        body: SafeArea(
          top: true,
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                flex: 8,
                child: Container(
                  width: 100,
                  height: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1284E4),
                  ),
                  alignment: AlignmentDirectional(0, -1),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 75.58,
                          decoration: const BoxDecoration(
                            color: Color(0xFF1284E4),
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(16),
                              bottomRight: Radius.circular(16),
                              topLeft: Radius.circular(0),
                              topRight: Radius.circular(0),
                            ),
                          ),
                          alignment: AlignmentDirectional(-1, 0),
                        ),
                        Align(
                          alignment: AlignmentDirectional(0, 0),
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Align(
                                  alignment: AlignmentDirectional(0, 0),
                                  child: Text(
                                    'Hurray! Everthing done',
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                          fontFamily: 'Inter',
                                          color: Colors.white,
                                          fontSize: 28,
                                          letterSpacing: 0.0,
                                          fontWeight: FontWeight.bold,
                                        ) ?? const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: AlignmentDirectional(0, 0),
                                  child: Text(
                                    " Meet your team's first channel: #${widget.channelName.isNotEmpty ? widget.channelName : 'Work'} ",
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          fontFamily: 'Inter',
                                          color: Colors.white,
                                          fontSize: 20,
                                          letterSpacing: 0.0,
                                          fontWeight: FontWeight.w500,
                                        ) ?? const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Align(
                                  alignment: AlignmentDirectional(0, 0),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      'https://storage.googleapis.com/flutterflow-io-6f20.appspot.com/projects/ether-4gst3t/assets/txhdyp1lfn7e/Channel.png',
                                      width: 400,
                                      height: 300,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        // Fallback to a placeholder if image fails
                                        return Container(
                                          width: 400,
                                          height: 300,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                            Icons.chat_bubble_outline,
                                            size: 80,
                                            color: Colors.white,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: AlignmentDirectional(0, 0),
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(0, 12, 0, 24),
                                    child: Text(
                                      'A channel brings together every part of your project so your team can get more done',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                            fontFamily: 'Inter',
                                            color: Colors.white,
                                            letterSpacing: 0.0,
                                          ) ?? const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                          ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                  child: SizedBox(
                                    width: MediaQuery.of(context).size.width > 400 ? 370 : double.infinity,
                                    height: 44,
                                    child: FilledButton(
                                      onPressed: (_isLoading || _isProcessing) ? null : _createWorkspaceAndNavigate,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF0F365F),
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
                                        elevation: 3,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Text(
                                              'See your channel in EtherShare',
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
                      ],
                    ),
                  ),
                ),
              ),
              if (MediaQuery.of(context).size.width > 768)
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      width: 100,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        image: const DecorationImage(
                          fit: BoxFit.cover,
                          image: NetworkImage(
                            'https://images.unsplash.com/photo-1514924013411-cbf25faa35bb?ixlib=rb-4.0.3&ixid=MnwxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8&auto=format&fit=crop&w=1380&q=80',
                          ),
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

}
