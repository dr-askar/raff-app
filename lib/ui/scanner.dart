import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

Future<String?> scanBarcode(BuildContext context) => Navigator.push<String>(context,
  MaterialPageRoute(builder: (_) => const BarcodeScannerPage()));

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});
  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}
class _BarcodeScannerPageState extends State<BarcodeScannerPage> with WidgetsBindingObserver {
  final controller = MobileScannerController(autoStart: false, detectionSpeed: DetectionSpeed.noDuplicates,
    formats: [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE,
      BarcodeFormat.code128, BarcodeFormat.code39, BarcodeFormat.itf]);
  final manual = TextEditingController();
  bool finished = false;
  double zoom = 0;
  Future<void> startCamera() async {
    try { await controller.start(); }
    catch (_) { /* MobileScanner exposes camera/permission errors through errorBuilder. */ }
  }
  @override
  void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) { startCamera(); } });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!controller.value.hasCameraPermission) { return; }
    if (state == AppLifecycleState.resumed && !finished) { startCamera(); }
    else if (state != AppLifecycleState.resumed) { controller.stop(); }
  }
  void finish(String? code) {
    if (finished || code == null || code.trim().isEmpty) { return; }
    finished = true; HapticFeedback.lightImpact(); controller.stop();
    Navigator.pop(context, code.trim());
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); controller.dispose(); manual.dispose(); super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مسح الباركود'), actions: [IconButton(tooltip: 'الفلاش', onPressed: () => controller.toggleTorch(), icon: const Icon(Icons.flash_on))]),
    body: Column(children: [
      Expanded(child: Stack(alignment: Alignment.center, children: [
        MobileScanner(controller: controller, onDetect: (capture) {
          for (final barcode in capture.barcodes) { if (barcode.rawValue != null) { finish(barcode.rawValue); break; } }
        }, errorBuilder: (context, error, child) => const Center(child: Padding(padding: EdgeInsets.all(24),
          child: Text('الكاميرا غير متاحة. اسمح بالوصول إليها من إعدادات الهاتف أو أدخل الباركود يدوياً.')))),
        IgnorePointer(child: Container(width: 280, height: 150, decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(22)))),
      ])),
      const Padding(padding: EdgeInsets.only(top: 12), child: Text('ضع الباركود داخل الإطار • حرّك الهاتف حتى تتضح الصورة')),
      Row(children: [const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.zoom_in)), Expanded(child:
        Slider(value: zoom, onChanged: (value) { setState(() => zoom = value); controller.setZoomScale(value); }))]),
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), child: Row(children: [
        Expanded(child: TextField(controller: manual, textDirection: TextDirection.ltr,
          decoration: const InputDecoration(labelText: 'إدخال الباركود يدوياً'), onSubmitted: finish)),
        const SizedBox(width: 12), FilledButton(onPressed: () => finish(manual.text), child: const Text('بحث')),
      ])),
    ]),
  );
}
