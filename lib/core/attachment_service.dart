import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/attachment.dart';

/// One file being uploaded, so the UI can show progress and offer cancel/retry.
class UploadTask {
  UploadTask({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.totalBytes,
  });

  final String id;
  final String fileName;
  final String mimeType;
  final int totalBytes;

  double progress = 0;
  bool done = false;
  String? error;
  UploadTaskHandle? handle;
}

/// Wraps the platform upload so it can be cancelled without the UI touching
/// firebase_storage directly.
class UploadTaskHandle {
  UploadTaskHandle(this._task);
  final Task _task;
  Future<void> cancel() => _task.cancel().then((_) {});
}

/// Uploads, lists and deletes task attachments.
///
/// Metadata lives in Firestore under the task, the bytes live in Storage at the
/// matching path, and both are keyed by the same attachment id so one can
/// always find the other. That is what makes clean-up reliable.
class AttachmentService {
  AttachmentService({FirebaseFirestore? db, FirebaseStorage? storage, String? uid})
      : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _uid = uid ?? FirebaseAuth.instance.currentUser?.uid ?? '_anon';

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final String _uid;

  CollectionReference<Map<String, dynamic>> _collection(String taskId) =>
      _db.collection('users').doc(_uid).collection('tasks').doc(taskId).collection('attachments');

  DocumentReference<Map<String, dynamic>> _taskRef(String taskId) =>
      _db.collection('users').doc(_uid).collection('tasks').doc(taskId);

  Stream<List<Attachment>> watch(String taskId) => _collection(taskId)
      .snapshots()
      .map((s) => s.docs.map(Attachment.fromDoc).toList()
        ..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0))));

  Future<List<Attachment>> list(String taskId) async {
    final snap = await _collection(taskId).get();
    return snap.docs.map(Attachment.fromDoc).toList();
  }

  String storagePathFor(String taskId, String attachmentId) =>
      'users/$_uid/tasks/$taskId/$attachmentId';

  /// Uploads [bytes] (or [file] on platforms where a path is cheaper than
  /// holding the whole file in memory) and writes the metadata document.
  ///
  /// [onProgress] receives 0..1. Throws if the file is larger than the Storage
  /// rules allow, so the user gets a clear message instead of a rules refusal.
  Future<Attachment> upload({
    required String taskId,
    required String originalFileName,
    Uint8List? bytes,
    File? file,
    String? mimeTypeOverride,
    void Function(double progress)? onProgress,
    void Function(UploadTaskHandle handle)? onStarted,
  }) async {
    assert(bytes != null || file != null, 'Provide bytes or a file');

    final size = bytes?.length ?? await file!.length();
    if (size > kMaxAttachmentBytes) {
      throw AttachmentTooLargeException(size);
    }

    final id = const Uuid().v4();
    final safeName = sanitiseFileName(originalFileName);
    final mimeType = mimeTypeOverride ?? mimeTypeForExtension(originalFileName);
    final path = storagePathFor(taskId, id);
    final ref = _storage.ref(path);
    final metadata = SettableMetadata(
      contentType: mimeType,
      customMetadata: {'originalFileName': originalFileName, 'taskId': taskId},
    );

    // Large files stream from disk rather than being held in memory.
    final task = file != null && !kIsWeb
        ? ref.putFile(file, metadata)
        : ref.putData(bytes!, metadata);

    onStarted?.call(UploadTaskHandle(task));

    task.snapshotEvents.listen(
      (snapshot) {
        if (snapshot.totalBytes > 0) {
          onProgress?.call(snapshot.bytesTransferred / snapshot.totalBytes);
        }
      },
      onError: (_) {/* surfaced by awaiting the task below */},
    );

    await task;
    final downloadUrl = await ref.getDownloadURL();

    final attachment = Attachment(
      id: id,
      taskId: taskId,
      fileName: safeName,
      originalFileName: originalFileName,
      storagePath: path,
      downloadUrl: downloadUrl,
      mimeType: mimeType,
      fileSize: size,
      // Until a resizing Cloud Function exists, an image is its own thumbnail.
      thumbnailUrl: mimeType.startsWith('image/') ? downloadUrl : null,
      uploadedBy: _uid,
      createdAt: DateTime.now(),
    );

    await _collection(taskId).doc(id).set(attachment.toJson());
    await _syncCount(taskId);
    return attachment;
  }

  /// Removes the metadata and the stored file together, so no orphan is left.
  Future<void> delete(Attachment attachment) async {
    await _collection(attachment.taskId).doc(attachment.id).delete();
    try {
      await _storage.ref(attachment.storagePath).delete();
    } on FirebaseException catch (e) {
      // An already-missing object is fine; anything else is worth knowing.
      if (e.code != 'object-not-found') rethrow;
    }
    await _syncCount(attachment.taskId);
  }

  /// Deletes every attachment of a task. Call this before deleting the task
  /// itself, otherwise the Storage files are orphaned.
  Future<void> deleteAllFor(String taskId) async {
    final items = await list(taskId);
    for (final a in items) {
      await _collection(taskId).doc(a.id).delete();
      try {
        await _storage.ref(a.storagePath).delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') rethrow;
      }
    }
  }

  /// The card badge reads a plain count, so the board never has to query each
  /// task's attachment subcollection.
  ///
  /// The same write also denormalises a small preview of the first attachment.
  /// Without it a board of fifty cards would need fifty subcollection reads
  /// just to draw thumbnails.
  Future<void> _syncCount(String taskId) async {
    final snapshot = await _collection(taskId).get();
    final items = snapshot.docs.map(Attachment.fromDoc).toList()
      ..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));

    // Prefer an image, so a task with a PDF and a photo shows the photo.
    final preview = items.where((a) => a.isImage).firstOrNull ?? items.firstOrNull;

    await _taskRef(taskId).update({
      'attachmentCount': items.length,
      'attachmentPreview': preview == null
          ? null
          : {
              'mimeType': preview.mimeType,
              'thumbnailUrl': preview.thumbnailUrl,
              'fileName': preview.originalFileName,
            },
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

class AttachmentTooLargeException implements Exception {
  const AttachmentTooLargeException(this.size);
  final int size;

  @override
  String toString() =>
      'That file is ${(size / (1024 * 1024)).toStringAsFixed(1)} MB. The limit is 50 MB.';
}
