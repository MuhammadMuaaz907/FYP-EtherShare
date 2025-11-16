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
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1284E4),
        body: SafeArea(
          top: true,
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                flex: 8,
                child: Container(
                  width: 100,
                  height: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1284E4),
                  ),
                  alignment: AlignmentDirectional(0, -1),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 75.58,
                          decoration: const BoxDecoration(
                            color: Color(0xFF1284E4),
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(16),
                              bottomRight: Radius.circular(16),
                              topLeft: Radius.circular(0),
                              topRight: Radius.circular(0),
                            ),
                          ),
                          alignment: AlignmentDirectional(-1, 0),
                        ),
                        Align(
                          alignment: AlignmentDirectional(0, 0),
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Align(
                                  alignment: AlignmentDirectional(0, 0),
                                  child: Text(
                                    'Hurray! Everthing done',
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                          fontFamily: 'Inter',
                                          color: Colors.white,
                                          fontSize: 28,
                                          letterSpacing: 0.0,
                                          fontWeight: FontWeight.bold,
                                        ) ?? const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: AlignmentDirectional(0, 0),
                                  child: Text(
                                    " Meet your team's first channel: #${channelName.isNotEmpty ? channelName : 'Work'} ",
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          fontFamily: 'Inter',
                                          color: Colors.white,
                                          fontSize: 20,
                                          letterSpacing: 0.0,
                                          fontWeight: FontWeight.w500,
                                        ) ?? const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Align(
                                  alignment: AlignmentDirectional(0, 0),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      'https://storage.googleapis.com/flutterflow-io-6f20.appspot.com/projects/ether-4gst3t/assets/txhdyp1lfn7e/Channel.png',
                                      width: 400,
                                      height: 300,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        // Fallback to a placeholder if image fails
                                        return Container(
                                          width: 400,
                                          height: 300,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                            Icons.chat_bubble_outline,
                                            size: 80,
                                            color: Colors.white,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: AlignmentDirectional(0, 0),
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(0, 12, 0, 24),
                                    child: Text(
                                      'A channel brings together every part of your project so your team can get more done',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                            fontFamily: 'Inter',
                                            color: Colors.white,
                                            letterSpacing: 0.0,
                                          ) ?? const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                          ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                  child: SizedBox(
                                    width: MediaQuery.of(context).size.width > 400 ? 370 : double.infinity,
                                    height: 44,
                                    child: FilledButton(
                                      onPressed: () async {
                                        // Save workspace for user in OrbitDB
                                        final key = userAddress.toLowerCase().trim();
                                        final workspaceDetails = jsonEncode({
                                          'workspaceName': workspaceName,
                                          'channelName': channelName,
                                        });
                                        print(
                                            'Saving workspace for key: $key, value: $workspaceDetails');
                                        final success = await OrbitDBService.saveWorkspaceForUser(key, workspaceDetails);
                                        print('Workspace save result: $success');
                                        print('📌 Workspace database address cached for future use');
                                        
                                        // Add the creator as the first member (inviter) of the workspace
                                        try {
                                          // Get creator's display name from profile
                                          String? creatorDisplayName;
                                          final profileDbName = 'profile_$key';
                                          final profileDbAddress = await OrbitDBService.getExistingDatabaseAddress(profileDbName);
                                          if (profileDbAddress != null) {
                                            final profileMessages = await OrbitDBService.getMessages(profileDbAddress);
                                            for (var msg in profileMessages) {
                                              if (msg['type'] == 'profile' && msg['userAddress']?.toString().toLowerCase() == key) {
                                                creatorDisplayName = msg['username']?.toString();
                                                break;
                                              }
                                            }
                                          }
                                          
                                          await OrbitDBService.addWorkspaceMember(
                                            inviterAddress: key,
                                            memberAddress: key,
                                            workspaceName: workspaceName,
                                            memberDisplayName: creatorDisplayName,
                                          );
                                          print('✅ Creator added as workspace member');
                                        } catch (e) {
                                          print('⚠️ Failed to add creator as member: $e');
                                          // Continue anyway since workspace was saved
                                        }
                                        
                                        // Save the initial channel to OrbitDB
                                        try {
                                          if (channelName.isNotEmpty && channelName.toLowerCase() != 'work') {
                                            final workspaceDbName = 'workspace_$key';
                                            var dbAddress = await OrbitDBService.getExistingDatabaseAddress(workspaceDbName);
                                            
                                            if (dbAddress == null) {
                                              dbAddress = await OrbitDBService.createChatDB(workspaceDbName);
                                            }
                                            
                                            if (dbAddress != null) {
                                              // Check if channel already exists
                                              final messages = await OrbitDBService.getMessages(dbAddress);
                                              final channelExists = messages.any((msg) =>
                                                  msg['type'] == 'channel' &&
                                                  msg['workspaceName'] == workspaceName &&
                                                  msg['channelName']?.toString().toLowerCase() == channelName.toLowerCase());
                                              
                                              if (!channelExists) {
                                                // Create channel message
                                                final channelMessage = {
                                                  'type': 'channel',
                                                  'workspaceName': workspaceName,
                                                  'channelName': channelName,
                                                  'createdBy': key,
                                                  'inviterAddress': key,
                                                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                                                };
                                                
                                                // Save channel to workspace database
                                                final result = await OrbitDBService.addMessage(dbAddress, channelMessage);
                                                if (result != null) {
                                                  print('✅ Initial channel "$channelName" saved to OrbitDB');
                                                  
                                                  // Create channel database for messages
                                                  final channelDbName = 'channel_${key}_${workspaceName}_$channelName';
                                                  final channelDbAddress = await OrbitDBService.createChatDB(channelDbName);
                                                  if (channelDbAddress != null) {
                                                    print('✅ Channel database created: $channelDbName');
                                                  }
                                                }
                                              } else {
                                                print('ℹ️ Initial channel "$channelName" already exists in database');
                                              }
                                            }
                                          }
                                        } catch (e) {
                                          print('⚠️ Failed to save initial channel: $e');
                                          // Continue anyway - it will be saved when TeamHomePage loads
                                        }
                                        
                                        // No need to save to SharedPreferences - all data is now in OrbitDB
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
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF0F365F),
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
                                        elevation: 3,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: Text(
                                        'See your channel in EtherShare',
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
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (MediaQuery.of(context).size.width > 768)
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      width: 100,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        image: const DecorationImage(
                          fit: BoxFit.cover,
                          image: NetworkImage(
                            'https://images.unsplash.com/photo-1514924013411-cbf25faa35bb?ixlib=rb-4.0.3&ixid=MnwxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8&auto=format&fit=crop&w=1380&q=80',
                          ),
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

}
