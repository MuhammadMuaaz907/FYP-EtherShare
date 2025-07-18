import 'package:http/http.dart' as http;
import 'dart:convert';

class OrbitDBService {
  final String serverUrl = 'http://192.168.0.35:3000';

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
      var response = await http.get(Uri.parse('$serverUrl/get-data/$dbAddress/$key'));
      var jsonResponse = jsonDecode(response.body);
      return jsonResponse['value'];
    } catch (e) {
      print('Error getting data: $e');
      return '';
    }
  }
}