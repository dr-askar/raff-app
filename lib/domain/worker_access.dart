import 'models.dart';

class WorkerAccess {
  static const labels = <String, String>{
    'viewCost': 'رؤية تكلفة القطعة ونسبة الربح',
    'editExchangeRate': 'تغيير سعر صرف الدولار',
    'addProduct': 'إضافة صنف جديد',
    'deleteProduct': 'حذف صنف',
    'editDetails': 'تعديل الاسم والباركود والتعبئة والتصنيف',
    'editQuantity': 'تعديل الكمية المتوفرة',
    'editSalePrice': 'تعديل سعر البيع يدوياً',
    'editCost': 'تعديل التكلفة وعملتها ونسبة الربح',
    'useCalculator': 'استخدام حساب الزبون',
    'viewStocktake': 'رؤية الجرد',
    'countStock': 'إدخال العدد الفعلي أثناء الجرد',
    'viewHistory': 'رؤية سجل تغيرات الأسعار',
  };
  final Map<String, bool> _values;
  const WorkerAccess([this._values = const {}]);
  bool allows(String key) => _values[key] ?? const {
    'useCalculator': true, 'viewStocktake': true, 'countStock': true,
  }[key] ?? false;
  factory WorkerAccess.fromJson(Json data) => WorkerAccess({
    for (final key in labels.keys) if (data[key] is bool) key: data[key] as bool,
  });
  Json toJson() => {for (final key in labels.keys) key: allows(key)};
  WorkerAccess withValue(String key, bool value) {
    final next = {...toJson(), key: value};
    if (key == 'editCost' && value) { next['viewCost'] = true; }
    if (key == 'viewCost' && !value) { next['editCost'] = false; }
    if (key == 'countStock' && value) { next['viewStocktake'] = true; }
    if (key == 'viewStocktake' && !value) { next['countStock'] = false; }
    return WorkerAccess.fromJson(next);
  }
}
