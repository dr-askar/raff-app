import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../domain/models.dart';
import '../domain/worker_access.dart';
import 'owner_lock.dart';

class ImportResult {
  final int added, updated;
  final List<String> errors;
  final int unprocessed;
  final String? stoppedReason;
  const ImportResult({required this.added, required this.updated, required this.errors,
    this.unprocessed = 0, this.stoppedReason});
  int get saved => added + updated;
  int get failed => errors.length;
}

class AppStore extends ChangeNotifier {
  final bool cloud;
  final String storeId;
  final SharedPreferences prefs;
  AppStore({required this.prefs, this.cloud = false, this.storeId = 'main'});
  static const _key = 'raff.demo.v1';
  static const _uuid = Uuid();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Map<String, Json> _public = {}, _pricing = {}, _margins = {};
  Json? _stockMeta, _stockCosts;
  final Map<String, Json> _stockCounts = {};
  bool _stockReady = false;
  bool _productsReady = false, _pricingReady = false, _marginsReady = false, _settingsReady = false;
  final Map<String, SnapshotMetadata> _metadataSources = {};
  List<Product> products = [];
  List<PriceChange> history = [];
  StoreSettings settings = const StoreSettings();
  Stocktake? stocktake;
  bool owner = true, fromCache = false, pending = false, loaded = false;
  String actor = 'صاحب المحل', error = '';
  WorkerAccess workerAccess = const WorkerAccess();
  late final OwnerLock ownerLock = OwnerLock(prefs);
  DateTime? _adminUntil, _retryAfter;
  int _passwordFailures = 0;
  bool can(String permission) => usable && (owner || workerAccess.allows(permission));
  bool get canEditProduct => owner || ['editDetails', 'editQuantity', 'editSalePrice', 'editCost', 'editMargin'].any(can);
  bool get hasOwnerPassword => cloud || ownerLock.configured;
  void _require(bool allowed) {
    if (!allowed || !usable) { throw const FormatException('صاحب المحل لم يمنحك صلاحية هذه العملية.'); }
  }
  Future<void> authenticateOwner(String password) async {
    if (_retryAfter != null && DateTime.now().isBefore(_retryAfter!)) {
      throw const FormatException('انتظر دقيقة قبل إعادة محاولة كلمة السر.');
    }
    var valid = false;
    if (cloud) {
      _requireOwner();
      final user = FirebaseAuth.instance.currentUser;
      if (user?.email != null) {
        try { await user!.reauthenticateWithCredential(EmailAuthProvider.credential(email: user.email!, password: password)); valid = true; }
        on FirebaseAuthException catch (_) { valid = false; }
      }
    } else { valid = await ownerLock.verify(password); }
    if (!valid) {
      if (++_passwordFailures >= 5) { _retryAfter = DateTime.now().add(const Duration(minutes: 1)); _passwordFailures = 0; }
      throw const FormatException('كلمة السر غير صحيحة.');
    }
    _passwordFailures = 0; _retryAfter = null;
    _adminUntil = DateTime.now().add(const Duration(minutes: 5));
  }
  void _requireAdmin() {
    _requireOwner();
    if (_adminUntil == null || !DateTime.now().isBefore(_adminUntil!)) {
      throw const FormatException('أعد فتح إعدادات الصلاحيات بكلمة سر المدير.');
    }
  }
  Future<void> setOwnerPassword(String password) async {
    _requireOwner();
    if (cloud) { throw const FormatException('كلمة مرور المدير السحابي هي كلمة مرور حسابه.'); }
    if (ownerLock.configured) { _requireAdmin(); }
    await ownerLock.set(password); _adminUntil = DateTime.now().add(const Duration(minutes: 5)); notifyListeners();
  }
  Future<void> changeOwnerPassword(String current, String next, String confirmation) async {
    _requireOwner();
    if (next != confirmation) { throw const FormatException('كلمة السر الجديدة وتأكيدها غير متطابقين.'); }
    if (next.trim().length < 6) { throw const FormatException('كلمة السر الجديدة تحتاج 6 أحرف أو أرقام على الأقل.'); }
    await authenticateOwner(current);
    await setOwnerPassword(next);
  }
  void lockWorker() {
    if (cloud) { return; }
    owner = false; actor = 'العامل'; _adminUntil = null; notifyListeners();
  }
  Future<void> unlockOwner(String password) async {
    if (cloud) { throw const FormatException('سجل الدخول بحساب صاحب المحل.'); }
    await authenticateOwner(password); owner = true; actor = 'صاحب المحل'; notifyListeners();
  }
  Future<List<Json>> workers() async {
    _requireAdmin();
    if (!cloud) { return [{'id': 'local', 'name': 'العامل على هذا الجهاز', 'permissions': workerAccess.toJson()}]; }
    final docs = await root.collection('members').where('role', isEqualTo: 'worker').get();
    return docs.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }
  Future<void> setWorkerAccess(String workerId, WorkerAccess access) async {
    _requireAdmin();
    if (cloud) { await root.collection('members').doc(workerId).update({'permissions': access.toJson()}); }
    else {
      if (!await prefs.setString('raff.worker.access.v1', jsonEncode(access.toJson()))) { throw const FormatException('تعذر حفظ الصلاحيات.'); }
      workerAccess = access; notifyListeners();
    }
  }
  String? uid;
  DocumentReference<Json> get root => FirebaseFirestore.instance.collection('stores').doc(storeId);
  bool get usable => !cloud || uid != null;
  String get syncLabel => !cloud ? 'تجربة محلية • لا توجد مزامنة' :
    pending ? 'تعديلات بانتظار المزامنة' : fromCache ? 'بيانات محفوظة • الاتصال غير مؤكد' : 'متصل • تمت المزامنة';

