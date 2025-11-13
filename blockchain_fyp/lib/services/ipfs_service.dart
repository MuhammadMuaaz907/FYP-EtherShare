import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

class IPFSService {
  // Multiple IPFS API URLs for fallback (ordered by reliability)
  // Based on IPFS Desktop config: API on 0.0.0.0:5001 (accessible via localhost)
  final List<String> ipfsApiUrls = [
    'http://127.0.0.1:5001/api/v0',     // Primary: Localhost (most reliable)
    'http://localhost:5001/api/v0',     // Alternative localhost
    'http://192.168.0.39:5001/api/v0',  // Fallback: Network IP (if localhost fails)
  ];

  Future<String> uploadFileToIPFS(File file) async {
    final fileSize = await file.length();
    print('📎 Uploading file to IPFS: ${file.path} (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');
    
    // Try each IPFS API URL in order
    for (int i = 0; i < ipfsApiUrls.length; i++) {
      final ipfsApiUrl = ipfsApiUrls[i];
      try {
        print('📎 Attempt ${i + 1}/${ipfsApiUrls.length}: Uploading to $ipfsApiUrl');
        
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
          print('✅ File uploaded successfully to $ipfsApiUrl. CID: $cid');
          return cid;
        } else {
          print('⚠️ Upload failed with status ${response.statusCode} on $ipfsApiUrl');
          // Continue to next URL
        }
      } catch (e) {
        print('⚠️ Error uploading to $ipfsApiUrl: $e');
        // Continue to next URL if not the last one
        if (i < ipfsApiUrls.length - 1) {
          print('📎 Trying next IPFS endpoint...');
          continue;
        } else {
          // Last attempt failed
          print('❌ All IPFS endpoints failed. Last error: $e');
          print('💡 Please ensure IPFS is running and accessible.');
          print('💡 You can:');
          print('   1. Start IPFS Desktop');
          print('   2. Check IPFS API is running on port 5001');
          print('   3. Verify network connectivity');
        }
      }
    }
    
    // All attempts failed
    return '';
  }

  Future<void> pinFile(String cid) async {
    print('📌 Pinning file: $cid');
    
    // Try each IPFS API URL in order
    for (int i = 0; i < ipfsApiUrls.length; i++) {
      final ipfsApiUrl = ipfsApiUrls[i];
      try {
        print('📌 Attempt ${i + 1}/${ipfsApiUrls.length}: Pinning on $ipfsApiUrl');
        var response = await http.post(
          Uri.parse('$ipfsApiUrl/pin/add?arg=$cid'),
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw Exception('Pin timeout');
          },
        );
        
        if (response.statusCode == 200) {
          print('✅ File pinned successfully on $ipfsApiUrl: $cid');
          return; // Success, exit
        } else {
          print('⚠️ Pin failed with status ${response.statusCode} on $ipfsApiUrl');
          // Continue to next URL
        }
      } catch (e) {
        print('⚠️ Error pinning on $ipfsApiUrl: $e');
        // Continue to next URL if not the last one
        if (i < ipfsApiUrls.length - 1) {
          continue;
        } else {
          print('❌ All IPFS endpoints failed for pinning. Last error: $e');
        }
      }
    }
  }
  
}