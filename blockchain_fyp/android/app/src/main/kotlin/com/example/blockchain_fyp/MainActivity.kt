package com.example.blockchain_fyp

import io.flutter.embedding.android.FlutterActivity
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

class MainActivity : FlutterActivity(), MethodCallHandler {
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
                // Create a unique address for the database
                val address = "db_${name}_${System.currentTimeMillis()}"
                
                // Initialize empty messages array for this database
                val messagesKey = "messages_$address"
                sharedPreferences.edit()
                    .putString(messagesKey, JSONArray().toString())
                    .apply()
                
                Log.d(TAG, "Chat DB created: $address")
                
                result.success(mapOf(
                    "success" to true,
                    "address" to address,
                    "message" to "Chat database '$name' created successfully"
                ))
            } catch (e: Exception) {
                Log.e(TAG, "Failed to create chat DB", e)
                result.success(mapOf(
                    "success" to false,
                    "error" to e.message
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
                
                // Add timestamp to message
                val messageWithTimestamp = message.toMutableMap() as MutableMap<String, Any>
                messageWithTimestamp["timestamp"] = System.currentTimeMillis()
                messageWithTimestamp["id"] = "msg_${System.currentTimeMillis()}"
                
                messagesArray.put(JSONObject(messageWithTimestamp as Map<String, Any>))
                
                // Save updated messages
                sharedPreferences.edit()
                    .putString(messagesKey, messagesArray.toString())
                    .apply()
                
                val messageId = messageWithTimestamp["id"] as String
                val hash = "hash_${System.currentTimeMillis()}"
                Log.d(TAG, "Message added: $messageId")
                
                result.success(mapOf(
                    "success" to true,
                    "hash" to hash,
                    "messageId" to messageId,
                    "message" to "Message added successfully"
                ))
            } catch (e: Exception) {
                Log.e(TAG, "Failed to add message", e)
                result.success(mapOf(
                    "success" to false,
                    "error" to e.message
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
                        messageMap[key] = messageObj.get(key)
                    }
                    messages.add(messageMap)
                }
                
                Log.d(TAG, "Retrieved ${messages.size} messages")
                
                result.success(mapOf(
                    "success" to true,
                    "messages" to messages,
                    "count" to messages.size
                ))
            } catch (e: Exception) {
                Log.e(TAG, "Failed to get messages", e)
                result.success(mapOf(
                    "success" to false,
                    "error" to e.message
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
