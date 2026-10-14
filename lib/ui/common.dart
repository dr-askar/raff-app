import 'package:flutter/material.dart';

String money(num n) => n.toStringAsFixed(n == n.roundToDouble() ? 0 : 2)
  .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

Future<void> perform(BuildContext context, Future<void> Function() action, [String message = 'تم الحفظ بنجاح']) async {
  try {
    await action();
    if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: const Color(0xff237b66))); }
  } catch (e) {
    if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(e is FormatException ? e.message : 'تعذر إتمام العملية. تحقق من الاتصال والصلاحيات وحاول مجدداً.'),
      backgroundColor: const Color(0xffb34747), duration: const Duration(seconds: 7))); }
  }
}

Future<bool> confirm(BuildContext context, String title, String body) async =>
  await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: Text(body), actions: [
    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
  ])) ?? false;

class EmptyState extends StatelessWidget {
  final String title, detail;
  final IconData icon;
  const EmptyState(this.title, this.detail, {super.key, this.icon = Icons.inventory_2_outlined});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 54, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 16),
    Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
    const SizedBox(height: 8), Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: Colors.blueGrey)),
  ])));
}
