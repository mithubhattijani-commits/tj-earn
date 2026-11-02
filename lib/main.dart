// DIAGNOSTIC BRANCH SHIM (Jaani, 2 Nov 2026) — "bilkul khali app".
// On branch diagnostic/minimal the real entry point is
// lib/main_diagnostic.dart (zero plugins, zero network, runApp() is
// synchronous). The full app's main.dart is untouched on main — see
// git history. This shim keeps the default `flutter build apk` entry
// working without workflow changes.
import 'main_diagnostic.dart' as diag;

void main() => diag.main();
