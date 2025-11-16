import 'package:flutter/material.dart';

class ActivityPage extends StatefulWidget {
  final String workspaceName;
  const ActivityPage({super.key, required this.workspaceName});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    // TODO: Load actual notifications from OrbitDB
    // For now, using placeholder data matching the screenshot
    setState(() {
      _notifications = [
        {
          'userName': 'Samra Maryam',
          'message': 'Replied to your message',
          'timestamp': 'Jul 8, at 4:31pm',
          'avatar': null,
          'avatarColor': const Color(0xFFE8D5FF), // Light purple
          'borderColor': const Color(0xFF0F365F),
        },
        {
          'userName': 'Muaaz Waleed',
          'message': 'accepted your request',
          'timestamp': 'Jul 8, at 4:30pm',
          'avatar': null,
          'avatarColor': const Color(0xFFE8D5FF), // Light purple
          'borderColor': const Color(0xFF0F365F),
        },
        {
          'userName': 'Yawer Ali',
          'message': 'Sent a voice message',
          'timestamp': 'Jul 8, at 2:20pm',
          'avatar': null,
          'avatarColor': const Color(0xFFD5E8FF), // Light blue
          'borderColor': const Color(0xFF0F365F),
        },
      ];
      _isLoading = false;
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
        backgroundColor: Colors.white,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title Section
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 0, 0),
                      child: Text(
                        'Notifications',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontFamily: 'Inter',
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 28,
                              letterSpacing: 0.0,
                            ) ??
                            const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 28,
                            ),
                      ),
                    ),
                    // Notifications List
                    Expanded(
                      child: _notifications.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.notifications_none,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No notifications yet',
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
                          : ListView.separated(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: _notifications.length,
                              separatorBuilder: (context, index) => Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: Colors.grey[200],
                                  ),
                              itemBuilder: (context, index) {
                                final notification = _notifications[index];
                                return _buildNotificationItem(notification);
                              },
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildNotificationItem(Map<String, dynamic> notification) {
    final userName = notification['userName'] ?? 'Unknown';
    final message = notification['message'] ?? '';
    final timestamp = notification['timestamp'] ?? '';
    final avatar = notification['avatar'];
    final avatarColor = notification['avatarColor'] ?? const Color(0xFFE8D5FF);
    final borderColor = notification['borderColor'] ?? const Color(0xFF0F365F);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            blurRadius: 0,
            color: Colors.grey[200] ?? Colors.grey,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: avatarColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: borderColor,
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: avatar != null
                    ? Image.network(
                        avatar,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 36,
                            height: 36,
                            color: avatarColor,
                            child: Center(
                              child: Text(
                                userName[0].toUpperCase(),
                                style: TextStyle(
                                  color: borderColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    : Container(
                        width: 36,
                        height: 36,
                        color: avatarColor,
                        child: Center(
                          child: Text(
                            userName[0].toUpperCase(),
                            style: TextStyle(
                              color: borderColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            // Notification Content
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 0, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 4),
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '$userName ',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF0F365F),
                                    fontSize: 16,
                                    letterSpacing: 0.0,
                                  ) ??
                                  const TextStyle(
                                    color: Color(0xFF0F365F),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                            ),
                            TextSpan(
                              text: message,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    fontFamily: 'Inter',
                                    color: Colors.black,
                                    fontSize: 16,
                                    letterSpacing: 0.0,
                                  ) ??
                                  const TextStyle(
                                    color: Colors.black,
                                    fontSize: 16,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(0, 4, 0, 0),
                      child: Text(
                        timestamp,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(
                              fontFamily: 'Inter',
                              color: Colors.grey[600],
                              fontSize: 13,
                              letterSpacing: 0.0,
                            ) ??
                            TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
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
    );
  }
}
