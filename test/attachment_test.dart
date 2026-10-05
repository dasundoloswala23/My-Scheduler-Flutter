import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/models/attachment.dart';

Attachment make({required String mime, int size = 1024}) => Attachment(
      id: 'a1',
      taskId: 't1',
      fileName: 'file',
      originalFileName: 'file',
      storagePath: 'users/u/tasks/t1/a1',
      downloadUrl: 'https://example.com/a1',
      mimeType: mime,
      fileSize: size,
      uploadedBy: 'u',
    );

void main() {
  group('mimeTypeForExtension', () {
    test('recognises common images', () {
      expect(mimeTypeForExtension('photo.jpg'), 'image/jpeg');
      expect(mimeTypeForExtension('photo.JPEG'), 'image/jpeg');
      expect(mimeTypeForExtension('shot.png'), 'image/png');
      expect(mimeTypeForExtension('loop.gif'), 'image/gif');
    });

    test('recognises documents, video and audio', () {
      expect(mimeTypeForExtension('report.pdf'), 'application/pdf');
      expect(mimeTypeForExtension('clip.mp4'), 'video/mp4');
      expect(mimeTypeForExtension('voice.mp3'), 'audio/mpeg');
      expect(
        mimeTypeForExtension('sheet.xlsx'),
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    });

    test('falls back for anything unknown', () {
      expect(mimeTypeForExtension('mystery.zzz'), 'application/octet-stream');
    });
  });

  group('sanitiseFileName', () {
    test('keeps ordinary names intact', () {
      expect(sanitiseFileName('holiday photo.png'), 'holiday photo.png');
      expect(sanitiseFileName('report-v2.final.pdf'), 'report-v2.final.pdf');
    });

    test('replaces characters that break storage paths', () {
      expect(sanitiseFileName('in/voice:2026?.pdf'), 'in_voice_2026_.pdf');
    });

    test('never returns an empty name', () {
      expect(sanitiseFileName('///'), 'file');
      expect(sanitiseFileName('   '), 'file');
    });
  });

  group('Attachment type flags', () {
    test('classifies by mime type', () {
      expect(make(mime: 'image/png').isImage, isTrue);
      expect(make(mime: 'video/mp4').isVideo, isTrue);
      expect(make(mime: 'audio/mpeg').isAudio, isTrue);
      expect(make(mime: 'application/pdf').isPdf, isTrue);

      final pdf = make(mime: 'application/pdf');
      expect(pdf.isImage, isFalse);
      expect(pdf.isVideo, isFalse);
    });
  });

  group('readableSize', () {
    test('shows bytes, kilobytes and megabytes', () {
      expect(make(mime: 'image/png', size: 512).readableSize, '512 B');
      expect(make(mime: 'image/png', size: 2048).readableSize, '2 KB');
      expect(make(mime: 'image/png', size: 2516582).readableSize, '2.4 MB');
    });
  });

  test('the size limit matches what the storage rules enforce', () {
    expect(kMaxAttachmentBytes, 50 * 1024 * 1024);
  });
}
