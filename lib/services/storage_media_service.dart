import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

/// Private media requests carry a fresh Auth token. The server checks current
/// canonical membership on each operation and never returns a download token.
class StorageMediaService {
  Uri get endpoint => Uri.https(
    'europe-west1-${Firebase.app().options.projectId}.cloudfunctions.net',
    '/storageMedia',
  );

  Future<http.Response> _request(String method, Map<String, String> query,
      {Object? json, Uint8List? bytes, String? range}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to access media.');
    final token = await user.getIdToken();
    if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
      throw StateError('Your session changed.');
    }
    final request = http.Request(method, endpoint.replace(queryParameters:query));
    request.headers['Authorization'] = 'Bearer $token';
    if (range != null) request.headers['Range'] = range;
    if (bytes != null) {
      request.headers['Content-Type'] = 'application/octet-stream';
      request.bodyBytes = bytes;
    } else if (json != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(json);
    }
    final client = http.Client();
    try {
      final result = await http.Response.fromStream(await client.send(request));
      if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
        throw StateError('Your session changed.');
      }
      if (result.statusCode != 200 && result.statusCode != 206) {
        throw StateError('Media operation unavailable for your current access.');
      }
      return result;
    } finally {
      client.close();
    }
  }

  Future<String> upload({required String kind, required Uint8List bytes,
      required String fileName, required String contentType, String? bandId}) async {
    final started = jsonDecode((await _request('POST', {'action':'begin'}, json:{
      'kind':kind, 'bandId':bandId, 'fileName':fileName,
      'contentType':contentType, 'byteLength':bytes.length,
    })).body) as Map<String, dynamic>;
    final id = started['id'] as String;
    final chunkBytes = started['chunkBytes'] as int;
    for (var offset = 0; offset < bytes.length; offset += chunkBytes) {
      final end = offset + chunkBytes < bytes.length ? offset + chunkBytes : bytes.length;
      await _request('PUT', {'action':'part','id':id,'index':'${offset ~/ chunkBytes}'},
        bytes:Uint8List.sublistView(bytes, offset, end));
    }
    await _request('POST', {'action':'finish','id':id});
    return id;
  }

  Future<void> registerBandFile(String id, String category, String bandId) async {
    await _request('POST', {'action':'register-band-file','id':id},
      json:{'category':category,'bandId':bandId});
  }

  Future<Uint8List> download(String id) async {
    final metadata = jsonDecode((await _request('GET', {'id':id,'action':'metadata'})).body) as Map<String,dynamic>;
    final length = metadata['byteLength'] as int;
    final output = BytesBuilder(copy: false);
    const chunkBytes = 4 * 1024 * 1024;
    for (var offset = 0; offset < length; offset += chunkBytes) {
      final end = offset + chunkBytes < length ? offset + chunkBytes - 1 : length - 1;
      final result = await _request('GET', {'id':id}, range:'bytes=$offset-$end');
      if (result.bodyBytes.length != end - offset + 1) throw StateError('Incomplete media download.');
      output.add(result.bodyBytes);
    }
    return output.takeBytes();
  }

  Future<void> delete(String id, {String? bandId}) async {
    await _request('DELETE', {'id':id, if (bandId != null) 'bandId':bandId});
  }

}
