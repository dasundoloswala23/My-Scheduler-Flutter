import 'package:cloud_firestore/cloud_firestore.dart';

/// A real file stored in Firebase Storage, with its metadata in Firestore at
/// `users/{uid}/tasks/{taskId}/attachments/{attachmentId}`.
///
/// The file itself lives at `users/{uid}/tasks/{taskId}/{attachmentId}`, which
/// is the path storage.rules guards, so ownership is decided by the path alone.
class Attachment {
  const Attachment({
    required this.id,
    required this.taskId,
    required this.fileName,
    required this.originalFileName,
    required this.storagePath,
    required this.downloadUrl,
    required this.mimeType,
    required this.fileSize,
    required this.uploadedBy,
    this.thumbnailUrl,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String taskId;

  /// Sanitised name used for storage and display.
  final String fileName;

  /// Exactly what the file was called on the user's device.
  final String originalFileName;

  final String storagePath;
  final String downloadUrl;
  final String mimeType;
  final int fileSize;
  final String uploadedBy;

  /// Only images get one; for now it is the image itself, since Storage
  /// resizing needs a Cloud Function.
  final String? thumbnailUrl;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');
  bool get isAudio => mimeType.startsWith('audio/');
  bool get isPdf => mimeType == 'application/pdf';

  /// "2.4 MB", for the file row in the task sheet.
  String get readableSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(0)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'fileName': fileName,
        'originalFileName': originalFileName,
        'storagePath': storagePath,
        'downloadUrl': downloadUrl,
        'mimeType': mimeType,
        'fileSize': fileSize,
        'thumbnailUrl': thumbnailUrl,
        'uploadedBy': uploadedBy,
        'createdAt': createdAt == null ? FieldValue.serverTimestamp() : Timestamp.fromDate(createdAt!),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory Attachment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final json = doc.data() ?? const {};
    return Attachment(
      id: doc.id,
      taskId: (json['taskId'] ?? '') as String,
      fileName: (json['fileName'] ?? '') as String,
      originalFileName: (json['originalFileName'] ?? json['fileName'] ?? '') as String,
      storagePath: (json['storagePath'] ?? '') as String,
      downloadUrl: (json['downloadUrl'] ?? '') as String,
      mimeType: (json['mimeType'] ?? 'application/octet-stream') as String,
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      uploadedBy: (json['uploadedBy'] ?? '') as String,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Maps a file extension to a MIME type, because file_picker does not always
/// report one on desktop.
String mimeTypeForExtension(String fileName) {
  final ext = fileName.toLowerCase().split('.').last;
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'bmp' => 'image/bmp',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'csv' => 'text/csv',
    'doc' => 'application/msword',
    'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt' => 'application/vnd.ms-powerpoint',
    'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'zip' => 'application/zip',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    'mp3' => 'audio/mpeg',
    'wav' => 'audio/wav',
    'm4a' => 'audio/mp4',
    _ => 'application/octet-stream',
  };
}

/// Strips characters that make for awkward storage object names.
///
/// A name made only of separators sanitises to nothing meaningful (`///`
/// becomes `___`), so those fall back to a plain name rather than being shown
/// to the user as punctuation.
String sanitiseFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[^\w\s.\-]'), '_').trim();
  final hasRealCharacter = RegExp(r'[a-zA-Z0-9]').hasMatch(cleaned);
  return hasRealCharacter ? cleaned : 'file';
}

/// The largest file the Storage rules will accept.
const int kMaxAttachmentBytes = 50 * 1024 * 1024;
