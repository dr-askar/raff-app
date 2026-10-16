typedef Json = Map<String, dynamic>;

// Round the floor upward to the displayed currency precision so a displayed
// minimum can be entered without exceeding the owner's discount allowance.
double minimumSalePrice(double price, double percent) {
  if (percent == 0) { return price; }
  final cents = price * (1 - percent / 100) * 100;
  final nearest = cents.roundToDouble();
  final rounded = ((cents - nearest).abs() < 0.0000001 ? nearest : cents.ceilToDouble()) / 100;
  return rounded > price ? price : rounded;
}

double number(dynamic value, [double fallback = 0]) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed != null && parsed.isFinite ? parsed : fallback;
}

class StoreSettings {
  final double rate, margin;
  final String currency;
  final int revision;
  const StoreSettings({this.rate = 1, this.margin = 20,
    this.currency = 'ل.س', this.revision = 0});
  factory StoreSettings.fromJson(Json j) => StoreSettings(
    rate: number(j['rate'], 1), margin: number(j['margin'], 20),
    currency: j['currency'] as String? ?? 'ل.س',
    revision: (j['revision'] as num?)?.toInt() ?? 0);
  Json toJson() => {'rate': rate, 'margin': margin,
    'currency': currency, 'revision': revision};
}

class Product {
  final String id, name, category, barcode, unit;
  final int revision;
  final double pack;
  final double quantity, saleBaseUsd, bargainPercent;
  final double? saleBaseLocal;
  final String costCurrency;
  final double? costUsd, costLocal, margin, manualPrice;
  final bool ready;
  const Product({required this.id, required this.name, this.category = 'عام',
    this.barcode = '', this.unit = 'piece', this.pack = 1, this.quantity = 0,
    this.saleBaseUsd = 0, this.bargainPercent = 0, this.saleBaseLocal, this.costCurrency = 'USD',
    this.costUsd, this.costLocal, this.margin, this.manualPrice,
    this.ready = false, this.revision = 0});
  factory Product.fromJson(String id, Json j, [Json? pricing]) => Product(
    id: id, name: j['name'] as String? ?? '',
    category: j['category'] as String? ?? 'عام', barcode: j['barcode'] as String? ?? '',
    pack: number(j['pack'], 1), unit: j['unit'] as String? ?? 'piece',
    quantity: number(j['quantity']), bargainPercent: number(j['bargainPercent']), saleBaseUsd: number(j['saleBaseUsd']),
    saleBaseLocal: j['saleBaseLocal'] == null ? null : number(j['saleBaseLocal']),
    costCurrency: j['costCurrency'] as String? ?? 'USD',
    costLocal: pricing?['costLocal'] == null ? null : number(pricing?['costLocal']),
    costUsd: pricing?['costUsd'] == null ? null : number(pricing?['costUsd']),
    margin: pricing?['margin'] == null ? null : number(pricing?['margin']),
    manualPrice: j['manualPrice'] == null ? null : number(j['manualPrice']),
    ready: j['ready'] == true, revision: (j['revision'] as num?)?.toInt() ?? 0);
  Json toJson() => {'name': name, 'category': category, 'barcode': barcode,
    'pack': pack == pack.roundToDouble() ? pack.toInt() : pack, 'unit': unit, 'quantity': quantity, 'bargainPercent': bargainPercent, 'saleBaseUsd': saleBaseUsd,
    'saleBaseLocal': saleBaseLocal, 'costCurrency': costCurrency,
    'manualPrice': manualPrice, 'ready': ready, 'revision': revision};
  Json costJson() => {'costUsd': costUsd, 'costLocal': costLocal};
  Json marginJson() => {'margin': margin};
  Json pricingJson() => {'costUsd': costUsd, 'costLocal': costLocal, 'margin': margin};
  double price(StoreSettings settings) => manualPrice ?? (costCurrency == 'SYP' ? saleBaseLocal ?? 0 : saleBaseUsd * settings.rate);
  double minimumPrice(StoreSettings settings) => minimumSalePrice(price(settings), bargainPercent);
  bool get byWeight => unit == 'kg';
  String get unitLabel => byWeight ? 'كغ' : 'قطعة';
  double? get unitCost => costCurrency == 'SYP' ? costLocal : costUsd;
  double? get packCost => unitCost == null ? null : unitCost! * pack;
  bool get hasCost => costCurrency == 'SYP' ? costLocal != null : costUsd != null;
  double? localCost(double rate) => costCurrency == 'SYP' ? costLocal : (costUsd == null ? null : costUsd! * rate);
  double effectiveMargin(StoreSettings settings) => margin ?? settings.margin;
  Product edit({String? name, String? category, String? barcode, String? unit, double? pack,
    double? quantity, double? bargainPercent, double? costUsd, double? costLocal, String? costCurrency, double? margin, double? manualPrice,
    bool useGeneralMargin = false, bool automatic = false,
    required StoreSettings settings}) {
    final currency = costCurrency ?? this.costCurrency;
    final switched = currency != this.costCurrency;
    final usd = currency == 'USD' ? costUsd ?? (switched ? null : this.costUsd) : null;
    final local = currency == 'SYP' ? costLocal ?? (switched ? null : this.costLocal) : null;
    final cost = currency == 'SYP' ? local : usd;
    final reprice = switched || costUsd != null || costLocal != null || margin != null || useGeneralMargin;
    if (switched && cost == null) { throw const FormatException('أدخل التكلفة عند تغيير عملتها.'); }
    final profit = useGeneralMargin ? null : (margin ?? this.margin);
    final oldCost = this.costCurrency == 'SYP' ? this.costLocal : this.costUsd;
    final oldBasis = this.costCurrency == 'SYP' ? saleBaseLocal ?? 0 : saleBaseUsd;
    final oldFactor = 1 + effectiveMargin(settings) / 100;
    final explicitMargin = margin != null || useGeneralMargin;
    final factor = explicitMargin || this.margin != null ? 1 + (profit ?? settings.margin) / 100 :
      (oldCost != null && oldCost > 0 && ready ? oldBasis / oldCost : oldFactor);
    final manual = automatic ? null : (manualPrice ?? this.manualPrice);
    return Product(id: id, name: name ?? this.name,
      category: category ?? this.category, barcode: barcode ?? this.barcode,
      pack: pack ?? this.pack, unit: unit ?? this.unit, quantity: quantity ?? this.quantity, bargainPercent: bargainPercent ?? this.bargainPercent,
      costUsd: usd, costLocal: local, costCurrency: currency, margin: profit, manualPrice: manual,
      saleBaseUsd: currency == 'USD' ? (!reprice ? saleBaseUsd : usd != null ? usd * factor : explicitMargin ? saleBaseUsd * factor / oldFactor : saleBaseUsd) : 0,
      saleBaseLocal: currency == 'SYP' ? (!reprice ? saleBaseLocal : local != null ? local * factor : explicitMargin ? (saleBaseLocal ?? 0) * factor / oldFactor : saleBaseLocal) : null,
      ready: manual != null || cost != null || (!switched && ready &&
        !(automatic && this.manualPrice != null && saleBaseUsd == 0 && (saleBaseLocal ?? 0) == 0)), revision: revision + 1);
  }
  void validate() {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ||
        name.trim().isEmpty || name.length > 120 || category.length > 80 ||
        barcode.length > 80 || !bargainPercent.isFinite || bargainPercent < 0 || bargainPercent > 100 || !['piece', 'kg'].contains(unit) || !pack.isFinite || pack <= 0 ||
        (unit == 'piece' && (pack < 1 || pack != pack.roundToDouble())) || quantity < 0 || !quantity.isFinite ||
        (costUsd != null && (costUsd! < 0 || !costUsd!.isFinite)) ||
        (margin != null && (margin! < 0 || !margin!.isFinite)) ||
        (manualPrice != null && (manualPrice! < 0 || !manualPrice!.isFinite)) ||
        !['USD', 'SYP'].contains(costCurrency) ||
        (costCurrency == 'SYP' && costUsd != null) || (costCurrency == 'USD' && costLocal != null) ||
        (costLocal != null && (costLocal! < 0 || !costLocal!.isFinite)) ||
        (saleBaseLocal != null && (saleBaseLocal! < 0 || !saleBaseLocal!.isFinite)) ||
        saleBaseUsd < 0 || !saleBaseUsd.isFinite) {
      throw const FormatException('تأكد من الاسم والأرقام غير السالبة والتعبئة.');
    }
  }
}

