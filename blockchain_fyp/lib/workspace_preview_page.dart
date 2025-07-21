import 'package:flutter/material.dart';
import 'workspace_home_page.dart';
import 'services/orbitdb_service.dart';
import 'dart:convert';

class ChannelPreviewPage extends StatelessWidget {
  final String workspaceName;
  final String channelName;
  final String userAddress;
  const ChannelPreviewPage(
      {super.key,
      required this.workspaceName,
      required this.channelName,
      required this.userAddress});

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
              children: [
                const SizedBox(height: 32),
                Text(
                  "Tada! Meet your team's first channel: #${channelName.isNotEmpty ? channelName : 'Work'}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 32),
                // Mockup phone screen
                Container(
                  width: 280,
                  height: 400,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Top bar
                      Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(left: 16),
                              child:
                                  Text('1:32', style: TextStyle(fontSize: 14)),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.tag, size: 16),
                            const Icon(Icons.arrow_back, size: 16),
                            const Spacer(),
                            const Icon(Icons.search, size: 16),
                            const SizedBox(width: 8),
                            const Icon(Icons.info_outline, size: 16),
                            const SizedBox(width: 16),
                          ],
                        ),
                      ),
                      // Chat content
                      Expanded(
                        child: Container(
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Messages
                                _buildMessage(
                                    'Hey team! How\'s the project going?',
                                    Colors.yellow),
                                _buildReactions(),
                                const SizedBox(height: 8),
                                _buildMessage('Great progress on the frontend!',
                                    Colors.pink),
                                _buildMessage('Backend API is almost ready',
                                    Colors.green),
                                _buildMessage(
                                    'Design review scheduled for tomorrow',
                                    Colors.grey),
                                _buildMessage(
                                    'Meeting notes from today\'s standup',
                                    Colors.lightBlue),
                                _buildAttachment(),
                                const SizedBox(height: 8),
                                _buildMessage(
                                    'Thanks everyone!', Colors.yellow),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Bottom navigation
                      Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(20),
                            bottomRight: Radius.circular(20),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(left: 16),
                              child: Icon(Icons.arrow_back, size: 16),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 20,
                              height: 2,
                              color: Colors.grey[600],
                            ),
                            const Spacer(),
                            const Icon(Icons.flash_on, size: 16),
                            const SizedBox(width: 8),
                            const Icon(Icons.camera_alt, size: 16),
                            const SizedBox(width: 8),
                            const Icon(Icons.photo_library, size: 16),
                            const SizedBox(width: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'A channel brings together every part of your project so your team can get more done.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      // Save workspace for user in OrbitDB
                      final orbitdb = OrbitDBService();
                      final key = userAddress.toLowerCase().trim();
                      final workspaceDetails = jsonEncode({
                        'workspaceName': workspaceName,
                        'channelName': channelName,
                      });
                      print(
                          'Saving workspace for key: $key, value: $workspaceDetails');
                      await orbitdb.saveWorkspaceForUser(key, workspaceDetails);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TeamHomePage(
                            workspaceName: workspaceName,
                            channelName: channelName,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF23C16B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('See your channel in EtherShare'),
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

  Widget _buildMessage(String text, Color userColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: userColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 12,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactions() {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: Row(
        children: [
          _buildReaction(Icons.star, '7'),
          const SizedBox(width: 4),
          _buildReaction(Icons.thumb_up, '5'),
          const SizedBox(width: 4),
          _buildReaction(Icons.lightbulb, '4'),
          const SizedBox(width: 4),
          _buildReaction(Icons.favorite, '1'),
          const SizedBox(width: 4),
          _buildReaction(Icons.person, ''),
        ],
      ),
    );
  }

  Widget _buildReaction(IconData icon, String count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey[600]),
          if (count.isNotEmpty) ...[
            const SizedBox(width: 2),
            Text(count,
                style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          ],
        ],
      ),
    );
  }

  Widget _buildAttachment() {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.description, size: 16, color: Colors.grey),
            const SizedBox(width: 8),
            Container(
              width: 60,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
