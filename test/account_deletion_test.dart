import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/account_service.dart';
import 'package:myschedule/core/attachment_service.dart';

class _Auth extends Fake implements FirebaseAuth {}

class _Storage extends Fake implements FirebaseStorage {}

const _collections = [
  'tasks',
  'boards',
  'lists',
  'categories',
  'notes',
  'reminders',
  'holidays',
  'focusSessions',
  'projectFlows',
  'flowLinks',
];

Future<void> _seed(FakeFirebaseFirestore db, String uid) async {
  final user = db.collection('users').doc(uid);
  await user.set({'preferences': {'theme': 'dark'}});
  for (final name in _collections) {
    for (var i = 0; i < 3; i++) {
      await user.collection(name).doc('$name-$i').set({'n': i});
    }
  }
  // Subcollections that hang off other documents.
  await user.collection('projectFlows').doc('projectFlows-0').collection('stages').doc('s1').set({'n': 1});
  await user.collection('projectFlows').doc('projectFlows-1').collection('stages').doc('s2').set({'n': 2});
}

Future<int> _countFor(FakeFirebaseFirestore db, String uid) async {
  final user = db.collection('users').doc(uid);
  var total = (await user.get()).exists ? 1 : 0;
  for (final name in _collections) {
    total += (await user.collection(name).get()).docs.length;
  }
  for (final flow in ['projectFlows-0', 'projectFlows-1']) {
    total += (await user.collection('projectFlows').doc(flow).collection('stages').get()).docs.length;
  }
  return total;
}

void main() {
  late FakeFirebaseFirestore db;
  late int cancelled;
  late AccountService service;

  setUp(() async {
    db = FakeFirebaseFirestore();
    cancelled = 0;
    service = AccountService(
      auth: _Auth(),
      db: db,
      cancelLocalReminders: () async => cancelled++,
    );
    await _seed(db, 'alice');
    await _seed(db, 'bob');
    // Shared data that is not any one person's.
    await db.collection('sharedHolidayTables').doc('LK-2026').set({'name': 'shared'});
  });

  AttachmentService attachmentsFor(String uid) =>
      AttachmentService(db: db, storage: _Storage(), uid: uid);

  test('removes every document the user owns, including flow stages', () async {
    expect(await _countFor(db, 'alice'), greaterThan(30));

    await service.deleteUserData('alice', attachments: attachmentsFor('alice'));

    expect(await _countFor(db, 'alice'), 0);
  });

  test('never touches another user or shared data', () async {
    final bobBefore = await _countFor(db, 'bob');

    await service.deleteUserData('alice', attachments: attachmentsFor('alice'));

    expect(await _countFor(db, 'bob'), bobBefore);
    expect((await db.collection('sharedHolidayTables').doc('LK-2026').get()).exists, isTrue);
  });

  test('clears the reminders scheduled on this device', () async {
    await service.deleteUserData('alice', attachments: attachmentsFor('alice'));
    expect(cancelled, 1);
  });

  test('a failure to clear local reminders does not fail the deletion', () async {
    final failing = AccountService(
      auth: _Auth(),
      db: db,
      cancelLocalReminders: () async => throw StateError('platform said no'),
    );
    await failing.deleteUserData('alice', attachments: attachmentsFor('alice'));
    expect(await _countFor(db, 'alice'), 0);
  });

  test('running it again after a partial failure finishes the job', () async {
    // A first attempt that only got partway.
    await db.collection('users').doc('alice').collection('tasks').doc('tasks-0').delete();
    await db.collection('users').doc('alice').collection('boards').doc('boards-1').delete();

    await service.deleteUserData('alice', attachments: attachmentsFor('alice'));
    await service.deleteUserData('alice', attachments: attachmentsFor('alice')); // and again

    expect(await _countFor(db, 'alice'), 0);
  });

  test('attachment metadata under tasks goes too', () async {
    await db
        .collection('users')
        .doc('alice')
        .collection('tasks')
        .doc('tasks-0')
        .collection('attachments')
        .doc('a1')
        .set({'taskId': 'tasks-0', 'storagePath': 'x', 'fileName': 'f', 'contentType': 'text/plain', 'size': 1});
    // A fake Storage has no objects, so only the metadata path is exercised.
    final fake = _MetadataOnly(db, 'alice');
    await service.deleteUserData('alice', attachments: fake);
    expect((await db.collection('users').doc('alice').collection('tasks').get()).docs, isEmpty);
  });
}

/// Stands in for [AttachmentService] where there is no Storage to talk to.
class _MetadataOnly extends Fake implements AttachmentService {
  _MetadataOnly(this.db, this.uid);
  final FakeFirebaseFirestore db;
  final String uid;
  final deleted = <String>[];

  @override
  Future<void> deleteAllFor(String taskId) async {
    final col = db.collection('users').doc(uid).collection('tasks').doc(taskId).collection('attachments');
    for (final d in (await col.get()).docs) {
      await d.reference.delete();
    }
    deleted.add(taskId);
  }
}
