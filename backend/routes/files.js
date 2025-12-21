const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const { ObjectId } = require('mongodb');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { optionalAuth } = require('../middleware/auth');
const { getCollection, getDb } = require('../utils/db');
const { GridFSBucket } = require('mongodb');

// Configure multer for file uploads
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadPath = process.env.UPLOAD_PATH || './uploads';
    if (!fs.existsSync(uploadPath)) {
      fs.mkdirSync(uploadPath, { recursive: true });
    }
    cb(null, uploadPath);
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, file.fieldname + '-' + uniqueSuffix + path.extname(file.originalname));
  }
});

const upload = multer({
  storage: storage,
  limits: {
    fileSize: parseInt(process.env.MAX_FILE_SIZE) || 10 * 1024 * 1024 // 10MB default
  },
  fileFilter: (req, file, cb) => {
    // Accept all file types (you can add filtering here)
    cb(null, true);
  }
});

/**
 * @route   POST /api/files/upload
 * @desc    Upload file and save metadata
 * @access  Public (add auth later)
 */
router.post('/upload', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'No file uploaded'
      });
    }

    const filesCollection = getCollection('files');
    const db = getDb();
    const { workspaceId, uploaderAddress } = req.body;
    
    if (!workspaceId || !uploaderAddress) {
      // Delete uploaded file if validation fails
      fs.unlinkSync(req.file.path);
      return res.status(400).json({
        success: false,
        error: 'Workspace ID and Uploader Address are required'
      });
    }

    const timestamp = Date.now();
    const fileId = `file_${timestamp}_${uploaderAddress.toLowerCase()}`;
    
    // Read file for GridFS
    const fileBuffer = fs.readFileSync(req.file.path);
    
    // Create GridFS bucket
    const bucket = new GridFSBucket(db, { bucketName: 'files' });
    
    // Upload to GridFS
    const uploadStream = bucket.openUploadStream(req.file.originalname, {
      metadata: {
        fileId: fileId,
        workspaceId: workspaceId,
        uploaderAddress: uploaderAddress.toLowerCase().trim()
      }
    });
    
    uploadStream.end(fileBuffer);
    
    // Wait for upload to complete
    await new Promise((resolve, reject) => {
      uploadStream.on('finish', resolve);
      uploadStream.on('error', reject);
    });
    
    const gridfsId = uploadStream.id.toString();
    
    // Save file metadata
    const fileData = {
      file_id: fileId,
      filename: req.file.originalname,
      workspace_id: workspaceId,
      uploader_address: uploaderAddress.toLowerCase().trim(),
      gridfs_id: gridfsId,
      file_size: req.file.size,
      upload_timestamp: timestamp,
      mime_type: req.file.mimetype
    };
    
    await filesCollection.insertOne(fileData);
    
    // Delete temporary file
    fs.unlinkSync(req.file.path);
    
    console.log(`✅ File uploaded: ${fileId}`);
    
    return res.status(201).json({
      success: true,
      message: 'File uploaded successfully',
      data: {
        file_id: fileId,
        filename: req.file.originalname,
        file_size: req.file.size,
        upload_timestamp: timestamp
      }
    });
  } catch (error) {
    // Clean up on error
    if (req.file && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
    
    console.error('❌ File upload error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to upload file',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/files/:fileId
 * @desc    Get file metadata
 * @access  Public
 */
router.get('/:fileId', optionalAuth, async (req, res) => {
  try {
    const filesCollection = getCollection('files');
    const { fileId } = req.params;
    
    const file = await filesCollection.findOne({ file_id: fileId });
    
    if (!file) {
      return res.status(404).json({
        success: false,
        error: 'File not found'
      });
    }
    
    // Remove _id
    const { _id, ...cleanFile } = file;
    
    return res.json({
      success: true,
      data: cleanFile
    });
  } catch (error) {
    console.error('❌ Get file metadata error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get file metadata',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/files/:fileId/download
 * @desc    Download file from GridFS
 * @access  Public
 */
router.get('/:fileId/download', optionalAuth, async (req, res) => {
  try {
    const filesCollection = getCollection('files');
    const db = getDb();
    const { fileId } = req.params;
    
    const file = await filesCollection.findOne({ file_id: fileId });
    
    if (!file) {
      return res.status(404).json({
        success: false,
        error: 'File not found'
      });
    }
    
    const bucket = new GridFSBucket(db, { bucketName: 'files' });
    const downloadStream = bucket.openDownloadStream(
      new ObjectId(file.gridfs_id)
    );
    
    // Set response headers
    res.setHeader('Content-Type', file.mime_type || 'application/octet-stream');
    res.setHeader('Content-Disposition', `attachment; filename="${file.filename}"`);
    
    downloadStream.pipe(res);
    
    downloadStream.on('error', (error) => {
      console.error('❌ File download error:', error);
      if (!res.headersSent) {
        res.status(500).json({
          success: false,
          error: 'Failed to download file'
        });
      }
    });
  } catch (error) {
    console.error('❌ Download file error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to download file',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/files/workspace/:workspaceId
 * @desc    Get all files in a workspace
 * @access  Public
 */
router.get('/workspace/:workspaceId', optionalAuth, async (req, res) => {
  try {
    const filesCollection = getCollection('files');
    const { workspaceId } = req.params;
    
    const files = await filesCollection
      .find({ workspace_id: workspaceId })
      .sort({ upload_timestamp: -1 })
      .toArray();
    
    // Clean up response
    const cleanFiles = files.map(file => {
      const { _id, ...rest } = file;
      return rest;
    });
    
    return res.json({
      success: true,
      count: cleanFiles.length,
      data: cleanFiles
    });
  } catch (error) {
    console.error('❌ Get workspace files error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get files',
      message: error.message
    });
  }
});

module.exports = router;

