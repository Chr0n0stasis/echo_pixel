import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

class WebDavService {
  String? _serverUrl;
  String? _username;
  String? _password;
  String _uploadRootPath = '/';
  bool _isConnected = false;

  bool get isConnected => _isConnected;
  String? get serverUrl => _serverUrl;
  String get uploadRootPath => _uploadRootPath;

  // 初始化WebDAV连接
  Future<bool> initialize(
    String serverUrl, {
    String? username,
    String? password,
    String uploadRootPath = '/',
  }) async {
    _serverUrl = serverUrl;
    _username = username;
    _password = password;
    _uploadRootPath =
        uploadRootPath.endsWith('/') ? uploadRootPath : '$uploadRootPath/';

    try {
      final response = await _makeRequest(
        method: 'PROPFIND',
        path: _uploadRootPath,
        headers: {'Depth': '0'},
      );
      _isConnected = response.statusCode == 207 || response.statusCode == 200;
      return _isConnected;
    } catch (e) {
      _isConnected = false;
      return false;
    }
  }

  // 列出目录内容
  Future<List<WebDavItem>> listDirectory(String path) async {
    if (!_isConnected) {
      throw Exception('WebDAV not connected');
    }

    try {
      final response = await _makeRequest(
        method: 'PROPFIND',
        path: path,
        headers: {'Depth': '1'},
      );

      if (response.statusCode != 207) {
        throw Exception('Failed to list directory: ${response.statusCode}');
      }

      return _parseMultiStatus(response.body, path);
    } catch (e) {
      throw Exception('Error listing directory: $e');
    }
  }

  // 创建目录
  Future<bool> createDirectory(String path) async {
    if (!_isConnected) {
      throw Exception('WebDAV not connected');
    }

    try {
      final response = await _makeRequest(method: 'MKCOL', path: path);

      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      throw Exception('Error creating directory: $e');
    }
  }

  // 上传文件
  Future<bool> uploadFile(String remotePath, File localFile) async {
    if (!_isConnected) {
      throw Exception('WebDAV not connected');
    }

    try {
      final bytes = await localFile.readAsBytes();

      final response = await _makeRequest(
        method: 'PUT',
        path: remotePath,
        body: bytes,
        headers: {
          'Content-Type': 'application/octet-stream',
          'Content-Length': bytes.length.toString(),
        },
      );

      return response.statusCode == 201 ||
          response.statusCode == 200 ||
          response.statusCode == 204;
    } catch (e) {
      throw Exception('Error uploading file: $e');
    }
  }

  // 下载文件
  Future<File> downloadFile(String remotePath, String localPath) async {
    if (!_isConnected) {
      throw Exception('WebDAV not connected');
    }

    try {
      final response = await _makeRequest(method: 'GET', path: remotePath);

      if (response.statusCode != 200) {
        throw Exception('Failed to download file: ${response.statusCode}');
      }

      final file = File(localPath);
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } catch (e) {
      throw Exception('Error downloading file: $e');
    }
  }

  // 删除文件或目录
  Future<bool> delete(String path) async {
    if (!_isConnected) {
      throw Exception('WebDAV not connected');
    }

    try {
      final response = await _makeRequest(method: 'DELETE', path: path);

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      throw Exception('Error deleting item: $e');
    }
  }

  // 生成HTTP请求
  Future<http.Response> _makeRequest({
    required String method,
    required String path,
    Map<String, String>? headers,
    dynamic body,
  }) async {
    if (_serverUrl == null) {
      throw Exception('WebDAV not configured');
    }

    final uri = Uri.parse(
      '$_serverUrl${path.startsWith('/') ? path : '/$path'}',
    );

    // 创建请求头
    Map<String, String> requestHeaders = {...?headers};

    // 如果提供了用户名和密码，则添加认证头
    if (_username != null && _password != null) {
      final auth =
          'Basic ${base64Encode(utf8.encode('$_username:$_password'))}';
      requestHeaders['Authorization'] = auth;
    }

    final request = http.Request(method, uri);
    request.headers.addAll(requestHeaders);

    if (body != null) {
      request.bodyBytes =
          body is List<int> ? body : utf8.encode(body.toString());
    }

    final streamedResponse = await request.send();
    return http.Response.fromStream(streamedResponse);
  }

  // 解析WebDAV目录列表响应
  List<WebDavItem> _parseMultiStatus(String xml, String basePath) {
    // 简单实现，生产环境应使用正规的XML解析器
    final items = <WebDavItem>[];

    // 简单提取href和resourcetype
    final hrefRegExp = RegExp(r'<D:href>(.*?)</D:href>', multiLine: true);
    final isCollectionRegExp = RegExp(
      r'<D:resourcetype>\s*<D:collection/>\s*</D:resourcetype>',
      multiLine: true,
    );

    final matches = hrefRegExp.allMatches(xml);
    for (var match in matches) {
      final href = match.group(1)!;

      // 跳过当前目录
      if (href.endsWith('/') && basePath.endsWith('/') && href == basePath) {
        continue;
      }

      final itemXml = xml.substring(
        match.start,
        xml.indexOf('</D:response>', match.start) + 13,
      );
      final isCollection = isCollectionRegExp.hasMatch(itemXml);

      // 提取最后一级路径名作为名称
      String name = href;
      if (name.endsWith('/')) {
        name = name.substring(0, name.length - 1);
      }
      name = name.split('/').last;

      items.add(WebDavItem(path: href, name: name, isDirectory: isCollection));
    }

    return items;
  }
}

// WebDAV项目类（文件或目录）
class WebDavItem {
  final String path;
  final String name;
  final bool isDirectory;

  WebDavItem({
    required this.path,
    required this.name,
    required this.isDirectory,
  });

  @override
  String toString() =>
      'WebDavItem(path: $path, name: $name, isDirectory: $isDirectory)';
}
