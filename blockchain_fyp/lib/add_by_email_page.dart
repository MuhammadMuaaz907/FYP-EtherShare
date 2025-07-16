import 'package:flutter/material.dart';
import 'project_name_page.dart';
import 'invite_teammates_page.dart';

class AddByEmailPage extends StatefulWidget {
  const AddByEmailPage({super.key});

  @override
  State<AddByEmailPage> createState() => _AddByEmailPageState();
}

class _AddByEmailPageState extends State<AddByEmailPage> {
  final TextEditingController _controller = TextEditingController();
  bool _canSend = false;

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
            onPressed: _canSend ? () {} : null,
            child: Text(
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
} 