// Firestore security rules, run against the local emulator (no live project is
// touched):  npm test   (from tools/rules-tests)
//
// Proves: owners can use their own data; other users and signed-out clients
// cannot read or write it; and malformed documents are refused per collection.
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, setDoc, updateDoc, collection, getDocs } from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-rules-test',
    firestore: {
      rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

const alice = () => env.authenticatedContext('alice').firestore();
const bob = () => env.authenticatedContext('bob').firestore();
const anon = () => env.unauthenticatedContext().firestore();
const at = (db, path) => doc(db, path);

// A valid document for each collection the clients write.
const VALID = {
  tasks: { title: 'Write plan', description: 'x', completed: false, subtasks: [], reminders: [] },
  boards: { name: 'Work', position: 1 },
  lists: { name: 'Todo', boardId: 'b1', position: 1 },
  projectFlows: { name: 'Launch', mode: 'sequential', status: 'active', progress: 0 },
  flowStages: { flowId: 'f1', title: 'Plan', isRequired: true, dependencyStageIds: [], status: 'active' },
  flowTaskLinks: { flowId: 'f1', stageId: 's1', taskId: 't1' },
  categories: { name: 'Home' },
  notes: { title: 'n' },
  reminders: { title: 'r' },
  holidays: { name: 'h' },
  focusSessions: { minutes: 25 },
};

describe('ownership', () => {
  for (const [name, data] of Object.entries(VALID)) {
    it(`${name}: the owner can create, read, update and delete`, async () => {
      const ref = at(alice(), `users/alice/${name}/x1`);
      await assertSucceeds(setDoc(ref, data));
      await assertSucceeds(getDoc(ref));
      await assertSucceeds(updateDoc(ref, { updatedNote: 'ok' }));
      await assertSucceeds(deleteDoc(ref));
    });

    it(`${name}: another signed-in user can neither read nor write`, async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), `users/alice/${name}/x1`), data);
      });
      const ref = at(bob(), `users/alice/${name}/x1`);
      await assertFails(getDoc(ref));
      await assertFails(setDoc(ref, data));
      await assertFails(updateDoc(ref, { hacked: true }));
      await assertFails(deleteDoc(ref));
      await assertFails(getDocs(collection(bob(), `users/alice/${name}`)));
    });

    it(`${name}: a signed-out client can neither read nor write`, async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), `users/alice/${name}/x1`), data);
      });
      const ref = at(anon(), `users/alice/${name}/x1`);
      await assertFails(getDoc(ref));
      await assertFails(setDoc(ref, data));
      await assertFails(deleteDoc(ref));
      await assertFails(getDocs(collection(anon(), `users/alice/${name}`)));
    });
  }

  it('attachment metadata under a task follows the same ownership', async () => {
    const path = 'users/alice/tasks/t1/attachments/a1';
    await assertSucceeds(setDoc(at(alice(), path), { fileName: 'f.pdf' }));
    await assertFails(getDoc(at(bob(), path)));
    await assertFails(getDoc(at(anon(), path)));
  });

  it('the user document is private to its owner', async () => {
    await assertSucceeds(setDoc(at(alice(), 'users/alice'), { appPreferences: { theme: 'dark' } }));
    await assertFails(getDoc(at(bob(), 'users/alice')));
    await assertFails(setDoc(at(bob(), 'users/alice'), { appPreferences: {} }));
    await assertFails(getDoc(at(anon(), 'users/alice')));
  });

  it('a user cannot write into another user by claiming the path', async () => {
    await assertFails(setDoc(at(bob(), 'users/alice/tasks/t1'), VALID.tasks));
  });

  it('a collection nobody listed is closed, even to its owner', async () => {
    await assertFails(setDoc(at(alice(), 'users/alice/surprises/x'), { a: 1 }));
    await assertFails(getDoc(at(alice(), 'users/alice/surprises/x')));
  });

  it('top-level collections are closed to everyone', async () => {
    await assertFails(setDoc(at(alice(), 'publicStuff/x'), { a: 1 }));
    await assertFails(getDoc(at(alice(), 'publicStuff/x')));
  });
});

