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
      setDoc(doc(db, path('costs/p')), { costUsd: 1, costLocal: null }),
      setDoc(doc(db, path('margins/p')), { margin: 20 }),
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
  await assertFails(getDoc(doc(db, path('costs/p'))));
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
  await assertSucceeds(getDoc(doc(db, path('costs/p'))));
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

async function grant(permissions) {
  await env.withSecurityRulesDisabled(ctx => updateDoc(doc(ctx.firestore(), path('members/worker')), { permissions }));
}
test('owner assigns permissions; worker cannot grant themselves access', async () => {
  const owner = env.authenticatedContext('owner').firestore();
  await assertSucceeds(updateDoc(doc(owner, path('members/worker')), { permissions: { viewCost: true, editExchangeRate: true } }));
  const worker = env.authenticatedContext('worker').firestore();
  await assertSucceeds(getDoc(doc(worker, path('costs/p'))));
  await assertFails(updateDoc(doc(worker, path('members/worker')), { permissions: { deleteProduct: true } }));
  await assertFails(updateDoc(doc(owner, path('members/worker')), { permissions: { editCost: true, viewCost: false } }));
  await assertFails(updateDoc(doc(owner, path('members/worker')), { permissions: { unknown: true } }));
});
test('exchange permission cannot change global margin or private costs', async () => {
  await grant({ editExchangeRate: true });
  const db = env.authenticatedContext('worker').firestore();
  await assertSucceeds(updateDoc(doc(db, path('settings/current')), { rate: 12000, revision: 1 }));
  await assertFails(updateDoc(doc(db, path('settings/current')), { margin: 50, revision: 2 }));
  await assertFails(getDoc(doc(db, path('costs/p'))));
  await grant({ editExchangeRate: false });
  await assertFails(updateDoc(doc(db, path('settings/current')), { rate: 14000, revision: 2 }));
});
test('quantity permission cannot edit names, sale prices or automatic price bases', async () => {
  await grant({ editQuantity: true });
  const db = env.authenticatedContext('worker').firestore();
  const meta = { updatedBy: 'worker', updatedAt: serverTimestamp() };
  await assertSucceeds(updateDoc(doc(db, path('products/p')), { ...meta, quantity: 7, revision: 2, costCurrency: 'USD', saleBaseLocal: null }));
  await assertFails(updateDoc(doc(db, path('products/p')), { ...meta, name: 'تعديل ممنوع', revision: 3 }));
  await assertFails(updateDoc(doc(db, path('products/p')), { ...meta, manualPrice: 9000, revision: 3 }));
  await assertFails(updateDoc(doc(db, path('products/p')), { ...meta, saleBaseUsd: 9, revision: 3 }));
  await assertFails(setDoc(doc(db, path('costs/p')), { costUsd: 9, margin: 20 }));
});
test('adding and deleting require independent permissions and preserve active stocktakes', async () => {
  const db = env.authenticatedContext('worker').firestore();
  const fresh = { ...product, barcode: '', quantity: 0, saleBaseUsd: 0, ready: false };
  await assertFails(setDoc(doc(db, path('products/new')), fresh));
  await grant({ addProduct: true });
  await assertSucceeds(setDoc(doc(db, path('products/new')), fresh));
  await assertFails(setDoc(doc(db, path('products/another')), { ...fresh, quantity: 40 }));
  let batch = writeBatch(db); batch.delete(doc(db, path('products/new')));
  await assertFails(batch.commit());
  await grant({ deleteProduct: true });
  batch = writeBatch(db); batch.delete(doc(db, path('products/p')));
  await assertFails(batch.commit());
  batch = writeBatch(db); batch.delete(doc(db, path('products/new'))); batch.delete(doc(db, path('costs/new')));
  await assertSucceeds(batch.commit());
});
test('SYP costs stay private and cost editing requires both cost permissions', async () => {
  const db = env.authenticatedContext('worker').firestore();
  await grant({ viewCost: true });
  await assertSucceeds(getDoc(doc(db, path('costs/p'))));
  await assertFails(setDoc(doc(db, path('costs/p')), { costUsd: null, costLocal: 5000 }));
  await grant({ viewCost: true, editCost: true });
  const batch = writeBatch(db);
  batch.update(doc(db, path('products/p')), { costCurrency: 'SYP', saleBaseUsd: 0, saleBaseLocal: 6000, revision: 2, updatedBy: 'worker', updatedAt: serverTimestamp() });
  batch.set(doc(db, path('costs/p')), { costUsd: null, costLocal: 5000 });
  await assertSucceeds(batch.commit());
  await grant({ viewCost: false, editCost: false });
  await assertFails(getDoc(doc(db, path('costs/p'))));
});
test('stocktake visibility and count entry can be revoked independently', async () => {
  const db = env.authenticatedContext('worker').firestore();
  await grant({ viewStocktake: false, countStock: false });
  await assertFails(getDoc(doc(db, path('stocktakes/active'))));
  await grant({ viewStocktake: true, countStock: false });
  await assertSucceeds(getDoc(doc(db, path('stocktakes/active'))));
  await assertFails(updateDoc(doc(db, path('stocktakes/active')), { countRevision: 1 }));
});

