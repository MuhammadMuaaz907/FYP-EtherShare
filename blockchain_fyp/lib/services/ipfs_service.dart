import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

class IPFSService {
  final String ipfsApiUrl = 'http://192.168.0.35:5001/api/v0';

  Future<String> uploadFileToIPFS(File file) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$ipfsApiUrl/add'));
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var jsonResponse = jsonDecode(responseData);
      String cid = jsonResponse['Hash'];
      return cid;
    } catch (e) {
      print('Error uploading to IPFS: $e');
      return '';
    }
  }

  Future<void> pinFile(String cid) async {
    try {
      await http.post(Uri.parse('$ipfsApiUrl/pin/add?arg=$cid'));
      print('File pinned: $cid');
    } catch (e) {
      print('Error pinning file: $e');
    }
  }
}