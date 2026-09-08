import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

const backendUrl = String.fromEnvironment('BACKEND_URL');
class ApiException implements Exception {
  const ApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
}
class BackendApi {
  BackendApi._();
  static final instance = BackendApi._();
  String? token;
  Map<String,dynamic>? user;
  WebSocketChannel? events;
  static const storage = FlutterSecureStorage();
  String get sessionKey => 'buklin-session-$backendUrl';
  Future<void> restoreSession() async {
    final saved = await storage.read(key: sessionKey);
    if (saved == null) return;
    try {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      token = data['token'] as String;
      user = Map<String, dynamic>.from(data['user']);
    } on FormatException { await storage.delete(key: sessionKey); }
  }
  void closeEvents() { events?.sink.close(); events = null; }
  Future<Map<String,dynamic>> call(String method,String path,[Map<String,dynamic>? body]) async {
    final request=http.Request(method,Uri.parse('$backendUrl$path'));
    request.headers['Content-Type']='application/json';
    if(token!=null) request.headers['Authorization']='Bearer $token';
    if(body!=null)request.body=jsonEncode(body);
    final client=http.Client();
    try {
      final response=await http.Response.fromStream(await client.send(request).timeout(const Duration(seconds:20)));
      final data=jsonDecode(response.body) as Map<String,dynamic>;
      if(response.statusCode>=400)throw ApiException(data['error']?.toString() ?? 'Request failed', response.statusCode);
      return data;
    } finally {client.close();}
  }
  Future<void> login(String email,String password,{bool register=false}) async {
    final result=await call('POST',register?'/auth/register':'/auth/login',{'email':email,'password':password});
    token=result['token'];user=Map<String,dynamic>.from(result['user']);
    await storage.write(key: sessionKey, value: jsonEncode({'token': token, 'user': user}));
  }
  Future<void> logout() async {
    await call('POST','/auth/logout');closeEvents();token=null;user=null;
    await storage.delete(key: sessionKey);
  }
  StreamSubscription<dynamic> listen(void Function() refresh) {
    closeEvents();
    final uri=Uri.parse(backendUrl);
    final channel=WebSocketChannel.connect(uri.replace(scheme:uri.scheme=='https'?'wss':'ws',path:'/events'));
    events=channel;
    channel.sink.add(jsonEncode({'token':token}));
    return channel.stream.listen((_)=>refresh(),onError:(_){},cancelOnError:true);
  }
}