test('cost and margin reads are independent, including legacy bundled documents', async () => {
  await env.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(), path('pricing/legacy')), { costUsd: 1, margin: 60 }));
  const db = env.authenticatedContext('worker').firestore();
  await grant({ viewCost: true });
  await assertSucceeds(getDoc(doc(db, path('costs/p'))));
  await assertFails(getDoc(doc(db, path('margins/p'))));
  await assertFails(getDoc(doc(db, path('pricing/legacy'))));
  await grant({ viewMargin: true });
  await assertSucceeds(getDoc(doc(db, path('margins/p'))));
  await assertFails(getDoc(doc(db, path('costs/p'))));
  await assertFails(getDoc(doc(db, path('pricing/legacy'))));
});
test('profit editing does not grant cost editing or permission to change bargaining limits', async () => {
  await grant({ viewMargin: true, editMargin: true });
  const db = env.authenticatedContext('worker').firestore();
  const batch = writeBatch(db);
  batch.update(doc(db, path('products/p')), { saleBaseUsd: 1.3, revision: 2, updatedBy: 'worker', updatedAt: serverTimestamp() });
  batch.set(doc(db, path('margins/p')), { margin: 30 });
  await assertSucceeds(batch.commit());
  await assertFails(setDoc(doc(db, path('costs/p')), { costUsd: 5, costLocal: null }));
  await assertFails(updateDoc(doc(db, path('products/p')), { bargainPercent: 90, revision: 3, updatedBy: 'worker', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db, path('products/p')), { costCurrency: 'SYP', revision: 3, updatedBy: 'worker', updatedAt: serverTimestamp() }));
});
test('owner alone sets per-item bargaining limits', async () => {
  const owner = env.authenticatedContext('owner').firestore();
  await assertSucceeds(updateDoc(doc(owner, path('products/p')), { bargainPercent: 5, revision: 2 }));
  await assertFails(updateDoc(doc(owner, path('products/p')), { bargainPercent: 101, revision: 3 }));
  await grant({ editDetails: true, applyBargain: true });
  const db = env.authenticatedContext('worker').firestore();
  await assertFails(updateDoc(doc(db, path('products/p')), { bargainPercent: 10, revision: 3, updatedBy: 'worker', updatedAt: serverTimestamp() }));
});


test('owner stores weighted packs and fractional quantities; ordinary worker cannot change units', async () => {
  const owner = env.authenticatedContext('owner').firestore();
  await assertSucceeds(updateDoc(doc(owner, path('products/p')), { unit: 'kg', pack: 12.5, quantity: 0.125, revision: 2 }));
  const worker = env.authenticatedContext('worker').firestore();
  await assertFails(updateDoc(doc(worker, path('products/p')), { unit: 'piece', pack: 12, revision: 3 }));
  await assertFails(updateDoc(doc(owner, path('products/p')), { unit: 'piece', pack: 0.5, revision: 3 }));
});
test('restore permission grants restoration writes without cost visibility or membership changes', async () => {
  await env.withSecurityRulesDisabled(context => updateDoc(doc(context.firestore(), path('members/worker')), { permissions: { restoreBackup: true } }));
  const db = env.authenticatedContext('worker').firestore();
  await assertSucceeds(updateDoc(doc(db, path('products/p')), { unit: 'kg', pack: 0.5, quantity: 0.125, revision: 2, updatedBy: 'worker', updatedAt: serverTimestamp() }));
  await assertSucceeds(setDoc(doc(db, path('costs/p')), { costUsd: 2, costLocal: null }));
  await assertSucceeds(setDoc(doc(db, path('margins/p')), { margin: 15 }));
  await assertSucceeds(updateDoc(doc(db, path('settings/current')), { rate: 15000, margin: 15, revision: 1 }));
  await assertFails(getDoc(doc(db, path('costs/p'))));
  await assertFails(getDoc(doc(db, path('margins/p'))));
  await assertFails(updateDoc(doc(db, path('members/worker')), { role: 'owner' }));
  await env.withSecurityRulesDisabled(context => updateDoc(doc(context.firestore(), path('members/worker')), { permissions: {} }));
  await assertFails(setDoc(doc(db, path('costs/p')), { costUsd: 3, costLocal: null }));
});
