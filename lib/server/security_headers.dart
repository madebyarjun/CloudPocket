import 'package:shelf/shelf.dart';

Middleware securityHeaders() => (Handler inner) => (Request request) async {
  // Control requests are small JSON documents. File bodies keep streaming through
  // their own handlers and never enter this bounded control buffer.
  if (request.method == 'POST' &&
      request.url.path.startsWith('api/') &&
      request.url.path != 'api/upload' &&
      request.url.path != 'api/room/upload') {
    const limit = 64 * 1024;
    if ((request.contentLength ?? 0) > limit) {
      return Response(413, body: 'Control request is too large');
    }
    final bytes = <int>[];
    await for (final chunk in request.read()) {
      if (bytes.length + chunk.length > limit) {
        return Response(413, body: 'Control request is too large');
      }
      bytes.addAll(chunk);
    }
    request = request.change(body: bytes);
  }
  final response = await inner(request);
  final contentType = response.headers['content-type'] ?? '';
  final isDocument = contentType.contains('text/html');
  final isFile = request.url.path.startsWith('api/files/') || request.url.path.startsWith('api/room/files/');
  return response.change(headers: {
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'no-referrer',
    'x-frame-options': 'DENY',
    'permissions-policy': 'camera=(), microphone=(), geolocation=()',
    if (request.url.path.startsWith('api/')) 'cache-control': 'no-store',
    if (isDocument && !isFile)
      'content-security-policy': "default-src 'self'; script-src 'self' https://accounts.google.com; style-src 'self' 'unsafe-inline' https://accounts.google.com; img-src 'self' data: blob:; media-src 'self' blob:; connect-src 'self' ws: wss: https://accounts.google.com; frame-src https://accounts.google.com cloudpocket:; object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'",
    // A shared document must never gain the portal's authenticated origin.
    if (isFile) 'content-security-policy': "sandbox; default-src 'none'; style-src 'unsafe-inline'; img-src data:; frame-ancestors 'none'",
  });
};
