import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:html_editor_enhanced/html_editor.dart';
import 'package:html_editor_enhanced/utils/shims/dart_ui.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// small function to always check if mounted before running setState()
void setState(
    bool mounted, void Function(Function()) setState, void Function() fn) {
  if (mounted) {
    setState.call(fn);
  }
}

/// courtesy of @modulovalue (https://github.com/modulovalue/dart_intersperse/blob/master/lib/src/intersperse.dart)
/// intersperses elements in between list items - used to insert dividers between
/// toolbar buttons when using [ToolbarType.nativeScrollable]
Iterable<T> intersperse<T>(T element, Iterable<T> iterable) sync* {
  final iterator = iterable.iterator;
  if (iterator.moveNext()) {
    yield iterator.current;
    while (iterator.moveNext()) {
      yield element;
      yield iterator.current;
    }
  }
}

/// Generates a random string to be used as the [VisibilityDetector] key.
/// Technically this limits the number of editors to a finite number, but
/// nobody will be embedding enough editors to reach the theoretical limit
/// (yes, this is a challenge ;-) )
String getRandString(int len) {
  var random = Random.secure();
  var values = List<int>.generate(len, (i) => random.nextInt(255));
  return base64UrlEncode(values);
}

/// Class that helps pass editor settings to the [onSettingsChange] callback
class EditorSettings {
  String parentElement;
  String fontName;
  double fontSize;
  bool isBold;
  bool isItalic;
  bool isUnderline;
  bool isStrikethrough;
  bool isSuperscript;
  bool isSubscript;
  Color foregroundColor;
  Color backgroundColor;
  bool isUl;
  bool isOl;
  bool isAlignLeft;
  bool isAlignCenter;
  bool isAlignRight;
  bool isAlignJustify;
  double lineHeight;
  TextDirection textDirection;

  EditorSettings({
    required this.parentElement,
    required this.fontName,
    required this.fontSize,
    required this.isBold,
    required this.isItalic,
    required this.isUnderline,
    required this.isStrikethrough,
    required this.isSuperscript,
    required this.isSubscript,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.isUl,
    required this.isOl,
    required this.isAlignLeft,
    required this.isAlignCenter,
    required this.isAlignRight,
    required this.isAlignJustify,
    required this.lineHeight,
    required this.textDirection,
  });
}

/// Class to create a script that can be run on Flutter Web.
///
/// [name] provides a unique identifier for the script. Note: It must be unique!
/// Otherwise your script may not be called when using [controller.evaluateJavascriptWeb].
/// [script] provides the script itself. If you'd like to return a value back to
/// Dart, you can do that via a postMessage call (see the README for an example).
class WebScript {
  String name;
  String script;

  WebScript({
    required this.name,
    required this.script,
  }) : assert(name.isNotEmpty && script.isNotEmpty);
}

/// Delegate for the icon that controls the expansion status of the toolbar
class ExpandIconDelegate extends SliverPersistentHeaderDelegate {
  final double? _size;
  final bool _isExpanded;
  final void Function() _setState;

  ExpandIconDelegate(this._size, this._isExpanded, this._setState);

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: _size,
      width: _size,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: IconButton(
        constraints: BoxConstraints(
          maxHeight: _size!,
          maxWidth: _size!,
        ),
        iconSize: _size! * 3 / 5,
        icon: Icon(
          _isExpanded ? Icons.expand_less : Icons.expand_more,
          color: Colors.grey,
        ),
        onPressed: () async {
          _setState.call();
        },
      ),
    );
  }

  @override
  double get maxExtent => _size!;

  @override
  double get minExtent => _size!;

  @override
  bool shouldRebuild(SliverPersistentHeaderDelegate oldDelegate) {
    return true;
  }
}

/// The following code contains all the code necessary for custom dropdowns.
/// It is really long because dropdowns utilize a bunch of private classes that
/// must be copy pasted.
/// The main change is marked with a comment in the code (CTRL-F "main change")

const Duration _kDropdownMenuDuration = Duration(milliseconds: 300);
const double _kMenuItemHeight = kMinInteractiveDimension;
const double _kDenseButtonHeight = 24.0;
const EdgeInsets _kMenuItemPadding = EdgeInsets.symmetric(horizontal: 16.0);
const EdgeInsetsGeometry _kAlignedButtonPadding =
    EdgeInsetsDirectional.only(start: 16.0, end: 4.0);
const EdgeInsets _kUnalignedButtonPadding = EdgeInsets.zero;
const EdgeInsets _kAlignedMenuMargin = EdgeInsets.zero;
const EdgeInsetsGeometry _kUnalignedMenuMargin =
    EdgeInsetsDirectional.only(start: 16.0, end: 24.0);

typedef DropdownButtonBuilder = List<Widget> Function(BuildContext context);

class _DropdownMenuPainter extends CustomPainter {
  _DropdownMenuPainter({
    this.color,
    this.elevation,
    this.selectedIndex,
    required this.resize,
    required this.getSelectedItemOffset,
  })  : _painter = BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2.0),
          boxShadow: kElevationToShadow[elevation],
        ).createBoxPainter(),
        super(repaint: resize);

  final Color? color;
  final int? elevation;
  final int? selectedIndex;
  final Animation<double> resize;
  final ValueGetter<double> getSelectedItemOffset;
  final BoxPainter _painter;

  @override
  void paint(Canvas canvas, Size size) {
    final selectedItemOffset = getSelectedItemOffset();
    final top = Tween<double>(
      begin: selectedItemOffset.clamp(
          0.0, max(size.height - _kMenuItemHeight, 0.0)),
      end: 0.0,
    );

    final bottom = Tween<double>(
      begin: (top.begin! + _kMenuItemHeight)
          .clamp(min(_kMenuItemHeight, size.height), size.height),
      end: size.height,
    );

    final rect = Rect.fromLTRB(
        0.0, top.evaluate(resize), size.width, bottom.evaluate(resize));

    _painter.paint(canvas, rect.topLeft, ImageConfiguration(size: rect.size));
  }

  @override
  bool shouldRepaint(_DropdownMenuPainter oldPainter) {
    return oldPainter.color != color ||
        oldPainter.elevation != elevation ||
        oldPainter.selectedIndex != selectedIndex ||
        oldPainter.resize != resize;
  }
}

class CustomDropdownMenuItem extends StatelessWidget {
  const CustomDropdownMenuItem({
    super.key,
    required this.height,
    required this.child,
  });

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) => PointerInterceptor(
        child: Container(
          height: height,
          alignment: Alignment.centerLeft,
          child: child,
        ),
      );
}
