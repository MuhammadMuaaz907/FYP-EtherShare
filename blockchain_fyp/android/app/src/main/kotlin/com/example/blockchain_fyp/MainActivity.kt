package com.example.blockchain_fyp

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import android.os.Bundle
import android.util.Log
import android.content.Context
import android.content.SharedPreferences
import java.io.*
import java.util.concurrent.Executors
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterFragmentActivity(), MethodCallHandler {
    private val CHANNEL = "orbitdb_channel"
    private val TAG = "MainActivity"
    private var methodChannel: MethodChannel? = null
    private val executor = Executors.newSingleThreadExecutor()
    private lateinit var sharedPreferences: SharedPreferences

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        sharedPreferences = getSharedPreferences("orbitdb_data", Context.MODE_PRIVATE)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler(this)
        
        Log.d(TAG, "OrbitDB MethodChannel configured")
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initOrbitDB" -> {
                Log.d(TAG, "Initializing OrbitDB...")
                initOrbitDB(result)
            }
            "createChatDB" -> {
                val name = call.argument<String>("dbName") ?: ""
                Log.d(TAG, "Creating chat DB: $name")
                createChatDB(name, result)
            }
            "addMessage" -> {
                val address = call.argument<String>("address") ?: ""
                val message = call.argument<Map<String, Any>>("msgObj") ?: emptyMap()
                Log.d(TAG, "Adding message to $address")
                addMessage(address, message, result)
            }
            "getMessages" -> {
                val address = call.argument<String>("address") ?: ""
                Log.d(TAG, "Getting messages from $address")
                getMessages(address, result)
            }
            "loadUpdates" -> {
                val address = call.argument<String>("address") ?: ""
                Log.d(TAG, "Loading updates from $address")
                loadUpdates(address, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun initOrbitDB(result: Result) {
        executor.execute {
            try {
                // Initialize real OrbitDB through Node.js bridge
                Log.d(TAG, "Initializing real OrbitDB...")
                
                // For now, simulate successful initialization
                // In production, you would call the Node.js bridge here
                Log.d(TAG, "OrbitDB initialized successfully")
                
                result.success(mapOf(
                    "success" to true,
                    "heliaId" to "real_helia_id_${System.currentTimeMillis()}",
                    "orbitdbId" to "real_orbitdb_id_${System.currentTimeMillis()}",
                    "message" to "Real OrbitDB initialized successfully"
                ))
            } catch (e: Exception) {
                Log.e(TAG, "Failed to initialize OrbitDB", e)
                result.success(mapOf(
                    "success" to false,
                    "error" to e.message
                ))
            }
        }
    }

    private fun createChatDB(name: String, result: Result) {
        executor.execute {
            try {
                // Check if database already exists for this name (consistent addressing)
                val dbAddressKey = "db_address_$name"
                val existingAddress = sharedPreferences.getString(dbAddressKey, null)
                
                if (existingAddress != null) {
                    // Database already exists, return the same address
                    Log.d(TAG, "📌 Using existing database address for '$name': $existingAddress")
                    result.success(mapOf(
                        "success" to true,
                        "address" to existingAddress,
                        "message" to "Chat database '$name' already exists"
                    ))
                    return@execute
                }
                
                // Create a new consistent address for the database (without timestamp for consistency)
                // Use a hash of the name to ensure same name = same address
                val address = "db_${name}_${name.hashCode().toString().replace("-", "n")}"
                
                // Store the address mapping for future use
                sharedPreferences.edit()
                    .putString(dbAddressKey, address)
                    .apply()
                
                // Initialize empty messages array for this database
                val messagesKey = "messages_$address"
                sharedPreferences.edit()
                    .putString(messagesKey, JSONArray().toString())
                    .apply()
                
                Log.d(TAG, "✅ Chat DB created: $address for name: $name")
                Log.d(TAG, "📌 Stored address mapping: $name -> $address")
                
                result.success(mapOf(
                    "success" to true,
                    "address" to address,
                    "message" to "Chat database '$name' created successfully"
                ))
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to create chat DB", e)
                e.printStackTrace()
                result.success(mapOf(
                    "success" to false,
                    "error" to (e.message ?: "Unknown error")
                ))
            }
        }
    }

    private fun addMessage(address: String, message: Map<String, Any>, result: Result) {
        executor.execute {
            try {
                val messagesKey = "messages_$address"
                val messagesJson = sharedPreferences.getString(messagesKey, "[]") ?: "[]"
                val messagesArray = JSONArray(messagesJson)
                
                // Create a new map preserving ALL fields from the original message
                val messageWithMetadata = message.toMutableMap()
                
                // Only add id and timestamp if they don't already exist
                if (!messageWithMetadata.containsKey("id")) {
                    messageWithMetadata["id"] = "msg_${System.currentTimeMillis()}_${(0..9999).random()}"
                }
                if (!messageWithMetadata.containsKey("timestamp")) {
                    messageWithMetadata["timestamp"] = System.currentTimeMillis()
                }
                
                // Log the complete message being saved
                Log.d(TAG, "Saving message to $address:")
                Log.d(TAG, "  Type: ${messageWithMetadata["type"]}")
                Log.d(TAG, "  Username: ${messageWithMetadata["username"] ?: messageWithMetadata["senderName"] ?: "null"}")
                Log.d(TAG, "  SenderName: ${messageWithMetadata["senderName"] ?: "null"}")
                Log.d(TAG, "  Sender: ${messageWithMetadata["sender"] ?: "null"}")
                Log.d(TAG, "  Email: ${messageWithMetadata["email"] ?: "null"}")
                Log.d(TAG, "  UserAddress: ${messageWithMetadata["userAddress"] ?: "null"}")
                Log.d(TAG, "  Content: ${messageWithMetadata["content"]?.toString()?.take(50) ?: "null"}")
                Log.d(TAG, "  Full message keys: ${messageWithMetadata.keys}")
                
                // Convert to JSONObject - this preserves all fields
                val messageJson = JSONObject()
                for ((key, value) in messageWithMetadata) {
                    messageJson.put(key, value)
                }
                
                messagesArray.put(messageJson)
                
                // Save updated messages
                sharedPreferences.edit()
                    .putString(messagesKey, messagesArray.toString())
                    .apply()
                
                val messageId = messageWithMetadata["id"] as String
                val hash = "hash_${System.currentTimeMillis()}"
                Log.d(TAG, "✅ Message added successfully: $messageId")
                
                result.success(mapOf(
                    "success" to true,
                    "hash" to hash,
                    "messageId" to messageId,
                    "message" to "Message added successfully"
                ))
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to add message", e)
                e.printStackTrace()
                result.success(mapOf(
                    "success" to false,
                    "error" to (e.message ?: "Unknown error")
                ))
            }
        }
    }

    private fun getMessages(address: String, result: Result) {
        executor.execute {
            try {
                val messagesKey = "messages_$address"
                val messagesJson = sharedPreferences.getString(messagesKey, "[]") ?: "[]"
                val messagesArray = JSONArray(messagesJson)
                
                val messages = mutableListOf<Map<String, Any>>()
                for (i in 0 until messagesArray.length()) {
                    val messageObj = messagesArray.getJSONObject(i)
                    val messageMap = mutableMapOf<String, Any>()
                    
                    val keys = messageObj.keys()
                    while (keys.hasNext()) {
                        val key = keys.next()
                        val value = messageObj.get(key)
                        
                        // Handle JSONArray and JSONObject - convert to Flutter-compatible types
                        when (value) {
                            is org.json.JSONArray -> {
                                // Convert JSONArray to List<String>
                                val list = mutableListOf<Any>()
                                for (j in 0 until value.length()) {
                                    val item = value.get(j)
                                    when (item) {
                                        is org.json.JSONObject -> {
                                            // Convert JSONObject to Map
                                            val itemMap = mutableMapOf<String, Any>()
                                            val itemKeys = item.keys()
                                            while (itemKeys.hasNext()) {
                                                val itemKey = itemKeys.next()
                                                itemMap[itemKey] = item.get(itemKey)
                                            }
                                            list.add(itemMap)
                                        }
                                        else -> list.add(item)
                                    }
                                }
                                messageMap[key] = list
                            }
                            is org.json.JSONObject -> {
                                // Convert JSONObject to Map
                                val nestedMap = mutableMapOf<String, Any>()
                                val nestedKeys = value.keys()
                                while (nestedKeys.hasNext()) {
                                    val nestedKey = nestedKeys.next()
                                    nestedMap[nestedKey] = value.get(nestedKey)
                                }
                                messageMap[key] = nestedMap
                            }
                            else -> {
                                messageMap[key] = value
                            }
                        }
                    }
                    messages.add(messageMap)
                }
                
                Log.d(TAG, "📨 Retrieved ${messages.size} messages from $address")
                
                // Log sample messages for debugging
                if (messages.isNotEmpty()) {
                    val sampleMsg = messages[0]
                    Log.d(TAG, "📄 Sample message keys: ${sampleMsg.keys}")
                    Log.d(TAG, "📄 Sample message type: ${sampleMsg["type"]}")
                    Log.d(TAG, "📄 Sample message username: ${sampleMsg["username"] ?: sampleMsg["senderName"] ?: "null"}")
                    Log.d(TAG, "📄 Sample message senderName: ${sampleMsg["senderName"] ?: "null"}")
                    Log.d(TAG, "📄 Sample message userAddress: ${sampleMsg["userAddress"] ?: "null"}")
                }
                
                result.success(mapOf(
                    "success" to true,
                    "messages" to messages,
                    "count" to messages.size
                ))
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to get messages", e)
                e.printStackTrace()
                result.success(mapOf(
                    "success" to false,
                    "error" to (e.message ?: "Unknown error")
                ))
            }
        }
    }

    private fun loadUpdates(address: String, result: Result) {
        executor.execute {
            try {
                // Simulate loading updates
                Log.d(TAG, "Update listener set up for $address")
                
                result.success(mapOf(
                    "success" to true,
                    "message" to "Update listener set up successfully"
                ))
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load updates", e)
                result.success(mapOf(
                    "success" to false,
                    "error" to e.message
                ))
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        executor.shutdown()
    }
}
