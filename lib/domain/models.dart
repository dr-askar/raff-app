typedef Json = Map<String, dynamic>;

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
  final String id, name, category, barcode;
  final int pack, revision;
  final double quantity, saleBaseUsd;
  final double? costUsd, margin, manualPrice;
  final bool ready;
  const Product({required this.id, required this.name, this.category = 'عام',
    this.barcode = '', this.pack = 1, this.quantity = 0,
    this.saleBaseUsd = 0, this.costUsd, this.margin, this.manualPrice,
    this.ready = false, this.revision = 0});
  factory Product.fromJson(String id, Json j, [Json? pricing]) => Product(
    id: id, name: j['name'] as String? ?? '',
    category: j['category'] as String? ?? 'عام', barcode: j['barcode'] as String? ?? '',
    pack: (j['pack'] as num?)?.toInt() ?? 1,
    quantity: number(j['quantity']), saleBaseUsd: number(j['saleBaseUsd']),
    costUsd: pricing?['costUsd'] == null ? null : number(pricing?['costUsd']),
    margin: pricing?['margin'] == null ? null : number(pricing?['margin']),
    manualPrice: j['manualPrice'] == null ? null : number(j['manualPrice']),
    ready: j['ready'] == true, revision: (j['revision'] as num?)?.toInt() ?? 0);
  Json toJson() => {'name': name, 'category': category, 'barcode': barcode,
    'pack': pack, 'quantity': quantity, 'saleBaseUsd': saleBaseUsd,
    'manualPrice': manualPrice, 'ready': ready, 'revision': revision};
  Json pricingJson() => {'costUsd': costUsd, 'margin': margin};
  double price(StoreSettings settings) => manualPrice ?? saleBaseUsd * settings.rate;
  double effectiveMargin(StoreSettings settings) => margin ?? settings.margin;
  Product edit({String? name, String? category, String? barcode, int? pack,
    double? quantity, double? costUsd, double? margin, double? manualPrice,
    bool useGeneralMargin = false, bool automatic = false,
    required StoreSettings settings}) {
    final cost = costUsd ?? this.costUsd;
    final profit = useGeneralMargin ? null : (margin ?? this.margin);
    final manual = automatic ? null : (manualPrice ?? this.manualPrice);
    return Product(id: id, name: name ?? this.name,
      category: category ?? this.category, barcode: barcode ?? this.barcode,
      pack: pack ?? this.pack, quantity: quantity ?? this.quantity,
      costUsd: cost, margin: profit, manualPrice: manual,
      saleBaseUsd: cost == null ? saleBaseUsd : cost * (1 + (profit ?? settings.margin) / 100),
      ready: manual != null || cost != null, revision: revision + 1);
  }
  void validate() {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ||
        name.trim().isEmpty || name.length > 120 || category.length > 80 ||
        barcode.length > 80 || pack < 1 || quantity < 0 || !quantity.isFinite ||
        (costUsd != null && (costUsd! < 0 || !costUsd!.isFinite)) ||
        (margin != null && (margin! < 0 || !margin!.isFinite)) ||
        (manualPrice != null && (manualPrice! < 0 || !manualPrice!.isFinite)) ||
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
  int quantity;
  CartLine({required this.id, required this.name, required this.unitPrice, this.quantity = 1});
  double get total => unitPrice * quantity;
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
    e.value * number(snapshot[e.key]?['costUsd']) * rate);
  Json toJson() => {'id': id, 'at': at, 'rate': rate, 'currency': currency,
    'closed': closed, 'countRevision': countRevision, 'productIds': productIds, 'counts': counts, 'snapshot': snapshot};
  factory Stocktake.fromJson(Json j) => Stocktake(id: j['id'], at: j['at'],
    rate: number(j['rate'], 1), currency: j['currency'] ?? 'ل.س', closed: j['closed'] == true,
    countRevision: number(j['countRevision']).toInt(),
    productIds: List<String>.from(j['productIds'] ?? (j['snapshot'] as Map? ?? {}).keys),
    counts: Map<String, dynamic>.from(j['counts'] ?? {}).map((k, v) => MapEntry(k, number(v))),
    snapshot: Map<String, dynamic>.from(j['snapshot'] ?? {}).map((k, v) => MapEntry(k, Json.from(v))));
}
