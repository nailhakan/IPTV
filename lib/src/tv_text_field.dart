import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'settings.dart';

/// A text field that is remote-control friendly.
///
/// With a TV remote, focusing an Android text field opens the on-screen keyboard right away and the
/// keyboard swallows the D-pad, so the user cannot leave the field. In TV mode this field only opens the
/// keyboard when OK/Select is pressed; up/down (or the keyboard's confirm key) end editing again.
/// Outside TV mode it behaves like a normal [TextField].
class RemoteTextField extends StatefulWidget {
  const RemoteTextField({
    super.key,
    this.controller,
    this.decoration,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final InputDecoration? decoration;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<RemoteTextField> createState() => _RemoteTextFieldState();
}

class _RemoteTextFieldState extends State<RemoteTextField> {
  late final FocusNode _node = FocusNode(onKeyEvent: _onKey);
  bool _editing = false;

  bool get _tv => AppSettings.instance.tvMode;

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (!_node.hasFocus && _editing) setState(() => _editing = false);
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _start() {
    if (_editing) return;
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
  }

  void _stop() {
    if (!_editing) return;
    setState(() => _editing = false);
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!_tv || e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final select = k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter;
    if (!_editing && select) {
      _start();
      return KeyEventResult.handled;
    }
    // A TextField swallows up/down itself (caret movement), so move the focus explicitly.
    final down = k == LogicalKeyboardKey.arrowDown;
    if (down || k == LogicalKeyboardKey.arrowUp) {
      _stop();
      node.focusInDirection(down ? TraversalDirection.down : TraversalDirection.up);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tv = _tv;
    return TextField(
      controller: widget.controller,
      focusNode: _node,
      decoration: widget.decoration,
      obscureText: widget.obscureText,
      onChanged: widget.onChanged,
      readOnly: tv && !_editing,
      showCursor: tv ? _editing : null,
      onTap: tv ? _start : null,
      textInputAction: tv ? TextInputAction.next : null,
      onSubmitted: (v) {
        widget.onSubmitted?.call(v);
        if (tv) {
          _stop();
          FocusScope.of(context).nextFocus();
        }
      },
    );
  }
}
