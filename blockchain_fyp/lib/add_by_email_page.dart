import 'package:flutter/material.dart';

import 'services/invite_service.dart';

class AddByEmailPage extends StatefulWidget {
  final String workspaceName;
  final String userAddress;

  const AddByEmailPage({
    super.key,
    required this.workspaceName,
    required this.userAddress,
  });

  @override
  State<AddByEmailPage> createState() => _AddByEmailPageState();
}

class _AddByEmailPageState extends State<AddByEmailPage> {
  final TextEditingController _controller = TextEditingController();
  bool _canSend = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _canSend = _controller.text.trim().isNotEmpty;
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
        title: const Text(
          'Add by Email',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: (_canSend && !_isSending) ? _handleSend : null,
            child: _isSending
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Send',
                    style: TextStyle(
                      color: _canSend ? Colors.white : Colors.white38,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF232B3E),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.search, color: Colors.white38, size: 26),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: Colors.white, fontSize: 17),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'name@example.com',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 17),
                        contentPadding: EdgeInsets.symmetric(vertical: 18),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSend() async {
    setState(() {
      _isSending = true;
    });

    final email = _controller.text.trim();
    final result = await InviteService.sendWorkspaceInviteEmail(
      recipientEmail: email,
      workspaceName: widget.workspaceName,
      inviterAddress: widget.userAddress,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSending = false;
    });

    if (result.isSuccess) {
      Navigator.pop(context, result);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message ?? 'Failed to send invitation email.'),
      ),
    );
  }
} 