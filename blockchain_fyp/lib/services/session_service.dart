// Session management helper for MongoDB-based authentication
import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  // Session keys
  static const String _keyIsLoggedIn = 'isLoggedIn';
  static const String _keyUserAddress = 'userAddress';
  static const String _keyWorkspaceName = 'workspaceName';
  static const String _keyChannelName = 'channelName';
  
  /// Save login session
  static Future<void> saveLoginSession(
    String userAddress,
    String workspaceName,
    String channelName,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyIsLoggedIn, true);
      await prefs.setString(_keyUserAddress, userAddress);
      await prefs.setString(_keyWorkspaceName, workspaceName);
      await prefs.setString(_keyChannelName, channelName);
      print('💾 Session saved: $userAddress');
    } catch (e) {
      print('❌ Error saving session: $e');
    }
  }
  
  /// Clear login session
  static Future<void> clearLoginSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyIsLoggedIn);
      await prefs.remove(_keyUserAddress);
      await prefs.remove(_keyWorkspaceName);
      await prefs.remove(_keyChannelName);
      print('🧹 Session cleared');
    } catch (e) {
      print('❌ Error clearing session: $e');
    }
  }
  
  /// Get login session
  static Future<Map<String, String?>> getLoginSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool(_keyIsLoggedIn) ?? false;
      
      if (isLoggedIn) {
        return {
          'isLoggedIn': 'true',
          'userAddress': prefs.getString(_keyUserAddress),
          'workspaceName': prefs.getString(_keyWorkspaceName),
          'channelName': prefs.getString(_keyChannelName),
        };
      }
      return {'isLoggedIn': 'false'};
    } catch (e) {
      print('❌ Error getting session: $e');
      return {'isLoggedIn': 'false'};
    }
  }
  
  /// Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final session = await getLoginSession();
    return session['isLoggedIn'] == 'true';
  }
  
  /// Get current user address
  static Future<String?> getUserAddress() async {
    final session = await getLoginSession();
    return session['userAddress'];
  }
  
  /// Get current workspace
  static Future<String?> getWorkspaceName() async {
    final session = await getLoginSession();
    return session['workspaceName'];
  }
  
  /// Get current channel
  static Future<String?> getChannelName() async {
    final session = await getLoginSession();
    return session['channelName'];
  }
}
