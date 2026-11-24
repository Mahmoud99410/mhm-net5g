import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController ip;
  late final TextEditingController user;
  late final TextEditingController pass;
  bool remember = true;
  bool obscure = true;
  bool autoTried = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    ip = TextEditingController(text: s.routerIp);
    user = TextEditingController(text: s.routerUser);
    pass = TextEditingController(text: s.savedPass);
    remember = s.remember;
    if (s.savedPass.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _go());
    }
  }

  Future<void> _go() async {
    final s = context.read<AppState>();
    await s.connect(
        ip: ip.text, user: user.text, pass: pass.text, rememberMe: remember);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset('assets/icon.png', width: 96, height: 96),
                  ),
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: 'MHM ',
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                    TextSpan(
                        text: 'NET5G',
                        style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: AppColors.cyan)),
                  ])),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    s.t('تحكم كامل بالراوتر والمقوي', 'Full control of your router & extender'),
                    style: const TextStyle(color: AppColors.text2),
                  ),
                ),
                const SizedBox(height: 28),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: ip,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: s.t('عنوان الراوتر', 'Router address'),
                          prefixIcon: const Icon(Icons.router_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: user,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: s.t('اسم المستخدم', 'Username'),
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: pass,
                        obscureText: obscure,
                        textDirection: TextDirection.ltr,
                        onSubmitted: (_) => _go(),
                        decoration: InputDecoration(
                          labelText: s.t('كلمة مرور لوحة التحكم', 'Admin password'),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => obscure = !obscure),
                          ),
                        ),
                      ),
                      CheckboxListTile(
                        value: remember,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(s.t('تذكرني على هذا الجهاز', 'Remember me')),
                        onChanged: (v) => setState(() => remember = v ?? true),
                      ),
                      if (s.lastError != null)
                        NoteBox(s.lastError!, color: AppColors.red, icon: Icons.error_outline),
                      const SizedBox(height: 4),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16)),
                        onPressed: s.connecting ? null : _go,
                        icon: s.connecting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.login),
                        label: Text(s.t('دخول', 'Sign in'),
                            style: const TextStyle(fontSize: 16)),
                      ),
                    ],
                  ),
                ),
                NoteBox(
                  s.t(
                      'اتصل بشبكة الراوتر أولاً (واي فاي أو كيبل). العنوان الافتراضي 192.168.8.1، وكلمة المرور هي نفسها التي تدخل بها لوحة تحكم الراوتر أو تطبيق AI Life.',
                      'Connect to the router network first. Default address is 192.168.8.1; the password is the same as the router web page / AI Life app.'),
                  color: AppColors.blue,
                ),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  TextButton(onPressed: () => s.setLang('ar'), child: const Text('العربية')),
                  const Text('|'),
                  TextButton(onPressed: () => s.setLang('en'), child: const Text('English')),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
