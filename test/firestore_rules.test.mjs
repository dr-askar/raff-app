import { readFile } from 'node:fs/promises';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, serverTimestamp, writeBatch } from 'firebase/firestore';

let env;
const path = suffix => `stores/main/${suffix}`;
const product = { name: 'حليب', category: 'ألبان', barcode: '123', pack: 12, quantity: 24,
  saleBaseUsd: 1.2, manualPrice: null, ready: true, revision: 1 };
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-raff',
    firestore: { rules: await readFile('firestore.rules', 'utf8'), host: '127.0.0.1', port: 8080 } });
});
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, path('members/owner')), { name: 'مالك', role: 'owner', active: true }),
      setDoc(doc(db, path('members/worker')), { name: 'عامل', role: 'worker', active: true }),
      setDoc(doc(db, path('members/disabled')), { name: 'معطل', role: 'worker', active: false }),
      setDoc(doc(db, path('products/p')), product),
      setDoc(doc(db, path('pricing/p')), { costUsd: 1, margin: 20 }),
      setDoc(doc(db, path('settings/current')), { rate: 10000, margin: 20, currency: 'ل.س', revision: 0 }),
      setDoc(doc(db, path('stocktakes/active')), { id: 'session', at: '2026-10-14', rate: 10000, currency: 'ل.س', closed: false, countRevision: 0, productIds: ['p'] }),
    ]);
  });
});
test('anonymous and unrelated users cannot read the shop', async () => {
  for (const db of [env.unauthenticatedContext().firestore(), env.authenticatedContext('stranger').firestore()]) {
    await assertFails(getDoc(doc(db, path('products/p'))));
  }
});
test('worker reads retail data but not private cost, and cannot edit pricing', async () => {
  const db = env.authenticatedContext('worker').firestore();
  await assertSucceeds(getDoc(doc(db, path('products/p'))));
  await assertFails(getDoc(doc(db, path('pricing/p'))));
  await assertFails(updateDoc(doc(db, path('products/p')), { quantity: 99, revision: 2 }));
  await assertFails(updateDoc(doc(db, path('settings/current')), { rate: 2 }));
});
test('worker cannot promote themselves or join another shop', async () => {
  const db = env.authenticatedContext('worker').firestore();
  await assertFails(updateDoc(doc(db, path('members/worker')), { role: 'owner' }));
  await assertFails(setDoc(doc(db, 'stores/other/members/worker'), { name: 'عامل', role: 'owner', active: true }));
});
test('owner can edit pricing with incremented revision; stale writes fail', async () => {
  const db = env.authenticatedContext('owner').firestore();
  await assertSucceeds(getDoc(doc(db, path('pricing/p'))));
  await assertSucceeds(updateDoc(doc(db, path('products/p')), { quantity: 30, revision: 2 }));
  await assertFails(updateDoc(doc(db, path('products/p')), { quantity: 35, revision: 2 }));
});
test('worker counts only an active session and cannot submit a negative count', async () => {
  const db = env.authenticatedContext('worker').firestore();
  const count = { sessionId: 'session', count: 7, updatedBy: 'worker', at: serverTimestamp() };
  async function writeCount(data) {
    const ref = doc(db, path('stocktakes/active'));
    const active = await getDoc(ref);
    const batch = writeBatch(db);
    batch.update(ref, { countRevision: active.data().countRevision + 1 });
    batch.set(doc(db, path('stockCounts/p')), { ...data, countRevision: active.data().countRevision + 1 });
    return batch.commit();
  }
  await assertFails(setDoc(doc(db, path('stockCounts/p')), count));
  await assertSucceeds(writeCount(count));
  await assertFails(writeCount({ ...count, count: -1 }));
  await assertFails(writeCount({ ...count, sessionId: 'old' }));
  await env.withSecurityRulesDisabled(context => updateDoc(doc(context.firestore(), path('stocktakes/active')), { closed: true }));
  await assertFails(writeCount(count));
});
test('disabled accounts lose product access', async () => {
  await assertFails(getDoc(doc(env.authenticatedContext('disabled').firestore(), path('products/p'))));
});
