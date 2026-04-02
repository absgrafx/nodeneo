import 'package:flutter/material.dart';

/// Synthetic username for **app lock only** (not your wallet, not sent anywhere).
///
/// Password managers expect a **username + password** pair. We keep this string in a
/// near-invisible field so vault entries can match without showing a “fake username” UI.
const String kAppLockAutofillUsername = 'NodeNeo';

/// Minimal footprint, still registered for autofill / platform credential heuristics.
class AppLockHiddenUsernameForAutofill extends StatelessWidget {
  final TextEditingController controller;

  const AppLockHiddenUsernameForAutofill({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Password manager account id',
      textField: true,
      child: Opacity(
        opacity: 0,
        child: SizedBox(
          height: 1,
          child: TextField(
            controller: controller,
            autocorrect: false,
            enableSuggestions: false,
            stylusHandwritingEnabled: false,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration.collapsed(hintText: ''),
            style: const TextStyle(fontSize: 1, height: 0.01),
            strutStyle: const StrutStyle(fontSize: 1, height: 0.01),
          ),
        ),
      ),
    );
  }
}
