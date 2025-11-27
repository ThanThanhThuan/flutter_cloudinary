import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart'; // Changed from image_picker
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart'; // To open/download files
import 'package:path/path.dart' as p; // To check extensions

void main() {
  runApp(
    const MaterialApp(
      home: FileUploadScreen(),
      debugShowCheckedModeBanner: false,
    ),
  );
}

class FileUploadScreen extends StatefulWidget {
  const FileUploadScreen({super.key});

  @override
  State<FileUploadScreen> createState() => _FileUploadScreenState();
}

class _FileUploadScreenState extends State<FileUploadScreen> {
  File? _selectedFile;
  PlatformFile? _fileDetails; // Stores name, size, extension
  String? _uploadedFileUrl;
  bool _isUploading = false;

  // TODO: Replace with your actual Cloudinary credentials
  final String cloudName = "YourCloudName";
  final String uploadPreset = "your_upload_preset";

  // 1. Pick ANY File (Image, PDF, Doc, etc)
  Future<void> _pickFile() async {
    // allowMultiple: false, type: FileType.any allows all files
    final result = await FilePicker.platform.pickFiles(type: FileType.any);

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFile = File(result.files.single.path!);
        _fileDetails = result.files.single;
        _uploadedFileUrl = null; // Reset previous upload
      });
    }
  }

  Future<void> _uploadToCloudinarySigned() async {
    if (_selectedFile == null) return;

    setState(() {
      _isUploading = true;
    });

    try {
      // STEP 1: Get Signature from YOUR Backend
      // CHANGE THIS URL based on your device (see note above)
      final backendUrl = Uri.parse('http://10.0.2.2:3000/api/sign-upload');

      final signResponse = await http.get(backendUrl);

      if (signResponse.statusCode != 200) {
        throw Exception("Backend connection failed: ${signResponse.body}");
      }

      final signData = jsonDecode(signResponse.body);

      // Extract data needed for upload
      final String apiKey = signData['api_key'];
      final String timestamp = signData['timestamp'].toString();
      final String signature = signData['signature'];
      final String cloudName = signData['cloud_name'];

      // STEP 2: Upload to Cloudinary using the Signature
      // Notice we do NOT use 'upload_preset' anymore.
      final cloudinaryUrl = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/auto/upload',
      );

      final request = http.MultipartRequest('POST', cloudinaryUrl)
        ..fields['api_key'] = apiKey
        ..fields['timestamp'] = timestamp
        ..fields['signature'] = signature
        // These MUST match exactly what you signed in the Node.js backend
        ..fields['use_filename'] = 'true'
        ..fields['unique_filename'] = 'false'
        ..fields['folder'] = 'flutter_uploads'
        ..files.add(
          await http.MultipartFile.fromPath('file', _selectedFile!.path),
        );

      final response = await request.send();
      final responseData = await response.stream.toBytes();
      final responseString = String.fromCharCodes(responseData);

      if (response.statusCode == 200) {
        final jsonMap = jsonDecode(responseString);
        setState(() {
          _uploadedFileUrl = jsonMap['secure_url'];
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Signed Upload Successful!")),
        );
      } else {
        throw Exception("Cloudinary Error: $responseString");
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      print("Error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // 2. Upload to Cloudinary (Resource Type: Auto)
  Future<void> _uploadToCloudinary() async {
    if (_selectedFile == null) return;

    // TRIM REMOVES ACCIDENTAL SPACES
    final String cleanCloudName = cloudName.trim();
    final String cleanPreset = uploadPreset.trim();

    // 1. Use 'auto' endpoint (Works for Images AND PDFs)
    final String urlString =
        'https://api.cloudinary.com/v1_1/$cleanCloudName/auto/upload';
    final Uri url = Uri.parse(urlString);

    setState(() {
      _isUploading = true;
    });

    try {
      final request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = cleanPreset
        // OPTIONAL: Send the original name as metadata (allowed per your error message)
        // This won't change the URL, but keeps the name in Cloudinary details.
        ..fields['filename_override'] = _selectedFile!.path.split('/').last
        ..files.add(
          await http.MultipartFile.fromPath('file', _selectedFile!.path),
        );

      // --- REMOVED FORBIDDEN FIELDS ---
      // ..fields['use_filename'] = 'true'     <-- CAUSES ERROR
      // ..fields['unique_filename'] = 'false' <-- CAUSES ERROR

      final response = await request.send();

      final responseData = await response.stream.toBytes();
      final responseString = String.fromCharCodes(responseData);

      print("DEBUG Status: ${response.statusCode}");
      print("DEBUG Body: $responseString");

      if (response.statusCode == 200) {
        final jsonMap = jsonDecode(responseString);
        setState(() {
          _uploadedFileUrl = jsonMap['secure_url'];
          _isUploading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Upload Successful!")));
      } else {
        setState(() {
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text("Failed: $responseString"),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // 3. Download / Open File
  Future<void> _openFileUrl() async {
    if (_uploadedFileUrl == null) return;

    final Uri uri = Uri.parse(_uploadedFileUrl!);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Could not launch URL")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Universal File Upload")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Section 1: File Selection Preview ---
            const Text(
              "1. Select File",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _buildFilePreview(),
            ),

            const SizedBox(height: 10),

            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.attach_file),
              label: const Text("Pick File (PDF, Image, Doc)"),
            ),

            const SizedBox(height: 30),

            // --- Section 2: Upload Action ---
            const Text(
              "2. Upload to Cloud",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: (_selectedFile != null && !_isUploading)
                  ? _uploadToCloudinarySigned //_uploadToCloudinary to Switch to non-signed upload
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
              icon: _isUploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.cloud_upload),
              label: Text(_isUploading ? "Uploading..." : "Upload Now"),
            ),

            const SizedBox(height: 30),

            // --- Section 3: Download / Open ---
            const Text(
              "3. Result",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            if (_uploadedFileUrl != null)
              Card(
                color: Colors.green.shade50,
                child: ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: const Text("File Uploaded!"),
                  subtitle: Text(
                    _uploadedFileUrl!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.download),
                    onPressed: _openFileUrl,
                    tooltip: "Open/Download",
                  ),
                ),
              )
            else
              const Text("Upload a file to get the download link."),
          ],
        ),
      ),
    );
  }

  // Helper to decide whether to show an Image or an Icon
  Widget _buildFilePreview() {
    if (_selectedFile == null) {
      return const Center(child: Text("No file selected"));
    }

    // Check extension to decide generic icon vs image preview
    final extension = p.extension(_selectedFile!.path).toLowerCase();
    final isImage = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
    ].contains(extension);

    if (isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(_selectedFile!, fit: BoxFit.contain),
      );
    } else {
      // It's a document (PDF, Doc, etc)
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _getIconForExtension(extension),
            size: 60,
            color: Colors.blueGrey,
          ),
          const SizedBox(height: 10),
          Text(
            _fileDetails?.name ?? "Unknown File",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text("Size: ${_fileDetails?.size} bytes"),
        ],
      );
    }
  }

  IconData _getIconForExtension(String ext) {
    switch (ext) {
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.doc':
      case '.docx':
        return Icons.description;
      case '.xls':
      case '.xlsx':
        return Icons.table_chart;
      case '.txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }
}
