// ignore_for_file: avoid_print
//
// Run with:
//   flutter test test/generate_icon_test.dart
//
// This renders the ZeroTabLogo at 1024×1024 and saves it to
// assets/icon/app_icon.png, which flutter_launcher_icons uses
// to generate all platform icon sizes.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zerotab/shared/widgets/zerotab_logo.dart';

void main() {
  testWidgets('Generate 1024×1024 app icon PNG', (WidgetTester tester) async {
    // Use a large physical size so the icon renders at full resolution
    tester.view.physicalSize    = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1.0;

    final repaintKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: repaintKey,
          child: const SizedBox(
            width:  1024,
            height: 1024,
            child: ZeroTabLogo(size: 1024, showBackground: true),
          ),
        ),
      ),
    );

    await tester.pump(); // settle the frame

    final boundary = repaintKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image   = await boundary.toImage(pixelRatio: 1.0);
    final data    = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes   = data!.buffer.asUint8List();

    // Save to assets/icon/
    final dir = Directory('assets/icon');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final file = File('assets/icon/app_icon.png');
    file.writeAsBytesSync(bytes);

    print('');
    print('✅  Icon saved → ${file.absolute.path}');
    print('    Size: ${bytes.length} bytes  (${image.width}×${image.height}px)');
    print('');
    print('Next step:');
    print('  dart run flutter_launcher_icons');
    print('');

    expect(bytes.length, greaterThan(5000), reason: 'PNG should not be empty');
    expect(image.width,  1024);
    expect(image.height, 1024);
  });
}
