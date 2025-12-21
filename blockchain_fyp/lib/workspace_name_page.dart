import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'invite_teammates_page.dart';
import 'services/distributed_service.dart';

class WorkspaceNamePage extends StatefulWidget {
  final String userAddress;
  const WorkspaceNamePage({super.key, required this.userAddress});

  @override
  State<WorkspaceNamePage> createState() => _WorkspaceNamePageState();
}

class _WorkspaceNamePageState extends State<WorkspaceNamePage> {
  final TextEditingController _controller = TextEditingController();
  bool _isButtonEnabled = false;
  bool _isChecking = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _isButtonEnabled = _controller.text.trim().isNotEmpty;
        _errorMessage = null; // Clear error when user types
      });
    });
  }
  
  Future<bool> _checkDuplicateWorkspace(String workspaceName) async {
    try {
      final existingWorkspaces = await DistributedService.getUserWorkspaces(widget.userAddress);
      final normalizedInput = workspaceName.trim().toLowerCase();
      
      final duplicateWorkspace = existingWorkspaces.firstWhere(
        (ws) => (ws['name']?.toString() ?? '').trim().toLowerCase() == normalizedInput,
        orElse: () => <String, dynamic>{},
      );
      
      return duplicateWorkspace.isNotEmpty;
    } catch (e) {
      print('⚠️ Error checking duplicate workspace: $e');
      return false; // Allow creation if check fails (backend will catch it)
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width > 768;
  }

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
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                flex: 8,
                child: Container(
                  width: 100,
                  height: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                  ),
                  alignment: AlignmentDirectional(0, -1),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Header Section
                        Container(
                          width: double.infinity,
                          height: 140,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(16),
                              bottomRight: Radius.circular(16),
                              topLeft: Radius.circular(0),
                              topRight: Radius.circular(0),
                            ),
                          ),
                          alignment: AlignmentDirectional(-1, 0),
                          child: Align(
                            alignment: AlignmentDirectional(-1, -1),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: IconButton(
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
                            ),
                          ),
                        ),
                        
                        // Main Content
                        Align(
                          alignment: AlignmentDirectional(0, 0),
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title
                                Text(
                                  'What\'s the name of your company or team?',
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                        fontFamily: 'Inter',
                                        fontSize: 31,
                                        letterSpacing: 0.0,
                                        fontWeight: FontWeight.bold,
                                      ) ?? const TextStyle(
                                        fontSize: 31,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                
                                // Subtitle
                                Align(
                                  alignment: AlignmentDirectional(0, 0),
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(0, 12, 0, 24),
                                    child: Text(
                                      'This will be the name of your workspace.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                            fontFamily: 'Inter',
                                            letterSpacing: 0.0,
                                          ) ?? const TextStyle(
                                            fontSize: 14,
                                          ),
                                    ),
                                  ),
                                ),
                                
                                // Input Field
                                Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                  child: SizedBox(
                                    width: MediaQuery.of(context).size.width > 400 ? 370 : double.infinity,
                                    child: TextFormField(
                                      controller: _controller,
                                      autofocus: true,
                                      decoration: InputDecoration(
                                        labelText: 'Eg. Xenox Marketing',
                                        labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                                              fontFamily: 'Inter',
                                              letterSpacing: 0.0,
                                            ) ?? const TextStyle(
                                              fontSize: 14,
                                            ),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: const BorderSide(
                                            color: Color(0xFFE0E0E0),
                                            width: 2,
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderSide: const BorderSide(
                                            color: Color(0xFF0F365F),
                                            width: 2,
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        errorBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: Theme.of(context).colorScheme.error,
                                            width: 2,
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        focusedErrorBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: Theme.of(context).colorScheme.error,
                                            width: 2,
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        filled: true,
                                        fillColor: const Color(0xFFF5F5F5),
                                      ),
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            fontFamily: 'Inter',
                                            letterSpacing: 0.0,
                                          ) ?? const TextStyle(
                                            fontSize: 14,
                                          ),
                                    ),
                                  ),
                                ),
                                
                                // Error Message
                                if (_errorMessage != null)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                    child: Container(
                                      width: MediaQuery.of(context).size.width > 400 ? 370 : double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.red[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.red[300]!),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _errorMessage!,
                                              style: TextStyle(
                                                color: Colors.red[700],
                                                fontSize: 14,
                                                fontFamily: 'Inter',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                
                                // Next Button
                                Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                  child: SizedBox(
                                    width: MediaQuery.of(context).size.width > 400 ? 370 : double.infinity,
                                    height: 44,
                                    child: FilledButton(
                                      onPressed: (_isButtonEnabled && !_isChecking)
                                          ? () async {
                                              final workspaceName = _controller.text.trim();
                                              
                                              if (workspaceName.isEmpty) {
                                                return;
                                              }
                                              
                                              setState(() {
                                                _isChecking = true;
                                                _errorMessage = null;
                                              });
                                              
                                              // Check for duplicate workspace name
                                              final isDuplicate = await _checkDuplicateWorkspace(workspaceName);
                                              
                                              if (mounted) {
                                                setState(() {
                                                  _isChecking = false;
                                                });
                                                
                                                if (isDuplicate) {
                                                  setState(() {
                                                    _errorMessage = 'You already have a workspace named "$workspaceName". Please choose a different name.';
                                                  });
                                                  return;
                                                }
                                                
                                                // Navigate to next page
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => InviteTeammatesPage(
                                                      workspaceName: workspaceName,
                                                      userAddress: widget.userAddress,
                                                    ),
                                                  ),
                                                );
                                              }
                                            }
                                          : null,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF0F365F),
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
                                        elevation: 3,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        disabledBackgroundColor: Colors.grey[300],
                                        disabledForegroundColor: Colors.grey[600],
                                      ),
                                      child: _isChecking
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Text(
                                              'Next',
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
                                
                                // Terms and Conditions
                                Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(0, 12, 0, 12),
                                  child: RichText(
                                    textScaler: MediaQuery.of(context).textScaler,
                                    textAlign: TextAlign.center,
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: 'By continuing, you\'re agreeing to our ',
                                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                                fontFamily: 'Inter',
                                                letterSpacing: 0.0,
                                              ) ?? const TextStyle(
                                                fontSize: 16,
                                              ),
                                        ),
                                        TextSpan(
                                          text: 'Main Services Agreement, ',
                                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                                fontFamily: 'Inter',
                                                color: const Color(0xFF0F365F),
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.0,
                                              ) ?? const TextStyle(
                                                fontSize: 16,
                                                color: Color(0xFF0F365F),
                                                fontWeight: FontWeight.w600,
                                              ),
                                          mouseCursor: SystemMouseCursors.click,
                                          recognizer: TapGestureRecognizer()
                                            ..onTap = () {
                                              // TODO: Navigate to Main Services Agreement
                                            },
                                        ),
                                        TextSpan(
                                          text: 'User Terms of Service',
                                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                                fontFamily: 'Inter',
                                                color: const Color(0xFF0F365F),
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.0,
                                              ) ?? const TextStyle(
                                                fontSize: 16,
                                                color: Color(0xFF0F365F),
                                                fontWeight: FontWeight.w600,
                                              ),
                                          mouseCursor: SystemMouseCursors.click,
                                          recognizer: TapGestureRecognizer()
                                            ..onTap = () {
                                              // TODO: Navigate to User Terms of Service
                                            },
                                        ),
                                        TextSpan(
                                          text: ', and ',
                                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                                fontFamily: 'Inter',
                                                letterSpacing: 0.0,
                                              ) ?? const TextStyle(
                                                fontSize: 16,
                                              ),
                                        ),
                                        TextSpan(
                                          text: 'Supplemental Terms. ',
                                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                                fontFamily: 'Inter',
                                                color: const Color(0xFF0F365F),
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.0,
                                              ) ?? const TextStyle(
                                                fontSize: 16,
                                                color: Color(0xFF0F365F),
                                                fontWeight: FontWeight.w600,
                                              ),
                                          mouseCursor: SystemMouseCursors.click,
                                          recognizer: TapGestureRecognizer()
                                            ..onTap = () {
                                              // TODO: Navigate to Supplemental Terms
                                            },
                                        ),
                                        TextSpan(
                                          text: 'Additional disclosures are available in our ',
                                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                                fontFamily: 'Inter',
                                                letterSpacing: 0.0,
                                              ) ?? const TextStyle(
                                                fontSize: 16,
                                              ),
                                        ),
                                        TextSpan(
                                          text: 'Privacy Policy ',
                                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                                fontFamily: 'Inter',
                                                color: const Color(0xFF0F365F),
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.0,
                                              ) ?? const TextStyle(
                                                fontSize: 16,
                                                color: Color(0xFF0F365F),
                                                fontWeight: FontWeight.w600,
                                              ),
                                          mouseCursor: SystemMouseCursors.click,
                                          recognizer: TapGestureRecognizer()
                                            ..onTap = () {
                                              // TODO: Navigate to Privacy Policy
                                            },
                                        ),
                                        TextSpan(
                                          text: 'and ',
                                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                                fontFamily: 'Inter',
                                                letterSpacing: 0.0,
                                              ) ?? const TextStyle(
                                                fontSize: 16,
                                              ),
                                        ),
                                        TextSpan(
                                          text: 'Cookie Policy.',
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                fontFamily: 'Inter',
                                                fontWeight: FontWeight.w600,
                                                color: const Color(0xFF0F365F),
                                                fontSize: 16,
                                                letterSpacing: 0.0,
                                              ) ?? const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF0F365F),
                                              ),
                                          mouseCursor: SystemMouseCursors.click,
                                          recognizer: TapGestureRecognizer()
                                            ..onTap = () {
                                              // TODO: Navigate to Cookie Policy
                                            },
                                        ),
                                      ],
                                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                            fontFamily: 'Inter',
                                            letterSpacing: 0.0,
                                          ) ?? const TextStyle(
                                            fontSize: 16,
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
              
              // Desktop Side Panel
              if (_isDesktop(context))
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        'https://images.unsplash.com/photo-1514924013411-cbf25faa35bb?ixlib=rb-4.0.3&ixid=MnwxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8&auto=format&fit=crop&w=1380&q=80',
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: double.infinity,
                            height: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F365F),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          );
                        },
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