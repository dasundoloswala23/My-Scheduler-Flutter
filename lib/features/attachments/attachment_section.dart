import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../core/attachment_service.dart';
import '../../models/attachment.dart';
import 'image_viewer.dart';

/// Attachment list, picker and upload progress for one task.
///
/// Images show a real thumbnail and open full screen; everything else shows a
/// type icon with the file name and size.
class AttachmentSection extends StatefulWidget {
  const AttachmentSection({super.key, required this.taskId, required this.service});

  final String taskId;
  final AttachmentService service;

  @override
  State<AttachmentSection> createState() => _AttachmentSectionState();
}

class _AttachmentSectionState extends State<AttachmentSection> {
  final List<_Upload> _uploads = [];

  bool get _canCaptureImage =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // ------------------------------------------------------------------ picking

  Future<void> _pickFiles({FileType type = FileType.any}) async {
    final files = await FilePicker.pickFiles(type: type);
    for (final picked in files) {
      // On native platforms the path lets Storage stream from disk rather than
      // holding the whole file in memory; on web there is no path, so read the
      // bytes instead.
      final path = picked.path;
      await _startUpload(
        name: picked.name,
        bytes: path == null ? await picked.readAsBytes() : null,
        file: path == null ? null : File(path),
      );
    }
  }

  Future<void> _capturePhoto() async {
    final picker = ImagePicker();
    final shot = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (shot == null) return;
    await _startUpload(
      name: shot.name,
      bytes: kIsWeb ? await shot.readAsBytes() : null,
      file: kIsWeb ? null : File(shot.path),
    );
  }

  // ----------------------------------------------------------------- uploading

  Future<void> _startUpload({required String name, Uint8List? bytes, File? file}) async {
    final upload = _Upload(name: name, bytes: bytes, file: file);
    setState(() => _uploads.add(upload));
    await _runUpload(upload);
  }

  Future<void> _runUpload(_Upload upload) async {
    setState(() {
      upload.error = null;
      upload.progress = 0;
      upload.cancelled = false;
    });

    try {
      await widget.service.upload(
        taskId: widget.taskId,
        originalFileName: upload.name,
        bytes: upload.bytes,
        file: upload.file,
        onStarted: (handle) => upload.handle = handle,
        onProgress: (p) {
          if (mounted) setState(() => upload.progress = p);
        },
      );
      if (mounted) setState(() => _uploads.remove(upload));
    } catch (e) {
      if (!mounted) return;
      if (upload.cancelled) {
        setState(() => _uploads.remove(upload));
        return;
      }
      setState(() => upload.error = e is AttachmentTooLargeException ? e.toString() : 'Upload failed');
    }
  }

  Future<void> _cancel(_Upload upload) async {
    upload.cancelled = true;
    await upload.handle?.cancel();
    if (mounted) setState(() => _uploads.remove(upload));
  }

  // ------------------------------------------------------------------- deleting

  Future<void> _delete(Attachment attachment) async {
    try {
      await widget.service.delete(attachment);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete that attachment.')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Attachment>>(
      stream: widget.service.watch(widget.taskId),
      builder: (context, snapshot) {
        final attachments = snapshot.data ?? const <Attachment>[];
        final images = attachments.where((a) => a.isImage).toList();
        final loading = snapshot.connectionState == ConnectionState.waiting;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Attachments',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                if (attachments.isNotEmpty)
                  Text('${attachments.length}',
                      style: TextStyle(color: context.palette.textSecondary, fontSize: 13)),
                const Spacer(),
                _AddMenu(
                  canCapture: _canCaptureImage,
                  onPickAny: () => _pickFiles(),
                  onPickImage: () => _pickFiles(type: FileType.image),
                  onCapture: _capturePhoto,
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (loading && attachments.isEmpty && _uploads.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (snapshot.hasError)
              _ErrorRow(onRetry: () => setState(() {}))
            else if (attachments.isEmpty && _uploads.isEmpty)
              Text('No attachments yet.',
                  style: TextStyle(color: context.palette.textSecondary, fontSize: 13)),

            for (final upload in _uploads) _UploadRow(
                  upload: upload,
                  onCancel: () => _cancel(upload),
                  onRetry: () => _runUpload(upload),
                ),

            for (final attachment in attachments)
              _AttachmentRow(
                attachment: attachment,
                onOpen: () {
                  if (!attachment.isImage) return;
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ImageViewerPage(
                      images: images,
                      initialIndex: images.indexWhere((a) => a.id == attachment.id),
                      onDelete: _delete,
                    ),
                  ));
                },
                onDelete: () => _delete(attachment),
              ),
          ],
        );
      },
    );
  }
}

