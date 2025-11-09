import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

class IPFSService {
  final String ipfsApiUrl = 'http://192.168.0.33:5001/api/v0';

  Future<String> uploadFileToIPFS(File file) async {
    try {
      print('📎 Uploading file to IPFS: ${file.path} (${await file.length()} bytes)');
      
      var request = http.MultipartRequest('POST', Uri.parse('$ipfsApiUrl/add'));
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      
      // Add timeout and headers
      var response = await request.send().timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw Exception('Upload timeout');
        },
      );
      
      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        var jsonResponse = jsonDecode(responseData);
        String cid = jsonResponse['Hash'];
        print('✅ File uploaded successfully. CID: $cid');
        return cid;
      } else {
        print('❌ Upload failed with status: ${response.statusCode}');
        return '';
      }
    } catch (e) {
      print('❌ Error uploading to IPFS: $e');
      return '';
    }
  }

  Future<void> pinFile(String cid) async {
    try {
      print('📌 Pinning file: $cid');
      var response = await http.post(
        Uri.parse('$ipfsApiUrl/pin/add?arg=$cid'),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Pin timeout');
        },
      );
      
      if (response.statusCode == 200) {
        print('✅ File pinned successfully: $cid');
      } else {
        print('❌ Pin failed with status: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error pinning file: $e');
    }
  }
  
}