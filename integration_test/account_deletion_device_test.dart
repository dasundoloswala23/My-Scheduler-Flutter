// Account deletion against the real Firebase project, with a THROWAWAY account
// created for the run (never the shared test account):
//
//   flutter test integration_test/account_deletion_device_test.dart -d windows
//
// It creates the account, fills it through the real repositories (a board, a
// task, a Project Flow with stages and a link), deletes the data, checks every
// collection is empty, then deletes the account and checks it can no longer sign
// in. Deleting the data first and the account second is also the partial-failure
// path the service is built for: the account still exists after step one.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:myschedule/core/account_service.dart';
import 'package:myschedule/core/repository.dart';
import 'package:myschedule/firebase_options.dart';
import 'package:myschedule/models/collections.dart';
import 'package:myschedule/models/project_flow.dart';
import 'package:myschedule/models/task.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const collections = [
    'tasks',
    'boards',
    'lists',
    'categories',
    'projectFlows',
    'flowStages',
    'flowTaskLinks',
  ];

  testWidgets('deleting an account removes its data and then the account itself', (tester) async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    final auth = FirebaseAuth.instance;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final email = 'flutter-delete-$stamp@example.test';
    final password = 'Tmp-$stamp-pw!';

    final cred = await auth.createUserWithEmailAndPassword(email: email, password: password);
    final uid = cred.user!.uid;
    final db = FirebaseFirestore.instance;
    final user = db.collection('users').doc(uid);

    try {
      final repo = Repo(uid: uid);
      await repo.ensureBootstrap();
      final board = (await user.collection('boards').get()).docs.single.id;
      final todo = (await user.collection('lists').where('boardId', isEqualTo: board).get())
          .docs
          .map(TaskList.fromDoc)
          .firstWhere((l) => l.name == 'Todo');
      final taskId = await repo.createTask(
          Task(id: 'new', title: 'Throwaway', boardId: board, listId: todo.id, position: 1000));
      final flowId = await repo.flows.createFlow(
        ProjectFlow(id: 'new', name: 'Throwaway flow', boardId: board),
        stageTitles: ['One', 'Two'],
      );
      final stage = (await user.collection('flowStages').get()).docs.first.id;
      await repo.flows.linkTask(flowId: flowId, stageId: stage, taskId: taskId);

      Future<Map<String, int>> counts() async => {
            for (final c in collections) c: (await user.collection(c).get()).docs.length,
          };

      final before = await counts();
      expect(before['tasks'], 1);
      expect(before['lists'], 6);
      expect(before['projectFlows'], 1);
      expect(before['flowStages'], 2);
      expect(before['flowTaskLinks'], 1);

      // Step one on its own: the data goes, the account stays (retryable).
      final service = AccountService();
      await service.deleteUserData(uid);
      final mid = await counts();
      expect(mid.values.every((n) => n == 0), isTrue, reason: 'every collection is empty: $mid');
      expect((await user.get()).exists, isFalse, reason: 'the user document is gone');

      // Step two: the whole thing again (idempotent), then the Auth account.
      await service.deleteAccount();
      expect(auth.currentUser, isNull);
      await expectLater(
        auth.signInWithEmailAndPassword(email: email, password: password),
        throwsA(isA<FirebaseAuthException>()),
        reason: 'a deleted account can no longer sign in',
      );
    } finally {
      // Never leave a throwaway account behind if an assertion failed halfway.
      final current = auth.currentUser;
      if (current != null && current.email == email) {
        try {
          await AccountService().deleteUserData(uid);
          await current.delete();
        } catch (_) {}
      }
    }
  });
}
