import 'package:flutter/material.dart';
import 'channel_page.dart';

class TeamHomePage extends StatefulWidget {
  final String workspaceName;
  final String channelName;
  const TeamHomePage({super.key, required this.workspaceName, required this.channelName});

  @override
  State<TeamHomePage> createState() => _TeamHomePageState();
}

class _TeamHomePageState extends State<TeamHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2236),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(110),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4F0E5E), Color(0xFF350D36)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.circle, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.workspaceName.isNotEmpty ? widget.workspaceName : 'OnlineWork',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                      ),
                      const Spacer(),
                      CircleAvatar(
                        backgroundColor: Colors.white,
                        radius: 18,
                        child: Icon(Icons.person, color: Color(0xFF4F0E5E)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFF5F2B6B),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 10),
                              const Icon(Icons.search, color: Colors.white54),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Jump to or search...',
                                  style: TextStyle(color: Colors.white54, fontSize: 16),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF5F2B6B),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.tune, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _quickAction(Icons.bookmark_border, 'Later'),
                _quickAction(Icons.play_arrow, 'Drafts & Sent'),
                _quickAction(Icons.headphones, 'Huddles'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text('Channels', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          _channelTile('# general'),
          _channelTile('# random'),
          _channelTile('# ${widget.channelName.isNotEmpty ? widget.channelName : 'work'}', trailing: _startHere()),
          _addChannelTile(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text('Direct messages', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          _dmTile('onlinework3517 (you)'),
          _addTeammatesTile(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF5F2B6B),
        onPressed: () {},
        child: const Icon(Icons.add, color: Colors.white),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF232B3E),
        selectedItemColor: const Color(0xFF4F0E5E),
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.forum), label: 'DMs'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Activity'),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
        currentIndex: 0,
        onTap: (i) {},
      ),
    );
  }

  Widget _quickAction(IconData icon, String label) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF232B3E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }

  Widget _channelTile(String name, {Widget? trailing}) {
    return ListTile(
      leading: const Icon(Icons.tag, color: Colors.white54),
      title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 16)),
      trailing: trailing != null
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 100),
              child: trailing,
            )
          : null,
      onTap: () {
        final channel = name.replaceAll('#', '').trim();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChannelPage(
              channelName: channel,
              workspaceName: widget.workspaceName,
            ),
          ),
        );
      },
    );
  }

  Widget _addChannelTile() {
    return ListTile(
      leading: const Icon(Icons.add, color: Colors.white54),
      title: const Text('Add channel', style: TextStyle(color: Colors.white, fontSize: 16)),
      onTap: () {},
    );
  }

  Widget _dmTile(String name) {
    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Colors.white,
        child: Icon(Icons.person, color: Color(0xFF4F0E5E)),
      ),
      title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 16)),
      onTap: () {},
    );
  }

  Widget _addTeammatesTile() {
    return ListTile(
      leading: const Icon(Icons.add, color: Colors.white54),
      title: const Text('Add teammates', style: TextStyle(color: Colors.white, fontSize: 16)),
      onTap: () {},
    );
  }

  Widget _startHere() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.yellow[700],
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.touch_app, size: 16, color: Colors.black),
          SizedBox(width: 4),
          Text('Start here', style: TextStyle(color: Colors.black, fontSize: 13)),
        ],
      ),
    );
  }
} 