import 'package:flutter/material.dart';

/// Opens the exact cached widget selection, even offline or across midnight.
class WidgetContentPage extends StatelessWidget {
  const WidgetContentPage({super.key, required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SelectableText(
        body,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.8),
      ),
    ),
  );
}