class PriceChange {
  final String name, actor, kind, at;
  final double before, after;
  const PriceChange({required this.name, required this.actor,
    required this.kind, required this.at, required this.before, required this.after});
  factory PriceChange.fromJson(Json j) => PriceChange(name: j['name'] ?? '',
    actor: j['actor'] ?? '', kind: j['kind'] ?? '', at: j['at'] ?? '',
    before: number(j['before']), after: number(j['after']));
  Json toJson() => {'name': name, 'actor': actor, 'kind': kind, 'at': at,
    'before': before, 'after': after};
}

class CartLine {
  final String id, name;
  final double unitPrice;
  double quantity;
  final String unit;
  bool get byWeight => unit == 'kg';
  String get unitLabel => byWeight ? 'كغ' : 'قطعة';
  double _discountPercent = 0;
  double? _chosenPrice;
  double get discountPercent => _discountPercent;
  set discountPercent(double value) { _discountPercent = value; _chosenPrice = null; }
  CartLine({required this.id, required this.name, required this.unitPrice, this.quantity = 1, this.unit = 'piece'});
  void setQuantity(double value) {
    if (!value.isFinite || value <= 0 || (!byWeight && value != value.roundToDouble())) {
      throw const FormatException('أدخل وزناً موجباً أو عدداً صحيحاً موجباً للقطع.');
    }
    quantity = value;
  }
  double get sellingPrice => _chosenPrice ?? unitPrice * (1 - discountPercent / 100);
  double minimumPrice(double allowedMaximum) => minimumSalePrice(unitPrice, allowedMaximum);
  double get total => sellingPrice * quantity;
  void setDiscount(double percent, double allowedMaximum) {
    if (!allowedMaximum.isFinite || allowedMaximum < 0 || allowedMaximum > 100 ||
        !percent.isFinite || percent < 0 || percent > allowedMaximum || percent > 100) { throw const FormatException('نسبة المساومة تتجاوز الحد المسموح لهذه المادة.'); }
    discountPercent = percent;
    _chosenPrice = minimumPrice(percent);
  }
  void setSellingPrice(double price, double allowedMaximum) {
    if (!allowedMaximum.isFinite || allowedMaximum < 0 || allowedMaximum > 100 ||
        !price.isFinite || price < minimumPrice(allowedMaximum) || price > unitPrice) {
      throw const FormatException('اختر سعراً بين أقل سعر مسموح وسعر المبيع.');
    }
    final percent = unitPrice == 0 ? 0.0 : (unitPrice - price) * 100 / unitPrice;
    // Keep the exact entered amount; percentage is retained for permission/limit changes.
    discountPercent = percent > allowedMaximum ? allowedMaximum : percent;
    _chosenPrice = price;
  }
}

