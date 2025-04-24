import 'dart:io';
import 'dart:convert';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart'; // 添加这个导入

class WebDavService {
  String? _serverUrl;
  String? _username;
  String? _password;
  String _uploadRootPath = '/';
  bool _isConnected = false;

  // 持久化的HttpClient和IOClient
  late HttpClient _httpClient;
  late IOClient _client;

  // 单例实现
  static final WebDavService _instance = WebDavService._internal();

  // 工厂构造函数，返回单例实例
  factory WebDavService() {
    return _instance;
  }

  // 内部私有构造函数
  WebDavService._internal() {
    final context = SecurityContext.defaultContext;
    context.allowLegacyUnsafeRenegotiation = true;
    _httpClient = HttpClient(context: context);
    _client = IOClient(_httpClient);
  }

  bool get isConnected => _isConnected;
  String? get serverUrl => _serverUrl;
  String get uploadRootPath => _uploadRootPath;

  // 释放资源
  void dispose() {
    _client.close();
    _httpClient.close();
  }

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
      // 首先尝试 PROPFIND
      var response = await _makeRequest(
        method: 'PROPFIND',
        path: _uploadRootPath,
        headers: {'Depth': '0'},
      );
      // 如果服务器不支持 PROPFIND (405)，退而求其次用 GET
      if (response.statusCode == 405) {
        response = await _makeRequest(
          method: 'GET',
          path: _uploadRootPath,
        );
      }
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

