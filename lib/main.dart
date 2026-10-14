import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/app_store.dart';
import 'ui/home.dart';

const cloudEnabled = bool.fromEnvironment('CLOUD', defaultValue: false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppStore? store; String? startupError;
  try {
    if (cloudEnabled) {
      await Firebase.initializeApp(options: const FirebaseOptions(
        apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
        appId: String.fromEnvironment('FIREBASE_APP_ID'),
        messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
        projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
        authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
      ));
    }
    store = AppStore(prefs: await SharedPreferences.getInstance(), cloud: cloudEnabled,
      storeId: const String.fromEnvironment('STORE_ID', defaultValue: 'main'));
    await store.initialize();
  } catch (_) { startupError = 'تعذر بدء التطبيق. تحقق من إعدادات Firebase أو مساحة التخزين ثم أعد المحاولة.'; }
  runApp(RaffApp(store: store, startupError: startupError));
}

class RaffApp extends StatelessWidget {
  final AppStore? store;
  final String? startupError;
  const RaffApp({super.key, this.store, this.startupError});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'رفّ', debugShowCheckedModeBanner: false,
    locale: const Locale('ar'), supportedLocales: const [Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2563a6)),
      scaffoldBackgroundColor: const Color(0xfff3f6fa),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xfff3f6fa), centerTitle: false),
    ),
    home: startupError != null ? Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24),
      child: Text(startupError!)))) : store!.cloud ? AuthGate(store: store!) : Home(store: store!),
  );
}

class AuthGate extends StatefulWidget {
  final AppStore store;
  const AuthGate({super.key, required this.store});
  @override
  State<AuthGate> createState() => _AuthGateState();
}
class _AuthGateState extends State<AuthGate> {
  final email = TextEditingController(), password = TextEditingController();
  Future<void>? connection;
  String? connectedUid;
  String error = ''; bool busy = false;
  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }
  Future<void> login() async {
    setState(() { busy = true; error = ''; });
    try { await FirebaseAuth.instance.signInWithEmailAndPassword(email: email.text.trim(), password: password.text); }
    on FirebaseAuthException catch (_) { if (mounted) { setState(() => error = 'تعذر الدخول. تحقق من البريد وكلمة المرور والاتصال.'); } }
    finally { if (mounted) { setState(() => busy = false); } }
  }
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snap) {
      if (snap.connectionState == ConnectionState.waiting) { return const Scaffold(body: Center(child: CircularProgressIndicator())); }
      if (snap.data != null) {
        if (connectedUid != snap.data!.uid) {
          connectedUid = snap.data!.uid;
          connection = widget.store.connect(snap.data!);
        }
        return FutureBuilder<void>(future: connection, builder: (context, state) {
          if (state.connectionState != ConnectionState.done) { return const Scaffold(body: Center(child: CircularProgressIndicator())); }
          if (state.hasError) { return Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(padding: EdgeInsets.all(24), child: Text('تعذر فتح المحل. تحقق من الاتصال وعضوية الحساب وصلاحيات Firebase.')),
            FilledButton(onPressed: () => setState(() { connection = widget.store.connect(snap.data!); }), child: const Text('إعادة المحاولة')),
            TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('تسجيل الخروج')),
          ]))); }
          return Home(store: widget.store);
        });
      }
      if (connectedUid != null) { connectedUid = null; connection = null; widget.store.disconnect(); }
      return Scaffold(body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(28),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.inventory_2_outlined, size: 64, color: Color(0xff2563a6)),
          const SizedBox(height: 16), const Text('أهلاً بك في رفّ', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8), const Text('أسعار واضحة. شغل أسهل.', textAlign: TextAlign.center), const SizedBox(height: 32),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'البريد الإلكتروني')),
          const SizedBox(height: 16), TextField(controller: password, obscureText: true, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'كلمة المرور'), onSubmitted: (_) { if (!busy) { login(); } }),
          if (error.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(error, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 24), FilledButton(onPressed: busy ? null : login, child: Padding(padding: const EdgeInsets.all(14), child: Text(busy ? 'جارٍ الدخول…' : 'دخول إلى المحل'))),
        ])))));
    });
}
