import 'package:flutter/material.dart';
import 'workspace_preview_page.dart';

class ProjectNamePage extends StatefulWidget {
  final String workspaceName;
  const ProjectNamePage({super.key, required this.workspaceName});

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
    return Scaffold(
      backgroundColor: const Color(0xFF1A2236),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
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
                const Text(
                  "What's a project your team is working on?",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'This could be anything: a project, campaign, event, or the deal you’re trying to close.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 32),
                Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF232B3E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: TextField(
                        controller: _controller,
                        maxLength: maxLength,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                          hintText: 'Ex. Q4 Budget, Website Update...',
                          hintStyle: TextStyle(color: Colors.white38, fontSize: 16),
                          counterText: '',
                        ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 8,
                      child: Text(
                        '${_controller.text.length}/$maxLength',
                        style: const TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isButtonEnabled
                        ? () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChannelPreviewPage(
                                  workspaceName: widget.workspaceName,
                                  channelName: _controller.text.trim(),
                                ),
                              ),
                            );
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      disabledBackgroundColor: Colors.blueGrey[900],
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
} 