describe('shape: malformed documents are refused', () => {
  const bad = [
    ['tasks', 'a title that is not a string', { title: 42 }],
    ['tasks', 'an absurdly long title', { title: 'x'.repeat(501) }],
    ['tasks', 'a description over the cap', { description: 'x'.repeat(20001) }],
    ['tasks', 'completed that is not a boolean', { completed: 'yes' }],
    ['tasks', 'subtasks that are not a list', { subtasks: 'nope' }],
    ['tasks', 'far too many subtasks', { subtasks: Array.from({ length: 501 }, () => 1) }],
    ['boards', 'a board name that is a number', { name: 7 }],
    ['lists', 'a list name that is a map', { name: { a: 1 } }],
    ['projectFlows', 'a flow with no name', { mode: 'sequential' }],
    ['projectFlows', 'a flow with an empty name', { name: '' }],
    ['projectFlows', 'an unknown mode', { name: 'x', mode: 'chaos' }],
    ['projectFlows', 'an unknown status', { name: 'x', status: 'exploded' }],
    ['projectFlows', 'progress that is text', { name: 'x', progress: 'half' }],
    ['flowStages', 'a stage with no flowId', { title: 'x' }],
    ['flowStages', 'an unknown stage state', { flowId: 'f', status: 'sleepy' }],
    ['flowStages', 'an unknown manual status', { flowId: 'f', manualStatus: 'maybe' }],
    ['flowStages', 'dependencies that are not a list', { flowId: 'f', dependencyStageIds: 'a' }],
    ['flowStages', 'a stage title that is too long', { flowId: 'f', title: 'x'.repeat(301) }],
    ['flowTaskLinks', 'a link with no stage', { flowId: 'f', taskId: 't' }],
    ['flowTaskLinks', 'a link with no task', { flowId: 'f', stageId: 's' }],
  ];

  for (const [name, why, data] of bad) {
    it(`${name}: refuses ${why}`, async () => {
      await assertFails(setDoc(at(alice(), `users/alice/${name}/x1`), data));
    });
  }

  it('an update that would make a good document bad is refused', async () => {
    const ref = at(alice(), 'users/alice/projectFlows/f1');
    await assertSucceeds(setDoc(ref, VALID.projectFlows));
    await assertFails(updateDoc(ref, { mode: 'chaos' }));
    await assertFails(updateDoc(ref, { name: '' }));
  });

  it('valid updates to every validated enum are accepted', async () => {
    const flow = at(alice(), 'users/alice/projectFlows/f1');
    await assertSucceeds(setDoc(flow, VALID.projectFlows));
    await assertSucceeds(updateDoc(flow, { mode: 'flexible' }));
    await assertSucceeds(updateDoc(flow, { mode: 'dependency', status: 'paused' }));
    await assertSucceeds(updateDoc(flow, { progress: 0.5, currentStageId: null }));
    const stage = at(alice(), 'users/alice/flowStages/s1');
    await assertSucceeds(setDoc(stage, VALID.flowStages));
    await assertSucceeds(updateDoc(stage, { status: 'blocked', manualStatus: 'blocked' }));
    await assertSucceeds(updateDoc(stage, { manualStatus: null }));
    await assertSucceeds(updateDoc(stage, { dependencyStageIds: ['a', 'b'] }));
  });

  it('unknown extra fields are allowed, so newer clients keep working', async () => {
    await assertSucceeds(setDoc(at(alice(), 'users/alice/tasks/t1'), { ...VALID.tasks, futureField: { a: 1 } }));
  });

  it('null optional fields are accepted, as clients write them', async () => {
    await assertSucceeds(
      setDoc(at(alice(), 'users/alice/tasks/t1'), {
        ...VALID.tasks,
        startDateTime: null,
        boardId: null,
        categoryId: null,
      }),
    );
    await assertSucceeds(
      setDoc(at(alice(), 'users/alice/projectFlows/f1'), {
        name: 'x',
        boardId: null,
        currentStageId: null,
        startDate: null,
        completedAt: null,
      }),
    );
  });
});