class _Upload {
  _Upload({required this.name, this.bytes, this.file});

  final String name;
  final Uint8List? bytes;
  final File? file;

  double progress = 0;
  String? error;
  bool cancelled = false;
  UploadTaskHandle? handle;
}

class _AddMenu extends StatelessWidget {
  const _AddMenu({
    required this.canCapture,
    required this.onPickAny,
    required this.onPickImage,
    required this.onCapture,
  });

  final bool canCapture;
  final VoidCallback onPickAny;
  final VoidCallback onPickImage;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Add attachment',
      onSelected: (value) => switch (value) {
        'image' => onPickImage(),
        'camera' => onCapture(),
        _ => onPickAny(),
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'file',
          child: ListTile(leading: Icon(Icons.attach_file), title: Text('Choose files')),
        ),
        const PopupMenuItem(
          value: 'image',
          child: ListTile(leading: Icon(Icons.image_outlined), title: Text('Choose images')),
        ),
        if (canCapture)
          const PopupMenuItem(
            value: 'camera',
            child: ListTile(leading: Icon(Icons.photo_camera_outlined), title: Text('Take a photo')),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: context.palette.selected,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add, size: 16, color: AppColors.primary),
          SizedBox(width: 5),
          Text('Add', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
        ]),
      ),
    );
  }
}

class _UploadRow extends StatelessWidget {
  const _UploadRow({required this.upload, required this.onCancel, required this.onRetry});

  final _Upload upload;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = upload.error != null;
    final percent = (upload.progress * 100).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: failed ? context.palette.danger : Colors.transparent),
      ),
      child: Row(
        children: [
          Icon(failed ? Icons.error_outline : Icons.upload_file,
              size: 20, color: failed ? context.palette.danger : AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(failed ? upload.error! : 'Uploading…',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: failed ? context.palette.danger : context.palette.textSecondary,
                    )),
                const SizedBox(height: 2),
                Text(upload.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                if (!failed) ...[
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: upload.progress == 0 ? null : upload.progress,
                      minHeight: 5,
                      backgroundColor: context.palette.selected,
                      valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (failed)
            TextButton(onPressed: onRetry, child: const Text('Retry'))
          else
            Text('$percent%',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.palette.textSecondary)),
          IconButton(
            tooltip: 'Cancel',
            onPressed: onCancel,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.attachment,
    required this.onOpen,
    required this.onDelete,
  });

  final Attachment attachment;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  IconData get _icon {
    if (attachment.isPdf) return Icons.picture_as_pdf;
    if (attachment.isVideo) return Icons.videocam_outlined;
    if (attachment.isAudio) return Icons.audiotrack_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 46,
                height: 46,
                child: attachment.isImage
                    ? CachedNetworkImage(
                        imageUrl: attachment.thumbnailUrl ?? attachment.downloadUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, _) => Container(
                          color: context.palette.selected,
                          child: const Center(
                            child: SizedBox(
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        errorWidget: (context, _, _) => Container(
                          color: context.palette.selected,
                          child: const Icon(Icons.broken_image_outlined,
                              size: 18, color: AppColors.primary),
                        ),
                      )
                    : Container(
                        color: context.palette.selected,
                        child: Icon(_icon, color: AppColors.primary, size: 20),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(attachment.originalFileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text('${attachment.readableSize} · ${_label()}',
                      style: TextStyle(fontSize: 11.5, color: context.palette.textSecondary)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 19),
            ),
          ],
        ),
      ),
    );
  }

  String _label() {
    if (attachment.isImage) return 'Image';
    if (attachment.isPdf) return 'PDF';
    if (attachment.isVideo) return 'Video';
    if (attachment.isAudio) return 'Audio';
    return 'File';
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.cloud_off, size: 18, color: context.palette.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Could not load attachments.',
              style: TextStyle(color: context.palette.textSecondary, fontSize: 13)),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
