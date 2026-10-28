import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/phone_remote.dart';

void main() {
  testWidgets('injected keys drive focus traversal and activation like a real remote', (tester) async {
    final a = FocusNode(), b = FocusNode(), c = FocusNode();
    addTearDown(() {
      a.dispose();
      b.dispose();
      c.dispose();
    });
    var pressed = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          TextButton(focusNode: a, autofocus: true, onPressed: () => pressed = 'a', child: const Text('A')),
          TextButton(focusNode: b, onPressed: () => pressed = 'b', child: const Text('B')),
          TextButton(focusNode: c, onPressed: () => pressed = 'c', child: const Text('C')),
        ]),
      ),
    ));
    await tester.pump();
    expect(a.hasFocus, isTrue);

    injectKey('down');
    await tester.pump();
    expect(b.hasFocus, isTrue, reason: 'down must move focus to the next button');

    injectKey('down');
    await tester.pump();
    expect(c.hasFocus, isTrue);

    injectKey('up');
    await tester.pump();
    expect(b.hasFocus, isTrue);

    injectKey('ok');
    await tester.pump();
    expect(pressed, 'b', reason: 'OK must press the focused button');
  });

  testWidgets('typed text goes into the focused field and can submit it', (tester) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(() {
      controller.dispose();
      focus.dispose();
    });
    var changed = '';
    var submitted = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TextField(controller: controller, focusNode: focus, autofocus: true, onChanged: (v) => changed = v, onSubmitted: (v) => submitted = v),
      ),
    ));
    await tester.pump();

    expect(applyTextToFocusedField('maç özeti', submit: true), isTrue);
    await tester.pump();
    expect(controller.text, 'maç özeti');
    expect(changed, 'maç özeti', reason: 'onChanged must fire so lists can filter');
    expect(submitted, 'maç özeti');
  });

  testWidgets('typing with no text field focused reports failure', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TextButton(autofocus: true, onPressed: () {}, child: const Text('x')))));
    await tester.pump();
    expect(applyTextToFocusedField('abc'), isFalse);
  });
}
