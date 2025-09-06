import 'package:flutter/material.dart';

class KV extends StatelessWidget {
  const KV(this.map, {super.key, this.title});
  final Map<String, dynamic>? map;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final m = map;
    if (m == null) return const Text('—');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Text(title!, style: const TextStyle(fontWeight: FontWeight.bold)),
        if (title != null) const SizedBox(height: 6),
        ...m.entries.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      e.key,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 5,
                    child: Text(
                      e.value is List
                          ? (e.value as List).join(', ')
                          : '${e.value}',
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}