class Stocktake {
  final String id, at;
  final int countRevision;
  final List<String> productIds;
  final double rate;
  final String currency;
  final bool closed;
  final Map<String, double> counts;
  final Map<String, Json> snapshot;
  const Stocktake({required this.id, required this.at, required this.rate,
    required this.currency, this.closed = false, this.countRevision = 0, this.productIds = const [], this.counts = const {},
    this.snapshot = const {}});
  double get value => counts.entries.fold(0, (sum, e) => sum +
    e.value * snapshotCost(snapshot[e.key] ?? {}, rate));
  Json toJson() => {'id': id, 'at': at, 'rate': rate, 'currency': currency,
    'closed': closed, 'countRevision': countRevision, 'productIds': productIds, 'counts': counts, 'snapshot': snapshot};
  factory Stocktake.fromJson(Json j) => Stocktake(id: j['id'], at: j['at'],
    rate: number(j['rate'], 1), currency: j['currency'] ?? 'ل.س', closed: j['closed'] == true,
    countRevision: number(j['countRevision']).toInt(),
    productIds: List<String>.from(j['productIds'] ?? (j['snapshot'] as Map? ?? {}).keys),
    counts: Map<String, dynamic>.from(j['counts'] ?? {}).map((k, v) => MapEntry(k, number(v))),
    snapshot: Map<String, dynamic>.from(j['snapshot'] ?? {}).map((k, v) => MapEntry(k, Json.from(v))));
}

// Old snapshots have no currency field and remain dollar-based.
double snapshotCost(Json row, double rate) => row['costCurrency'] == 'SYP'
  ? number(row['costLocal']) : number(row['costUsd']) * rate;

