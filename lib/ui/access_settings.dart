import 'package:flutter/material.dart';
import '../data/app_store.dart';
import '../domain/models.dart';
import '../domain/worker_access.dart';
import 'common.dart';

Future<String?> passwordDialog(BuildContext context, {bool create = false}) async {
  final first = TextEditingController(), second = TextEditingController();
  String? error;
  final result = await showDialog<String>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, change) =>
    AlertDialog(title: Text(create ? 'تعيين كلمة سر المدير' : 'كلمة سر المدير'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: first, obscureText: true, autofocus: true, decoration: InputDecoration(labelText: 'كلمة السر', errorText: error)),
      if (create) ...[const SizedBox(height: 12), TextField(controller: second, obscureText: true, decoration: const InputDecoration(labelText: 'تأكيد كلمة السر'))],
      if (create) const Padding(padding: EdgeInsets.only(top: 12), child: Text('6 أحرف أو أرقام على الأقل. احتفظ بها؛ لا يوجد استرجاع محلي لكلمة السر.')),
    ]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('رجوع')),
      FilledButton(onPressed: () {
        if (create && (first.text.trim().length < 6 || first.text != second.text)) { change(() => error = 'استخدم 6 أحرف على الأقل وتأكيداً مطابقاً'); return; }
        if (first.text.isNotEmpty) { Navigator.pop(ctx, first.text); }
      }, child: const Text('متابعة')),
    ])));
  Future<void>.delayed(const Duration(milliseconds: 300), () { first.dispose(); second.dispose(); });
  return result;
}

Future<void> openWorkerAccess(BuildContext context, AppStore store) async {
  final create = !store.hasOwnerPassword;
  final password = await passwordDialog(context, create: create);
  if (password == null || !context.mounted) { return; }
  try {
    if (create) { await store.setOwnerPassword(password); } else { await store.authenticateOwner(password); }
    if (context.mounted) { await Navigator.push(context, MaterialPageRoute(builder: (_) => AccessSettings(store: store))); }
  } catch (e) {
    if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is FormatException ? e.message : 'تعذر التحقق من حساب المدير.'))); }
  }
}

class AccessSettings extends StatefulWidget {
  final AppStore store;
  const AccessSettings({super.key, required this.store});
  @override
  State<AccessSettings> createState() => _AccessSettingsState();
}
class _AccessSettingsState extends State<AccessSettings> {
  List<Json>? members;
  String? selected;
  WorkerAccess access = const WorkerAccess();
  String? error;
  bool busy = false;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final rows = await widget.store.workers();
      if (!mounted) { return; }
      setState(() { members = rows; if (rows.isNotEmpty) { choose(rows.first); } });
    } catch (_) { if (mounted) { setState(() => error = 'تعذر تحميل العمال. أعد فتح الصفحة بكلمة سر المدير.'); } }
  }
  void choose(Json row) { selected = row['id']; access = WorkerAccess.fromJson(Json.from(row['permissions'] ?? {})); }
  Future<void> save() async {
    if (selected == null || busy) { return; }
    setState(() => busy = true);
    await perform(context, () async {
      await widget.store.setWorkerAccess(selected!, access);
      members!.firstWhere((m) => m['id'] == selected)['permissions'] = access.toJson();
    }, 'تم حفظ صلاحيات العامل');
    if (mounted) { setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('صلاحيات العامل'), actions: [
      if (!widget.store.cloud) TextButton.icon(onPressed: busy ? null : () => changePasswordDialog(context, widget.store), icon: const Icon(Icons.password), label: const Text('كلمة السر')),
    ]),
    bottomNavigationBar: members == null || members!.isEmpty ? null : SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: busy ? null : save, icon: const Icon(Icons.lock_outline), label: Text(busy ? 'جارٍ الحفظ…' : 'حفظ الصلاحيات')))),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 650), child:
      error != null ? Center(child: Text(error!)) : members == null ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(20), children: [
        const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('فعّل فقط ما يحتاجه العامل. رؤية رأس المال ورؤية نسبة الربح خياران مستقلان. تعديل كل منهما يحتاج السماح برؤيته فقط. نسبة المساومة لكل مادة يحددها المدير وحده. المدير وحده يغيّر هذه الصلاحيات.'))),
        if (members!.isEmpty) const Text('لا يوجد حساب عامل مضاف للمحل. أضفه في Firebase أولاً.'),
        if (members!.isNotEmpty) ...[
          DropdownButtonFormField<String>(initialValue: selected, decoration: const InputDecoration(labelText: 'العامل'),
            items: members!.map((m) => DropdownMenuItem<String>(value: m['id'], child: Text(m['name'] ?? m['id']))).toList(),
            onChanged: busy ? null : (id) => setState(() => choose(members!.firstWhere((m) => m['id'] == id)))),
          const SizedBox(height: 14),
          ...WorkerAccess.labels.entries.map((e) => Card(child: SwitchListTile(title: Text(e.value), value: access.allows(e.key),
            onChanged: busy ? null : (value) => setState(() => access = access.withValue(e.key, value))))),
        ],
      ]))));
}

Future<void> changePasswordDialog(BuildContext context, AppStore store) async {
  final current = TextEditingController(), next = TextEditingController(), confirmation = TextEditingController();
  String? error; var busy = false;
  await showDialog<void>(context: context, barrierDismissible: false, builder: (ctx) => StatefulBuilder(builder: (ctx, change) =>
    AlertDialog(title: const Text('تغيير كلمة سر المدير'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: current, obscureText: true, enabled: !busy, decoration: const InputDecoration(labelText: 'كلمة السر الحالية')),
      const SizedBox(height: 12), TextField(controller: next, obscureText: true, enabled: !busy, decoration: const InputDecoration(labelText: 'كلمة السر الجديدة')),
      const SizedBox(height: 12), TextField(controller: confirmation, obscureText: true, enabled: !busy, decoration: const InputDecoration(labelText: 'تأكيد كلمة السر الجديدة')),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
    ])), actions: [TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('رجوع')),
      FilledButton(onPressed: busy ? null : () async {
        if (next.text != confirmation.text || next.text.trim().length < 6) { change(() => error = 'تأكيد مطابق وكلمة سر من 6 أحرف أو أرقام على الأقل'); return; }
        change(() { busy = true; error = null; });
        try {
          await store.changeOwnerPassword(current.text, next.text, confirmation.text);
          if (ctx.mounted && context.mounted) { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تغيير كلمة سر المدير'))); }
        } catch (e) { if (ctx.mounted) { change(() { busy = false; error = e is FormatException ? e.message.toString() : 'تعذر تغيير كلمة السر.'; }); } }
      }, child: Text(busy ? 'جارٍ الحفظ…' : 'تغيير كلمة السر')),
    ])));
  Future<void>.delayed(const Duration(milliseconds: 300), () { current.dispose(); next.dispose(); confirmation.dispose(); });
}
