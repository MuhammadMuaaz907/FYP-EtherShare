import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let orbitdbChannel = FlutterMethodChannel(name: "orbitdb_channel",
                                              binaryMessenger: controller.binaryMessenger)
    
    orbitdbChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      
      switch call.method {
      case "initOrbitDB":
        self.initOrbitDB(result: result)
      case "createChatDB":
        let args = call.arguments as? [String: Any]
        let name = args?["name"] as? String ?? ""
        self.createChatDB(name: name, result: result)
      case "addMessage":
        let args = call.arguments as? [String: Any]
        let address = args?["address"] as? String ?? ""
        let message = args?["message"] as? [String: Any] ?? [:]
        self.addMessage(address: address, message: message, result: result)
      case "getMessages":
        let args = call.arguments as? [String: Any]
        let address = args?["address"] as? String ?? ""
        self.getMessages(address: address, result: result)
      case "loadUpdates":
        let args = call.arguments as? [String: Any]
        let address = args?["address"] as? String ?? ""
        self.loadUpdates(address: address, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    })
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func initOrbitDB(result: @escaping FlutterResult) {
    print("iOS: Initializing OrbitDB...")
    
    // Simulate OrbitDB initialization
    // In a real implementation, you would initialize the Node.js bridge here
    DispatchQueue.global(qos: .background).async {
      let response: [String: Any] = [
        "success": true,
        "heliaId": "simulated_helia_id_ios",
        "message": "OrbitDB initialized successfully"
      ]
      
      DispatchQueue.main.async {
        result(response)
      }
    }
  }
  
  private func createChatDB(name: String, result: @escaping FlutterResult) {
    print("iOS: Creating chat DB: \(name)")
    
    DispatchQueue.global(qos: .background).async {
      let address = "simulated_address_ios_\(name)"
      let response: [String: Any] = [
        "success": true,
        "address": address,
        "message": "Chat database '\(name)' created successfully"
      ]
      
      DispatchQueue.main.async {
        result(response)
      }
    }
  }
  
  private func addMessage(address: String, message: [String: Any], result: @escaping FlutterResult) {
    print("iOS: Adding message to \(address)")
    
    DispatchQueue.global(qos: .background).async {
      let messageId = "msg_ios_\(Int(Date().timeIntervalSince1970 * 1000))"
      let hash = "hash_ios_\(Int(Date().timeIntervalSince1970 * 1000))"
      
      let response: [String: Any] = [
        "success": true,
        "hash": hash,
        "messageId": messageId,
        "message": "Message added successfully"
      ]
      
      DispatchQueue.main.async {
        result(response)
      }
    }
  }
  
  private func getMessages(address: String, result: @escaping FlutterResult) {
    print("iOS: Getting messages from \(address)")
    
    DispatchQueue.global(qos: .background).async {
      let messages: [[String: Any]] = []
      let response: [String: Any] = [
        "success": true,
        "messages": messages,
        "count": messages.count
      ]
      
      DispatchQueue.main.async {
        result(response)
      }
    }
  }
  
  private func loadUpdates(address: String, result: @escaping FlutterResult) {
    print("iOS: Loading updates from \(address)")
    
    DispatchQueue.global(qos: .background).async {
      let response: [String: Any] = [
        "success": true,
        "message": "Update listener set up successfully"
      ]
      
      DispatchQueue.main.async {
        result(response)
      }
    }
  }
}
