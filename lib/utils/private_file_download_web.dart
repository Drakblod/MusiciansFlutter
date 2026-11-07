import 'dart:js_interop';
import 'dart:typed_data';

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts);
}
@JS('URL.createObjectURL')
external String _createUrl(_Blob blob);
@JS('URL.revokeObjectURL')
external void _revokeUrl(String url);
@JS('document.createElement')
external _Anchor _createElement(String tag);
extension type _Anchor._(JSObject _) implements JSObject {
  external set href(String value);
  external set download(String value);
  external void click();
}

Future<void> savePrivateFile(Uint8List bytes, String name) async {
  final url = _createUrl(_Blob(<JSAny>[bytes.toJS].toJS));
  try {
    _createElement('a')..href = url..download = name..click();
    // Yield one browser task so the download consumes the temporary URL.
    await Future<void>.delayed(Duration.zero);
  } finally {
    _revokeUrl(url);
  }
}
