import 'package:flutter/material.dart';
import '../services/session_service.dart';

class DMsPage extends StatefulWidget {
  final String workspaceName;
  const DMsPage({super.key, required this.workspaceName});

  @override
  State<DMsPage> createState() => _DMsPageState();
}

class _DMsPageState extends State<DMsPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _activeUsers = [];
  List<Map<String, dynamic>> _chatList = [];
  bool _isLoading = true;
  String? userAddress;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await _loadUserAddress();
    await _loadActiveUsers();
    await _loadChatList();
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadUserAddress() async {
    try {
      final session = await SessionService.getLoginSession();
      userAddress = session['userAddress'];
    } catch (e) {
      print('❌ Error loading user address: $e');
    }
  }

  Future<void> _loadActiveUsers() async {
    // TODO: Load active users from workspace members
    // For now, using placeholder data
    setState(() {
      _activeUsers = [
        {'name': 'User 1', 'avatar': null},
        {'name': 'User 2', 'avatar': null},
        {'name': 'User 3', 'avatar': null},
        {'name': 'User 4', 'avatar': null},
      ];
    });
  }

  Future<void> _loadChatList() async {
    // TODO: Load actual chat list from OrbitDB
    // For now, using placeholder data matching the screenshot
    setState(() {
      _chatList = [
        {
          'name': 'Hayati',
          'lastMessage': 'How are you ?',
          'timestamp': '11:45pm',
          'isRead': true,
          'unreadCount': 0,
          'avatar': null,
        },
        {
          'name': 'Rudolff',
          'lastMessage': 'I am stuck..',
          'timestamp': '1:25am',
          'isRead': false,
          'unreadCount': 0,
          'avatar': null,
        },
        {
          'name': 'Henry',
          'lastMessage': 'Catch up dude!',
          'timestamp': '12:45pm',
          'isRead': false,
          'unreadCount': 2,
          'avatar': null,
        },
        {
          'name': 'Freddy',
          'lastMessage': 'Easyy man...',
          'timestamp': '11:45pm',
          'isRead': false,
          'unreadCount': 0,
          'avatar': null,
        },
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        backgroundColor: const Color.fromARGB(255, 255, 255, 255),
        body: SafeArea(
          top: true,
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF0F365F),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // Active Users Section
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 20, 16, 0),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.max,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Active users',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black,
                                      fontSize: 16,
                                      letterSpacing: 0.0,
                                    ) ??
                                    const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  // TODO: Navigate to see all active users
                                },
                                child: Text(
                                  'see all',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        fontFamily: 'Inter',
                                        color: const Color(0xFF0F365F),
                                        fontSize: 14,
                                        letterSpacing: 0.0,
                                        decoration: TextDecoration.underline,
                                      ) ??
                                      const TextStyle(
                                        color: Color(0xFF0F365F),
                                        fontSize: 14,
                                        decoration: TextDecoration.underline,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 16, 0),
                            child: Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                // Add New Contact Button
                                GestureDetector(
                                  onTap: () {
                                    // TODO: Open add contact dialog
                                  },
                                  child: Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF2F80ED),
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.add,
                                      color: Color(0xFF0F365F),
                                      size: 28,
                                    ),
                                  ),
                                ),
                                // Active User Avatars
                                ...List.generate(
                                  _activeUsers.length,
                                  (index) => Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(
                                        12, 0, 0, 0),
                                    child: GestureDetector(
                                      onTap: () {
                                        // TODO: Open chat with user
                                      },
                                      child: Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: const Color(0xFF2A313F),
                                            width: 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.1),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: ClipOval(
                                          child: _activeUsers[index]['avatar'] != null
                                              ? Image.network(
                                                  _activeUsers[index]['avatar'],
                                                  fit: BoxFit.cover,
                                                  width: 60,
                                                  height: 60,
                                                  errorBuilder: (context, error, stackTrace) {
                                                    return Container(
                                                      width: 60,
                                                      height: 60,
                                                      color: const Color(0xFF0F365F),
                                                      child: Center(
                                                        child: Text(
                                                          _activeUsers[index]['name']?[0].toUpperCase() ?? 'U',
                                                          style: const TextStyle(
                                                            color: Colors.white,
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 20,
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                )
                                              : Container(
                                                  width: 60,
                                                  height: 60,
                                                  color: const Color(0xFF0F365F),
                                                  child: Center(
                                                    child: Text(
                                                      _activeUsers[index]['name']?[0].toUpperCase() ?? 'U',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 20,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Direct Messages Heading
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Text(
                            'Direct messages',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black,
                                  fontSize: 16,
                                  letterSpacing: 0.0,
                                ) ??
                                const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                          ),
                        ],
                      ),
                    ),
                    // Chat List Section
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 20),
                        child: _chatList.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline,
                                      size: 64,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No messages yet',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                            fontFamily: 'Inter',
                                            color: Colors.grey[600],
                                            letterSpacing: 0.0,
                                          ) ??
                                          TextStyle(
                                            color: Colors.grey[600],
                                          ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: _chatList.length,
                                itemBuilder: (context, index) {
                                  final chat = _chatList[index];
                                  return Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 12),
                                    child: _buildChatCard(chat),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildChatCard(Map<String, dynamic> chat) {
    final hasUnread = chat['unreadCount'] != null && chat['unreadCount'] > 0;
    final isRead = chat['isRead'] == true;

    return GestureDetector(
      onTap: () {
        // TODO: Navigate to chat screen
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF0F365F),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Left side: Avatar and Name/Message
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  // Avatar
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFE0E0E0),
                        width: 1,
                      ),
                    ),
                    child: ClipOval(
                      child: chat['avatar'] != null
                          ? Image.network(
                              chat['avatar'],
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 52,
                                  height: 52,
                                  color: const Color(0xFF0F365F),
                                  child: Center(
                                    child: Text(
                                      chat['name']?[0].toUpperCase() ?? 'U',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            )
                          : Container(
                              width: 52,
                              height: 52,
                              color: const Color(0xFF0F365F),
                              child: Center(
                                child: Text(
                                  chat['name']?[0].toUpperCase() ?? 'U',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                  // Name and Message
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 0, 0),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chat['name'] ?? 'Unknown',
                            textAlign: TextAlign.start,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                  fontFamily: 'Inter',
                                  color: Colors.black,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  letterSpacing: 0.0,
                                ) ??
                                const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            chat['lastMessage'] ?? '',
                            textAlign: TextAlign.start,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w400,
                                  color: const Color(0xFF828282),
                                  fontSize: 13,
                                  letterSpacing: 0.0,
                                ) ??
                                const TextStyle(
                                  color: Color(0xFF828282),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Right side: Timestamp and Status
            Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  chat['timestamp'] ?? '',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'Inter',
                        color: const Color(0xFF828282),
                        fontSize: 11,
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w400,
                      ) ??
                      const TextStyle(
                        color: Color(0xFF828282),
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                ),
                const SizedBox(height: 8),
                // Status Indicator
                hasUnread
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF393C),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEF393C).withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '${chat['unreadCount']}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  fontFamily: 'Inter',
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.0,
                                ) ??
                                const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                      )
                    : Icon(
                        Icons.done_all,
                        color: isRead
                            ? const Color(0xFF2F80ED)
                            : const Color(0xFFBDBDBD),
                        size: 18,
                      ),
              ],
            ),
            ],
          ),
        ),
      ),
    );
  }
}

