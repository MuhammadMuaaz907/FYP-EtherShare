import 'package:flutter/material.dart';
import 'invite_teammates_page.dart';

class WorkspaceNamePage extends StatefulWidget {
  const WorkspaceNamePage({super.key});

  @override
  State<WorkspaceNamePage> createState() => _WorkspaceNamePageState();
}

class _WorkspaceNamePageState extends State<WorkspaceNamePage> {
  final TextEditingController _controller = TextEditingController();
  bool _isButtonEnabled = false;

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
                  "What's the name of your company or team?",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'This will be the name of your workspace.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 32),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF232B3E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                      hintText: 'Ex. Acme or Acme Marketing',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 16),
                    ),
                  ),
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
                                builder: (_) => InviteTeammatesPage(
                                  workspaceName: _controller.text.trim(),
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
                const SizedBox(height: 32),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                    children: [
                      const TextSpan(text: 'By continuing, you’re agreeing to our '),
                      TextSpan(
                        text: 'Main Services Agreement',
                        style: const TextStyle(color: Colors.lightBlueAccent, decoration: TextDecoration.underline),
                        // onTap logic can be added with GestureDetector if needed
                      ),
                      const TextSpan(text: ', '),
                      TextSpan(
                        text: 'User Terms of Service',
                        style: const TextStyle(color: Colors.lightBlueAccent, decoration: TextDecoration.underline),
                      ),
                      const TextSpan(text: ', and '),
                      TextSpan(
                        text: 'Supplemental Terms',
                        style: const TextStyle(color: Colors.lightBlueAccent, decoration: TextDecoration.underline),
                      ),
                      const TextSpan(text: '. Additional disclosures are available in our '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: const TextStyle(color: Colors.lightBlueAccent, decoration: TextDecoration.underline),
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Cookie Policy',
                        style: const TextStyle(color: Colors.lightBlueAccent, decoration: TextDecoration.underline),
                      ),
                      const TextSpan(text: '.'),
                    ],
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