  Future<void> initialize() async {
    if (cloud) { owner = false; return; }
    final saved = prefs.getString(_key);
    if (saved != null) { _load(Json.from(jsonDecode(saved))); }
    else {
      settings = const StoreSettings(rate: 10000, margin: 20);
      products = [
        Product(id: _uuid.v4(), name: 'حليب كامل الدسم', category: 'ألبان', barcode: '6281000000011',
          pack: 12, quantity: 24, costUsd: 0.75, saleBaseUsd: 0.9, ready: true),
        Product(id: _uuid.v4(), name: 'أرز — 1 كغ', category: 'مواد غذائية', barcode: '6281000000028',
          pack: 10, quantity: 40, costUsd: 1.2, saleBaseUsd: 1.44, ready: true),
        Product(id: _uuid.v4(), name: 'مياه — 1.5 لتر', category: 'مشروبات', barcode: '6281000000035',
          pack: 6, quantity: 60, costUsd: 0.25, saleBaseUsd: 0.3, ready: true),
      ];
      await _persist();
    }
    workerAccess = WorkerAccess.fromJson(Json.from(jsonDecode(prefs.getString('raff.worker.access.v1') ?? '{}')));
    if (ownerLock.configured) { owner = false; actor = 'العامل'; }
    loaded = true;
    notifyListeners();
  }

  Future<void> connect(User user) async {
    await disconnect();
    final member = await root.collection('members').doc(user.uid).get(const GetOptions(source: Source.server));
    final data = member.data();
    if (data == null || data['active'] != true || !['owner', 'worker'].contains(data['role'])) {
      throw const FormatException('الحساب غير مضاف للمحل. اطلب من صاحب المحل تفعيل حسابك.');
    }
    uid = user.uid;
    owner = data['role'] == 'owner';
    workerAccess = WorkerAccess.fromJson(Json.from(data['permissions'] ?? {}));
    if (owner) { await _migrateLegacyMargins(); }
    actor = data['name'] as String? ?? user.email ?? 'مستخدم';
    error = '';
    _watch(root.collection('members').doc(user.uid).snapshots(), (snap) {
      final m = snap.data();
      if (m == null || m['active'] != true || (m['role'] == 'owner') != owner) {
        _pricing.clear(); _margins.clear(); _stockCosts = null; history = []; _rebuild(); _rebuildStock();
        unawaited(FirebaseAuth.instance.signOut());
      } else if (!owner && jsonEncode(workerAccess.toJson()) != jsonEncode(WorkerAccess.fromJson(Json.from(m['permissions'] ?? {})).toJson())) {
        // Clear sensitive state immediately, then resubscribe with the new access.
        workerAccess = WorkerAccess.fromJson(Json.from(m['permissions'] ?? {}));
        _pricing.clear(); _margins.clear(); _stockCosts = null; history = []; stocktake = null; _rebuild(); loaded = false;
        unawaited(connect(user).catchError((Object e) { error = 'تعذر تحديث الصلاحيات. أعد تسجيل الدخول.'; notifyListeners(); }));
      }
    });
    _watch(root.collection('settings').doc('current').snapshots(includeMetadataChanges: true), (snap) {
      settings = StoreSettings.fromJson(snap.data() ?? {});
      _settingsReady = snap.exists;
      if (!snap.exists) { error = 'إعدادات المحل غير موجودة. أكمل إعداد Firebase حسب ملف README.'; }
      _metadata('settings', snap.metadata); _setLoaded();
    });
    _watch(root.collection('products').snapshots(includeMetadataChanges: true), (snap) {
      _public.clear();
      for (final doc in snap.docs) { _public[doc.id] = doc.data(); }
      _rebuild();
      _productsReady = true; _setLoaded();
      _metadata('products', snap.metadata);
    });
    if (can('viewCost')) {
      _watch(root.collection('costs').snapshots(includeMetadataChanges: true), (snap) {
        if (!can('viewCost')) { return; }
        _pricing.clear();
        for (final doc in snap.docs) { _pricing[doc.id] = doc.data(); }
        _rebuild();
        _pricingReady = true; _setLoaded();
        _metadata('pricing', snap.metadata);
      });
    }
    if (can('viewMargin')) {
      _watch(root.collection('margins').snapshots(includeMetadataChanges: true), (snap) {
        if (!can('viewMargin')) { return; }
        _margins.clear();
        for (final doc in snap.docs) { _margins[doc.id] = doc.data(); }
        _rebuild(); _marginsReady = true; _setLoaded(); _metadata('margins', snap.metadata);
      });
    }
    if (can('viewHistory')) {
      _watch(root.collection('priceChanges').orderBy('at', descending: true).limit(100).snapshots(), (snap) {
        if (!can('viewHistory')) { return; }
        history = snap.docs.map((d) => PriceChange.fromJson(d.data())).toList();
      });
    }
    if (can('viewStocktake')) {
    _watch(root.collection('stocktakes').doc('active').snapshots(), (snap) {
      if (!can('viewStocktake')) { return; }
      _stockMeta = snap.data(); _rebuildStock();
    });
    _watch(root.collection('stockCounts').snapshots(includeMetadataChanges: true), (snap) {
      if (!can('viewStocktake')) { return; }
      _stockCounts.clear();
      for (final doc in snap.docs) { _stockCounts[doc.id] = doc.data(); }
      _rebuildStock(); _metadata('counts', snap.metadata);
    });
    if (can('viewCost')) {
      _watch(root.collection('stocktakeCosts').doc('active').snapshots(), (snap) {
        if (!can('viewCost') || !can('viewStocktake')) { return; }
        _stockCosts = snap.data(); _rebuildStock();
      });
    }
    }
    notifyListeners();
  }

