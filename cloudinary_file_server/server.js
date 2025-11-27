const express = require('express');
const cors = require('cors');
const cloudinary = require('cloudinary').v2;
require('dotenv').config();

const app = express();
app.use(cors()); // Allows Flutter to talk to this server
app.use(express.json());

// Configure Cloudinary
cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET
});

// Endpoint to get the signature
app.get('/api/sign-upload', (req, res) => {
    const timestamp = Math.round((new Date).getTime() / 1000);

    // Parameters we want to allow in the upload
    const paramsToSign = {
        timestamp: timestamp,
        use_filename: true,      // We want to keep original names
        unique_filename: false,  // Don't add random characters
        folder: 'flutter_uploads' // Optional: organize files
    };

    // Generate Signature
    const signature = cloudinary.utils.api_sign_request(
        paramsToSign,
        process.env.CLOUDINARY_API_SECRET
    );

    // Send back to Flutter
    res.json({
        signature: signature,
        timestamp: timestamp,
        cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
        api_key: process.env.CLOUDINARY_API_KEY,
        // We must send back the exact params we signed
        use_filename: true,
        unique_filename: false,
        folder: 'flutter_uploads'
    });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`Backend running on port ${PORT}`);
});