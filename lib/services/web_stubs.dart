// Stub file for non-web platforms
// This file provides empty implementations for platforms that don't support web APIs

class _HtmlWindow {
  // Stub implementation
}

class _Html {
  static _HtmlWindow get window => _HtmlWindow();
}

class _JsUtil {
  static dynamic getProperty(dynamic object, String property) => null;
  static dynamic callMethod(dynamic object, String method, List<dynamic> args) => null;
  static Future<dynamic> promiseToFuture(dynamic promise) async => null;
  static dynamic dartify(dynamic object) => null;
}

// Export the stubs with the same names as the web imports
final html = _Html();
final js_util = _JsUtil();
