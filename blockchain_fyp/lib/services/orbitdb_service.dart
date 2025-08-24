import 'package:http/http.dart' as http;
import 'dart:convert';

class OrbitDBService {
  final String serverUrl = 'http://192.168.0.37:3000';

  // Shared workspace DB address (replace with your actual address after first creation)
  static const String workspaceDbName = 'workspaces';
  static String workspaceDbAddress = 'orbitdb://1753005090106-9uj7iwhel';

  // Helper to create the shared workspace DB (call once, then save the address)
  Future<void> ensureWorkspaceDbExists() async {
    if (workspaceDbAddress == 'workspaces-db-address') {
      final address = await createDatabase(workspaceDbName);
      if (address.isNotEmpty) {
        workspaceDbAddress = address;
      }
    }
  }

  // Helper to save workspace details for a user
  Future<bool> saveWorkspaceForUser(String userAddress, String workspaceDetails) async {
    await ensureWorkspaceDbExists();
    final key = userAddress.toLowerCase().trim();
    print('Saving workspace for key: $key, value: $workspaceDetails');
    return addData(workspaceDbAddress, key, workspaceDetails);
  }

  Future<String> createDatabase(String dbName, {String dbType = 'keyvalue'}) async {
    try {
      var response = await http.post(
        Uri.parse('$serverUrl/create-db'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'dbName': dbName, 'dbType': dbType}),
      );
      var jsonResponse = jsonDecode(response.body);
      return jsonResponse['address'];
    } catch (e) {
      print('Error creating database: $e');
      return '';
    }
  }

  Future<bool> addData(String dbAddress, String key, String value) async {
    try {
      var response = await http.post(
        Uri.parse('$serverUrl/add-data'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'dbAddress': dbAddress, 'key': key, 'value': value}),
      );
      var jsonResponse = jsonDecode(response.body);
      return jsonResponse['success'];
    } catch (e) {
      print('Error adding data: $e');
      return false;
    }
  }

  Future<String> getData(String dbAddress, String key) async {
    try {
      var encodedDbAddress = base64.encode(utf8.encode(dbAddress));
      var encodedKey = base64.encode(utf8.encode(key));
      var response = await http.get(Uri.parse('$serverUrl/get-data/$encodedDbAddress/$encodedKey'));
      print('OrbitDB GET response: ${response.statusCode} ${response.body}');
      if (response.statusCode == 200) {
        var jsonResponse = jsonDecode(response.body);
        return jsonResponse['value'];
      } else {
        print('Error getting data: ${response.body}');
        return '';
      }
    } catch (e) {
      print('Error getting data: $e');
      return '';
    }
  }

  // Store a message in a channel (append to list)
  Future<bool> addChannelMessage(String workspace, String channel, Map<String, dynamic> message) async {
    final dbAddress = workspaceDbAddress;
    final key = 'messages-${workspace}-${channel}';
    // Get current messages
    String current = await getData(dbAddress, key);
    List<dynamic> messages = [];
    if (current.isNotEmpty) {
      try {
        messages = jsonDecode(current);
      } catch (_) {
        messages = [];
      }
    }
    messages.add(message);
    return addData(dbAddress, key, jsonEncode(messages));
  }

  // Retrieve all messages for a channel
  Future<List<Map<String, dynamic>>> getChannelMessages(String workspace, String channel) async {
    final dbAddress = workspaceDbAddress;
    final key = 'messages-${workspace}-${channel}';
    String data = await getData(dbAddress, key);
    if (data.isNotEmpty) {
      try {
        List<dynamic> decoded = jsonDecode(data);
        return decoded.cast<Map<String, dynamic>>();
      } catch (_) {
        return [];
      }
    }
    return [];
  }
}