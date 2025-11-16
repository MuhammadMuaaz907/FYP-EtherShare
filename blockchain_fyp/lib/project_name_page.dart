import 'package:flutter/material.dart';
import 'workspace_preview_page.dart';

class ProjectNamePage extends StatefulWidget {
  final String workspaceName;
  final String userAddress;
  const ProjectNamePage({super.key, required this.workspaceName, required this.userAddress});

  @override
  State<ProjectNamePage> createState() => _ProjectNamePageState();
}

class _ProjectNamePageState extends State<ProjectNamePage> {
  final TextEditingController _controller = TextEditingController();
  bool _isButtonEnabled = false;
  static const int maxLength = 80;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _isButtonEnabled = _controller.text.trim().isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
        ),
        body: SafeArea(
          top: true,
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 32),
                    Text(
                      "What's a project your team is working on?",
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
                      'This could be anything: a project, campaign, event, or the deal you\'re trying to close.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamily: 'Inter',
                            letterSpacing: 0.0,
                          ) ?? const TextStyle(
                            fontSize: 16,
                          ),
                    ),
                    const SizedBox(height: 32),
                    Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFE0E0E0),
                              width: 2,
                            ),
                          ),
                          child: TextField(
                            controller: _controller,
                            maxLength: maxLength,
                            autofocus: true,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontFamily: 'Inter',
                                  letterSpacing: 0.0,
                                ) ?? const TextStyle(
                                  fontSize: 14,
                                ),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                              hintText: 'Ex. Q4 Budget, Website Update...',
                              hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontFamily: 'Inter',
                                    color: Colors.grey[400],
                                    letterSpacing: 0.0,
                                  ) ?? TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 14,
                                  ),
                              counterText: '',
                            ),
                          ),
                        ),
                        Positioned(
                          right: 12,
                          bottom: 8,
                          child: Text(
                            '${_controller.text.length}/$maxLength',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontFamily: 'Inter',
                                  color: Colors.grey[400],
                                  fontSize: 13,
                                  letterSpacing: 0.0,
                                ) ?? TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 13,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: MediaQuery.of(context).size.width > 400 ? 370 : double.infinity,
                      height: 44,
                      child: FilledButton(
                        onPressed: _isButtonEnabled
                            ? () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChannelPreviewPage(
                                      workspaceName: widget.workspaceName,
                                      channelName: _controller.text.trim(),
                                      userAddress: widget.userAddress,
                                    ),
                                  ),
                                );
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
                          disabledBackgroundColor: const Color(0xFF0F365F),
                          disabledForegroundColor: Colors.white.withOpacity(0.6),
                        ),
                        child: Text(
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
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
} 