  // 递归创建目录（处理嵌套目录创建）
  Future<void> createDirectoryRecursive(String path) async {
    if (!_isConnected) {
      throw Exception('WebDAV not connected');
    }

    try {
      // 首先尝试直接创建
      final response = await _makeRequest(method: 'MKCOL', path: path);

      if (response.statusCode == 201 || response.statusCode == 200) {
        return; // Success, just return void
      }

      // 如果失败且是因为父目录不存在
      if (response.statusCode == 409 || response.statusCode == 404) {
        // 获取父目录路径
        final parentPath = path.substring(0, path.lastIndexOf('/'));
        if (parentPath.isEmpty || parentPath == path) {
          throw Exception('Invalid directory path: $path');
        }

        // 递归创建父目录
        debugPrint('尝试创建父目录: $parentPath');
        await createDirectoryRecursive(parentPath);

        // 父目录创建成功，再次尝试创建当前目录
        final retryResponse = await _makeRequest(method: 'MKCOL', path: path);
        if (retryResponse.statusCode != 201 &&
            retryResponse.statusCode != 200) {
          throw Exception(
              'Failed to create directory: ${retryResponse.statusCode}');
        }
        return;
      }

      throw Exception('Failed to create directory: ${response.statusCode}');
    } catch (e) {
      debugPrint('创建目录错误: $e');
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

  // 删除文件 - 提供更明确的API
  Future<bool> deleteFile(String path) async {
    return delete(path);
  }

  // 删除目录 - 提供更明确的API
  Future<bool> deleteDirectory(String path) async {
    return delete(path);
  }

  // 检查文件是否存在
  Future<bool> fileExists(String path) async {
    if (!_isConnected) {
      throw Exception('WebDAV not connected');
    }

    try {
      final response = await _makeRequest(
        method: 'PROPFIND',
        path: path,
        headers: {'Depth': '0'},
      );

      // 返回200或207表示文件存在
      return response.statusCode == 200 || response.statusCode == 207;
    } catch (e) {
      // 如果是404错误，表示文件不存在
      if (e.toString().contains('404')) {
        return false;
      }
      // 其他错误重新抛出
      throw Exception('Error checking file existence: $e');
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
    Map<String, String> requestHeaders = {...?headers};

    // 如果提供了用户名和密码，则添加认证头
    if (_username != null && _password != null) {
      final auth =
          'Basic [0m${base64Encode(utf8.encode('$_username:$_password'))}';
      requestHeaders['Authorization'] = auth;
    }

    // 为 PROPFIND 请求添加标准 XML body 和 Content-Type
    if (method == 'PROPFIND') {
      requestHeaders['Content-Type'] = 'application/xml';
    }

    http.Response response;
    switch (method) {
      case 'GET':
        response = await _client.get(uri, headers: requestHeaders);
        break;
      // ...其他分支不变...
      default:
        final request = http.Request(method, uri);
        request.headers.addAll(requestHeaders);
        if (method == 'PROPFIND') {
          const xmlBody = '''<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:allprop/>
</D:propfind>''';
          request.body = xmlBody;
        } else if (body != null) {
          request.bodyBytes =
              body is List<int> ? body : utf8.encode(body.toString());
        }
        final streamed = await _client.send(request);
        response = await http.Response.fromStream(streamed);
    }

    return response;
  }

  // 解析WebDAV目录列表响应
  List<WebDavItem> _parseMultiStatus(String xml, String basePath) {
    final items = <WebDavItem>[];

    // 使用更精确的正则表达式来提取信息
    final responseRegExp = RegExp(
      r'<D:response[^>]*>(.*?)</D:response>',
      multiLine: true,
      dotAll: true,
    );

    // 确保基础路径格式统一（以/结尾）
    if (!basePath.endsWith('/')) {
      basePath = '$basePath/';
    }

    // 调试日志：显示收到的XML内容的前200个字符
    debugPrint(
        '解析WebDAV响应，内容开头: ${xml.length > 200 ? "${xml.substring(0, 200)}..." : xml}');
    debugPrint('基础路径: $basePath');

    final responses = responseRegExp.allMatches(xml);
    debugPrint('找到 ${responses.length} 个响应元素');

    for (var response in responses) {
      final responseText = response.group(1)!;

      // 提取 href
      final hrefRegExp = RegExp(r'<D:href>(.*?)</D:href>', dotAll: true);
      final hrefMatch = hrefRegExp.firstMatch(responseText);
      if (hrefMatch == null) continue;

      var href = hrefMatch.group(1)!;

      // 输出原始href内容，帮助调试
      debugPrint('原始href: $href');

      // 统一路径格式，处理URL编码
      href = Uri.decodeComponent(href);

      // 移除服务器前缀路径部分，使其相对于请求的路径
      final serverPrefix = Uri.parse(_serverUrl ?? '').path;
      if (serverPrefix.isNotEmpty && href.startsWith(serverPrefix)) {
        href = href.substring(serverPrefix.length);
      }

      // 确保路径以/开头
      if (!href.startsWith('/')) {
        href = '/$href';
      }

      // 跳过当前目录的引用
      if (href == basePath) {
        debugPrint('跳过当前目录引用: $href');
        continue;
      }

      // 多种方法判断是否为目录
      bool isCollection = false;

      // 方法1: 标准WebDAV目录标识
      final isCollectionRegExp = RegExp(
        r'<D:resourcetype[^>]*>\s*<D:collection/>\s*</D:resourcetype>',
        multiLine: true,
        dotAll: true,
      );
      isCollection = isCollectionRegExp.hasMatch(responseText);

      // 方法2：路径以斜线结尾通常表示目录
      if (!isCollection && href.endsWith('/')) {
        isCollection = true;
        debugPrint('基于路径结尾的斜杠判定为目录: $href');
      }

      // 方法3：检查常见的contenttype标记
      if (!isCollection) {
        final contentTypeRegExp = RegExp(
          r'<D:getcontenttype>(.*?)</D:getcontenttype>',
          dotAll: true,
        );
        final contentTypeMatch = contentTypeRegExp.firstMatch(responseText);
        if (contentTypeMatch != null) {
          final contentType = contentTypeMatch.group(1)!.toLowerCase();
          // 如果内容类型包含directory或collection，视为目录
          if (contentType.contains('directory') ||
              contentType.contains('collection')) {
            isCollection = true;
            debugPrint('基于内容类型判定为目录: $contentType');
          }
        }
      }

      // 获取名称
      String name;
      if (href.endsWith('/')) {
        name = href.substring(0, href.length - 1).split('/').last;
      } else {
        name = href.split('/').last;
      }

      // 如果没有名称，可能是根目录，跳过
      if (name.isEmpty) continue;

      // 添加到结果列表
      final item = WebDavItem(
        path: href,
        name: name,
        isDirectory: isCollection,
      );

      items.add(item);
      debugPrint('已添加项目: $item');
    }

    // 最终结果日志
    debugPrint(
        '共解析出 ${items.length} 个项目，其中目录 ${items.where((item) => item.isDirectory).length} 个');
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
