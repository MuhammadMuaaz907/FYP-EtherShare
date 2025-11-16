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
          title: Text(
            'Add by Email',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: 'Inter',
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.0,
                ) ?? const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                ),
          ),
          centerTitle: true,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton(
                onPressed: (_canSend && !_isSending) ? _handleSend : null,
                child: _isSending
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF0F365F),
                        ),
                      )
                    : Text(
                        'Send',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontFamily: 'Inter',
                              color: _canSend ? const Color(0xFF0F365F) : Colors.grey[400],
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              letterSpacing: 0.0,
                            ) ?? TextStyle(
                              color: _canSend ? const Color(0xFF0F365F) : Colors.grey[400],
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                      ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFE0E0E0),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Icon(
                          Icons.search,
                          color: Color(0xFF0F365F),
                          size: 24,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          autofocus: true,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontFamily: 'Inter',
                                letterSpacing: 0.0,
                              ) ?? const TextStyle(
                                fontSize: 14,
                              ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'name@example.com',
                            hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontFamily: 'Inter',
                                  color: Colors.grey[400],
                                  letterSpacing: 0.0,
                                ) ?? TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 14,
                                ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 18),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ),
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