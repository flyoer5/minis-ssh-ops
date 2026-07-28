Uri validateBackendBaseUrl(String raw) {
  final value = raw.trim();
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw ArgumentError.value(raw, 'baseUrl', 'Enter a valid backend URL');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw ArgumentError.value(raw, 'baseUrl', 'Only HTTP and HTTPS are supported');
  }
  final host = uri.host.toLowerCase();
  final loopback = host == 'localhost' || host == '127.0.0.1' || host == '::1';
  if (uri.scheme == 'http' && !loopback) {
    throw ArgumentError.value(raw, 'baseUrl', 'Remote backend URLs must use HTTPS');
  }
  return uri;
}