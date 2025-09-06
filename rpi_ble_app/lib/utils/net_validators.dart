class NetValidators {
  static final RegExp ipv4 = RegExp(
      r'^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)$');

  static String? requiredIpv4(String? v) {
    v = v?.trim();
    if (v == null || v.isEmpty) return 'Required';
    if (!ipv4.hasMatch(v)) return 'Invalid IPv4';
    return null;
  }

  static String? optionalDnsList(String? v) {
    final s = v?.trim();
    if (s == null || s.isEmpty) return null;
    final items = s.split(RegExp(r'[,\n\s]+')).where((e) => e.isNotEmpty);
    for (final ip in items) {
      if (!ipv4.hasMatch(ip)) return 'Invalid DNS "$ip"';
    }
    return null;
  }

  static List<String> normalizeDnsList(String raw) => raw
      .split(RegExp(r'[,\n\s]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty && ipv4.hasMatch(e))
      .toList();
}