  Future<void> _migrateLegacyMargins() async {
    // Legacy bundled documents stay owner-only. New collections separate the
    // two read permissions without exposing hidden fields to the client.
    final docs = await root.collection('pricing').get(const GetOptions(source: Source.server));
    for (final doc in docs.docs) {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final current = await tx.get(doc.reference);
        final marginRef = root.collection('margins').doc(doc.id);
        final costRef = root.collection('costs').doc(doc.id);
        final marginDoc = await tx.get(marginRef);
        final costDoc = await tx.get(costRef);
        final values = current.data();
        if (values == null) { return; }
        if (!marginDoc.exists) { tx.set(marginRef, {'margin': values['margin']}); }
        if (!costDoc.exists) { tx.set(costRef, {'costUsd': values['costUsd'], 'costLocal': values['costLocal']}); }
        tx.delete(doc.reference);
      });
    }
  }

  void _watch<T>(Stream<T> stream, void Function(T) apply) {
    _subscriptions.add(stream.listen((event) {
      apply(event);
      notifyListeners();
    }, onError: (Object e) {
      error = 'تعذر مزامنة البيانات. تحقق من الإنترنت والصلاحيات.';
      notifyListeners();
    }));
  }
  void _metadata(String source, SnapshotMetadata m) {
    _metadataSources[source] = m;
    fromCache = _metadataSources.values.any((m) => m.isFromCache);
    pending = _metadataSources.values.any((m) => m.hasPendingWrites);
  }
  void _setLoaded() { loaded = _productsReady && _settingsReady && (!can('viewCost') || _pricingReady) && (!can('viewMargin') || _marginsReady); }
  void _rebuildStock() {
    final j = _stockMeta;
    if (j == null) { stocktake = null; return; }
    stocktake = Stocktake.fromJson({...j,
      'counts': {for (final e in _stockCounts.entries) if (e.value['sessionId'] == j['id']) e.key: e.value['count']},
      'snapshot': _stockCosts?['sessionId'] == j['id'] ? _stockCosts!['snapshot'] : {},
    });
    final revisions = _stockCounts.values.where((c) => c['sessionId'] == j['id']).map((c) => number(c['countRevision']).toInt());
    final latest = revisions.fold<int>(0, (a, b) => a > b ? a : b);
    _stockReady = latest == stocktake!.countRevision &&
      (!can('viewCost') || _stockCosts?['sessionId'] == j['id']);
  }
  void _rebuild() {
    products = _public.entries.map((e) => Product.fromJson(e.key, e.value, {...?_pricing[e.key], ...?_margins[e.key]})).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }
  Future<void> disconnect() async {
    for (final s in _subscriptions) { await s.cancel(); }
    _subscriptions.clear();
    if (cloud) {
      _adminUntil = null; products = []; history = []; _public.clear(); _pricing.clear(); _margins.clear();
      stocktake = null; owner = false; loaded = false; uid = null;
      settings = const StoreSettings();
      _stockMeta = null; _stockCosts = null; _stockCounts.clear(); _metadataSources.clear();
      _stockReady = false;
      _productsReady = false; _pricingReady = false; _marginsReady = false; _settingsReady = false;
      fromCache = false; pending = false; error = '';
    }
  }
  void _requireOwner() {
    if (!owner || !usable) { throw const FormatException('هذه العملية متاحة لصاحب المحل فقط.'); }
  }
  Product? findBarcode(String code) {
    for (final p in products) { if (p.barcode == code.trim()) { return p; } }
    return null;
  }
  Product? findId(String id) {
    for (final p in products) { if (p.id == id) { return p; } }
    return null;
  }
  String newId() => _uuid.v4();
  DocumentReference<Json> _barcode(String code) => root.collection('barcodes').doc(base64Url.encode(utf8.encode(code)));
  PriceChange _change(String name, String kind, double before, double after) =>
    PriceChange(name: name, actor: actor, kind: kind,
      at: DateTime.now().toUtc().toIso8601String(), before: before, after: after);

  Future<void> saveProduct(Product product, {int? expectedRevision}) =>
    _saveProduct(product, expectedRevision: expectedRevision);
  Future<void> _saveProduct(Product product, {int? expectedRevision, bool deferLocalPersist = false}) async {
    product.validate();
    final baseSettings = settings;
    final old = findId(product.id);
    _require(old == null ? can('addProduct') : canEditProduct);
    if (!owner) {
      final base = old ?? Product(id: product.id, name: product.name);
      if (old != null && !can('editDetails') && (product.name != base.name || product.category != base.category || product.barcode != base.barcode || product.pack != base.pack)) { _require(false); }
      if (!can('editQuantity') && product.quantity != base.quantity) { _require(false); }
      if (!can('editSalePrice') && product.manualPrice != base.manualPrice) { _require(false); }
      if (!can('editSalePrice') && !can('editCost') && !can('editMargin') && product.ready != base.ready) { _require(false); }
      if (product.bargainPercent != base.bargainPercent) { _require(false); }
      if (!can('editCost') && (jsonEncode(product.costJson()) != jsonEncode(base.costJson()) || product.costCurrency != base.costCurrency)) { _require(false); }
      if (!can('editMargin') && product.margin != base.margin) { _require(false); }
      if (!can('editCost') && !can('editMargin') && (product.saleBaseUsd != base.saleBaseUsd || product.saleBaseLocal != base.saleBaseLocal)) { _require(false); }
      if (can('editCost') && !can('viewMargin') && old != null && old.hasCost &&
          (old.costCurrency == 'SYP' ? old.costLocal : old.costUsd) == 0 && old.manualPrice == null &&
          jsonEncode(product.costJson()) != jsonEncode(old.costJson())) {
        throw const FormatException('تعديل رأس مال كان صفراً يحتاج مراجعة المدير لنسبة الربح.');
      }
    }
    if (old != null && expectedRevision != null && old.revision != expectedRevision) {
      throw const FormatException('تعدلت المادة. افتحها مجدداً قبل الحفظ.');
    }
    final duplicate = findBarcode(product.barcode);
    if (product.barcode.isNotEmpty && duplicate != null && duplicate.id != product.id) {
      throw const FormatException('هذا الباركود مستخدم لمادة أخرى.');
    }
    final change = _change(product.name, old == null ? 'إضافة مادة' : 'تعديل مادة',
      old?.price(baseSettings) ?? 0, product.price(baseSettings));
    if (cloud) {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final ref = root.collection('products').doc(product.id);
        final current = await tx.get(ref);
        if (current.exists && current.data()?['revision'] != (expectedRevision ?? old?.revision)) {
          throw const FormatException('تعدلت المادة على جهاز آخر. افتحها مجدداً قبل الحفظ.');
        }
        final previousBarcode = current.data()?['barcode'] as String? ?? '';
        if (product.barcode.isNotEmpty && previousBarcode != product.barcode) {
          final code = await tx.get(_barcode(product.barcode));
          if (code.exists && code.data()?['productId'] != product.id) {
            throw const FormatException('هذا الباركود مستخدم لمادة أخرى.');
          }
        }
        final settingsDoc = await tx.get(root.collection('settings').doc('current'));
        if (settingsDoc.exists && settingsDoc.data()?['revision'] != baseSettings.revision) {
          throw const FormatException('تغيرت إعدادات الأسعار. حاول مجدداً.');
        }
        if (previousBarcode.isNotEmpty && previousBarcode != product.barcode) { tx.delete(_barcode(previousBarcode)); }
        if (product.barcode.isNotEmpty && previousBarcode != product.barcode) { tx.set(_barcode(product.barcode), {'productId': product.id}); }
        tx.set(ref, {...product.toJson(), 'updatedBy': uid, 'updatedAt': FieldValue.serverTimestamp()});
        if (can('editCost')) { tx.set(root.collection('costs').doc(product.id), product.costJson()); }
        if (can('editMargin')) { tx.set(root.collection('margins').doc(product.id), product.marginJson()); }
        tx.set(root.collection('priceChanges').doc(), {...change.toJson(), 'uid': uid});
      });
      _public[product.id] = product.toJson(); _pricing[product.id] = product.costJson(); _margins[product.id] = product.marginJson();
      _rebuild(); notifyListeners();
    } else {
      products = [...products.where((p) => p.id != product.id), product];
      history.insert(0, change);
      if (!deferLocalPersist) { await _persist(); notifyListeners(); }
    }
  }

  void applyBargain(CartLine line, double percent) {
    _require(can('useCalculator') && can('applyBargain'));
    final product = findId(line.id);
    if (product == null || !product.ready) { throw const FormatException('المادة غير موجودة أو غير مسعرة.'); }
    line.setDiscount(percent, product.bargainPercent);
  }
  void applyBargainPrice(CartLine line, double price) {
    _require(can('useCalculator') && can('applyBargain'));
    final product = findId(line.id);
    if (product == null || !product.ready) { throw const FormatException('المادة غير موجودة أو غير مسعرة.'); }
    line.setSellingPrice(price, product.bargainPercent);
  }
  double basketTotal(List<CartLine> lines) => lines.fold<double>(0, (amount, line) {
    final product = findId(line.id);
    final allowed = can('applyBargain') && can('useCalculator') && product != null && product.ready ? product.bargainPercent : 0.0;
    if (!line.discountPercent.isFinite || line.discountPercent < 0) { line.discountPercent = 0; }
    if (line.discountPercent > allowed) { line.discountPercent = allowed; }
    return amount + line.total;
  });

  Future<void> deleteProduct(Product product) async {
    _require(can('deleteProduct'));
    final current = findId(product.id);
    if (current == null || current.revision != product.revision) { throw const FormatException('تغيرت المادة؛ أعد فتحها قبل الحذف.'); }
    if (stocktake != null && !stocktake!.closed && stocktake!.productIds.contains(product.id)) {
      throw const FormatException('اعتمد الجرد المفتوح قبل حذف هذه المادة.');
    }
    final change = _change(product.name, 'حذف مادة', product.price(settings), 0);
    if (cloud) {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final ref = root.collection('products').doc(product.id);
        final doc = await tx.get(ref);
        final active = await tx.get(root.collection('stocktakes').doc('active'));
        if (doc.data()?['revision'] != product.revision) { throw const FormatException('تغيرت المادة على جهاز آخر.'); }
        if (active.data()?['closed'] == false && (active.data()?['productIds'] as List? ?? []).contains(product.id)) { throw const FormatException('المادة ضمن جرد مفتوح.'); }
        tx.delete(ref); tx.delete(root.collection('costs').doc(product.id)); tx.delete(root.collection('margins').doc(product.id));
        if (product.barcode.isNotEmpty) { tx.delete(_barcode(product.barcode)); }
        tx.set(root.collection('priceChanges').doc(), {...change.toJson(), 'uid': uid});
      });
      _public.remove(product.id); _pricing.remove(product.id); _margins.remove(product.id); _rebuild();
    } else { products.removeWhere((p) => p.id == product.id); history.insert(0, change); await _persist(); }
    notifyListeners();
  }

  Future<ImportResult> importProducts(List<Product> rows, {required int settingsRevision,
    void Function(int processed, int total)? onProgress}) async {
    _requireOwner();
    var added = 0, updated = 0;
    final errors = <String>[];
    onProgress?.call(0, rows.length);
    // Chunk size is a save checkpoint, never a limit on the number of products.
    final chunkSize = cloud ? 1 : 50;
    for (var start = 0; start < rows.length; start += chunkSize) {
      final end = start + chunkSize < rows.length ? start + chunkSize : rows.length;
      if (!owner || !usable || settings.revision != settingsRevision) {
        return ImportResult(added: added, updated: updated, errors: errors,
          unprocessed: rows.length - start,
          stoppedReason: !owner || !usable ? 'توقفت العملية بسبب تغير صلاحية المدير.' : 'تغيرت إعدادات الأسعار؛ أعد معاينة الأصناف المتبقية.');
      }
      final previousProducts = products;
      final previousHistory = List<PriceChange>.of(history);
      final accepted = <Product>[];
      var chunkAdded = 0, chunkUpdated = 0;
      for (var index = start; index < end; index++) {
        final p = rows[index];
        final existed = findId(p.id) != null;
        try {
          await _saveProduct(p, expectedRevision: p.revision - 1, deferLocalPersist: !cloud);
          accepted.add(p);
          if (existed) { chunkUpdated++; } else { chunkAdded++; }
        } on FormatException catch (e) {
          errors.add('${p.name}: ${e.message}');
        } catch (_) {
          errors.add('${p.name}: تعذر الحفظ؛ تحقق من الاتصال ومساحة التخزين والصلاحيات.');
          if (!cloud) {
            products = previousProducts; history = previousHistory;
            for (final row in accepted) { errors.add('${row.name}: لم يتم حفظ دفعة هذه المادة على الجهاز.'); }
            notifyListeners();
          }
          return ImportResult(added: added, updated: updated, errors: errors,
            unprocessed: rows.length - index - 1, stoppedReason: 'توقفت العملية؛ الأصناف المحفوظة سابقاً باقية.');
        }
      }
      if (!cloud && accepted.isNotEmpty) {
        try { await _persist(); }
        catch (_) {
          products = previousProducts; history = previousHistory;
          for (final p in accepted) { errors.add('${p.name}: لم يتم حفظ دفعة هذه المادة على الجهاز.'); }
          notifyListeners();
          return ImportResult(added: added, updated: updated, errors: errors,
            unprocessed: rows.length - end, stoppedReason: 'تعذر الحفظ على الجهاز؛ تحقق من مساحة التخزين ثم أعد المحاولة.');
        }
        notifyListeners();
      }
      added += chunkAdded; updated += chunkUpdated;
      onProgress?.call(end, rows.length);
      // Give the phone time to paint progress and handle input between checkpoints.
      await Future<void>.delayed(Duration.zero);
    }
    return ImportResult(added: added, updated: updated, errors: errors);
  }

  Future<void> changeSettings(double rate, double margin, String currency) async {
    _require(can('editExchangeRate'));
    if (!owner && (margin != settings.margin || currency != settings.currency)) { _require(false); }
    final previous = settings;
    if (!rate.isFinite || rate <= 0 || !margin.isFinite || margin < 0 || currency.trim().isEmpty) {
      throw const FormatException('أدخل سعر صرف موجباً وربحاً غير سالب واسم العملة.');
    }
    // General-margin changes reprice only automatic products following the general margin.
    final changed = products.where((p) => p.margin == null && p.hasCost && p.manualPrice == null)
      .map((p) => p.edit(useGeneralMargin: true, settings: StoreSettings(rate: rate, margin: margin))).toList();
    if (margin != previous.margin && changed.length > 140) { throw const FormatException('تعديل النسبة العامة يدعم حتى 140 مادة حالياً. عدّل على دفعات.'); }
    final next = StoreSettings(rate: rate, margin: margin, currency: currency.trim(), revision: previous.revision + 1);
    final rateChange = _change('سعر الصرف', 'تغيير الصرف', previous.rate, rate);
    final marginChange = _change('نسبة الربح العامة', 'تغيير الربح', previous.margin, margin);
    if (cloud) {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final ref = root.collection('settings').doc('current');
        final current = await tx.get(ref);
        if (current.exists && current.data()?['revision'] != previous.revision) {
          throw const FormatException('تغيرت الإعدادات على جهاز آخر. حاول مجدداً.');
        }
        final docs = <DocumentSnapshot<Json>>[];
        if (margin != previous.margin) {
          for (final p in changed) { docs.add(await tx.get(root.collection('products').doc(p.id))); }
          for (var i = 0; i < docs.length; i++) {
            if (docs[i].data()?['revision'] != changed[i].revision - 1) {
              throw const FormatException('تغيرت مادة أثناء التعديل. حاول مجدداً.');
            }
          }
        }
        tx.set(ref, next.toJson());
        tx.set(root.collection('priceChanges').doc(), {...rateChange.toJson(), 'uid': uid});
        if (margin != previous.margin) {
          tx.set(root.collection('priceChanges').doc(), {...marginChange.toJson(), 'uid': uid});
          for (final p in changed) { tx.update(root.collection('products').doc(p.id), p.toJson()); }
        }
      });
      settings = next;
      if (margin != previous.margin) { for (final p in changed) { _public[p.id] = p.toJson(); } _rebuild(); }
      notifyListeners();
    } else {
      if (margin != previous.margin) {
        final map = {for (final p in changed) p.id: p};
        products = products.map((p) => map[p.id] ?? p).toList();
        history.insert(0, marginChange);
      }
      history.insert(0, rateChange); settings = next;
      await _persist(); notifyListeners();
    }
  }

  Future<void> bulkMargin(List<Product> selected, double increase) async {
    _requireOwner();
    if (selected.isEmpty || selected.length > 100 || !increase.isFinite || increase < 0) {
      throw const FormatException('اختر من 1 إلى 100 مادة ونسبة غير سالبة.');
    }
    // Each edit is revision-checked and audited. Report completed count on failure.
    var completed = 0;
    try {
      for (final p in selected) {
        await saveProduct(p.edit(margin: p.effectiveMargin(settings) + increase, settings: settings), expectedRevision: p.revision);
        completed++;
      }
    } catch (_) {
      throw FormatException('تم تعديل $completed من ${selected.length}. توقف التعديل؛ راجع السجل قبل إعادة المحاولة.');
    }
  }

  Future<void> startStocktake() async {
    _requireOwner();
    if (cloud && fromCache) { throw const FormatException('انتظر اكتمال المزامنة قبل تثبيت تكلفة الجرد.'); }
    if (stocktake != null && !stocktake!.closed) { throw const FormatException('اعتمد الجرد الحالي قبل بدء جرد جديد.'); }
    final s = Stocktake(id: newId(), at: DateTime.now().toUtc().toIso8601String(),
      rate: settings.rate, currency: settings.currency,
      productIds: products.map((p) => p.id).toList(),
      snapshot: {for (final p in products) p.id: {'name': p.name, 'barcode': p.barcode,
        'quantity': p.quantity, 'costUsd': p.costUsd, 'costLocal': p.costLocal, 'costCurrency': p.costCurrency, 'pack': p.pack}});
    if (products.length > 400) { throw const FormatException('الجرد الحالي يدعم حتى 400 مادة. يلزم تقسيم الجرد للمخزون الأكبر.'); }
    if (cloud) {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final ref = root.collection('stocktakes').doc('active');
        final active = await tx.get(ref);
        if (active.exists && active.data()?['closed'] != true) { throw const FormatException('يوجد جرد مفتوح على جهاز آخر.'); }
        tx.set(ref, {'id': s.id, 'at': s.at, 'rate': s.rate, 'currency': s.currency, 'closed': false, 'countRevision': 0, 'productIds': s.productIds});
        tx.set(root.collection('stocktakeCosts').doc('active'), {'sessionId': s.id, 'snapshot': s.snapshot});
      });
    } else { stocktake = s; await _persist(); notifyListeners(); }
  }
  Future<void> countProduct(String id, double count) async {
    _require(can('countStock') && can('viewStocktake'));
    final s = stocktake;
    if (!usable || s == null || s.closed || count < 0 || !count.isFinite ||
        findId(id) == null || !s.productIds.contains(id)) {
      throw const FormatException('تحقق من العدد ومن وجود جلسة جرد مفتوحة.');
    }
    if (cloud) {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final activeRef = root.collection('stocktakes').doc('active');
        final active = await tx.get(activeRef);
        if (active.data()?['id'] != s.id || active.data()?['closed'] != false) {
          throw const FormatException('الجرد مغلق أو تغيرت جلسته. أعد فتح الشاشة.');
        }
        tx.set(root.collection('stockCounts').doc(id), {'sessionId': s.id,
          'count': count, 'updatedBy': uid, 'at': FieldValue.serverTimestamp(),
          'countRevision': number(active.data()?['countRevision']).toInt() + 1});
        // Any new count makes an in-flight approval retry, including a new product row.
        tx.update(activeRef, {'countRevision': number(active.data()?['countRevision']).toInt() + 1});
      });
    } else {
      stocktake = Stocktake.fromJson({...s.toJson(), 'counts': {...s.counts, id: count}, 'countRevision': s.countRevision + 1});
      await _persist(); notifyListeners();
    }
  }
  Future<void> approveStocktake() async {
    _requireOwner(); final s = stocktake;
    if (s == null || s.closed || s.counts.isEmpty) { throw const FormatException('لا يوجد جرد لاعتماده.'); }
    if (s.counts.length > 400) { throw const FormatException('اعتماد الجرد يدعم حتى 400 مادة حالياً.'); }
    if (cloud) {
      if (!_stockReady || fromCache) { throw const FormatException('انتظر وصول آخر أعداد الجرد وتكاليفه قبل الاعتماد.'); }
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final activeRef = root.collection('stocktakes').doc('active');
        final active = await tx.get(activeRef);
        if (active.data()?['id'] != s.id || active.data()?['closed'] != false ||
            active.data()?['countRevision'] != s.countRevision) {
          throw const FormatException('تغيرت جلسة الجرد. أعد فتح الشاشة.');
        }
        final rows = <String, DocumentSnapshot<Json>>{};
        final currentCounts = <String, DocumentSnapshot<Json>>{};
        for (final id in s.counts.keys) {
          rows[id] = await tx.get(root.collection('products').doc(id));
          currentCounts[id] = await tx.get(root.collection('stockCounts').doc(id));
        }
        for (final id in rows.keys) {
          final c = currentCounts[id]!.data();
          if (c?['sessionId'] != s.id || number(c?['count']) != s.counts[id]) {
            throw const FormatException('تغير عدد أثناء اعتماد الجرد. راجع الأعداد مجدداً.');
          }
          if (rows[id]!.exists) { tx.update(rows[id]!.reference, {
            'quantity': s.counts[id], 'revision': number(rows[id]!.data()?['revision']).toInt() + 1,
            'updatedBy': uid, 'updatedAt': FieldValue.serverTimestamp()}); }
        }
        tx.update(activeRef, {'closed': true});
        tx.set(root.collection('stocktakeArchive').doc(s.id), s.toJson());
      });
    } else {
      products = products.map((p) => s.counts.containsKey(p.id) ?
        p.edit(quantity: s.counts[p.id], settings: settings) : p).toList();
      stocktake = Stocktake.fromJson({...s.toJson(), 'closed': true});
      await _persist(); notifyListeners();
    }
  }

  Json backup() {
    _requireOwner();
    return {'schema': 1, 'createdAt': DateTime.now().toUtc().toIso8601String(),
      'settings': settings.toJson(), 'products': [for (final p in products)
        {'id': p.id, ...p.toJson(), 'pricing': p.pricingJson()}],
      'history': history.map((c) => c.toJson()).toList(), 'stocktake': stocktake?.toJson()};
  }
  Future<void> restore(Json data) async {
    _requireOwner();
    // Cloud restore uses the regular revision-checked product path; never restores memberships.
    if (data['schema'] != 1 || data['products'] is! List || data['settings'] is! Map) {
      throw const FormatException('ملف النسخة الاحتياطية غير صالح.');
    }
    final nextSettings = StoreSettings.fromJson(Json.from(data['settings']));
    Stocktake? restoredStock;
    if (data['stocktake'] != null) {
      restoredStock = Stocktake.fromJson(Json.from(data['stocktake']));
      if (restoredStock.rate <= 0 || restoredStock.counts.values.any((c) => c < 0)) {
        throw const FormatException('أعداد الجرد أو سعر الصرف في النسخة غير صالحة.');
      }
    }
    final restored = (data['products'] as List).map((j) => Product.fromJson(j['id'], Json.from(j), Json.from(j['pricing'] ?? {}))).toList();
    final ids = <String>{}, codes = <String>{};
    for (final p in restored) {
      p.validate();
      if (!ids.add(p.id) || (p.barcode.isNotEmpty && !codes.add(p.barcode))) {
        throw const FormatException('النسخة تحتوي مواد أو باركودات مكررة.');
      }
    }
    if (nextSettings.rate <= 0 || nextSettings.margin < 0) { throw const FormatException('إعدادات النسخة غير صالحة.'); }
    if (cloud) {
      var completed = 0;
      try {
        await changeSettings(nextSettings.rate, nextSettings.margin, nextSettings.currency);
        for (final p in restored) {
          final old = findId(p.id);
          await saveProduct(Product.fromJson(p.id, {...p.toJson(), 'revision': (old?.revision ?? 0) + 1}, p.pricingJson()), expectedRevision: old?.revision);
          completed++;
        }
      } catch (_) { throw FormatException('تمت استعادة $completed مادة. توقف الاسترجاع؛ راجع البيانات قبل المحاولة مجدداً.'); }
    } else {
      _load(data); await _persist(); notifyListeners();
    }
  }
  void _load(Json j) {
    settings = StoreSettings.fromJson(Json.from(j['settings'] ?? {}));
    products = (j['products'] as List? ?? []).map((p) => Product.fromJson(p['id'], Json.from(p), Json.from(p['pricing'] ?? {}))).toList();
    history = (j['history'] as List? ?? []).map((c) => PriceChange.fromJson(Json.from(c))).toList();
    stocktake = j['stocktake'] == null ? null : Stocktake.fromJson(Json.from(j['stocktake']));
  }
  Future<void> _persist() async {
    final data = {'schema': 1, 'settings': settings.toJson(), 'products': [for (final p in products)
      {'id': p.id, ...p.toJson(), 'pricing': p.pricingJson()}],
      'history': history.take(500).map((c) => c.toJson()).toList(), 'stocktake': stocktake?.toJson()};
    if (!await prefs.setString(_key, jsonEncode(data))) { throw const FormatException('تعذر حفظ البيانات على الجهاز.'); }
  }
  @override
  void dispose() { for (final s in _subscriptions) { unawaited(s.cancel()); } super.dispose(); }
}

