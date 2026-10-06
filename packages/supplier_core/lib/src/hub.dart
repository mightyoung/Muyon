import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ai_runtime.dart';
import 'hub_channel.dart';
export 'hub_channel.dart';

import 'quotation.dart';
import 'store.dart';
import 'values.dart';

// The optional company hub (services/supplier_hub): colleagues publish chosen
// suppliers and quotations there and search what others published. Nothing
// here runs unless a hub address is configured, and nothing is sent without
// the person confirming the exact records first.

class HubException implements Exception {
  HubException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A hub address as typed: http(s), a host, nothing after the path.
Uri parseHubAddress(String text) {
  final t = text.trim().replaceFirst(RegExp(r'/+$'), '');
  final u = Uri.tryParse(t);
  if (u == null ||
      !(u.scheme == 'http' || u.scheme == 'https') ||
      u.host.isEmpty ||
      u.userInfo.isNotEmpty ||
      u.hasQuery ||
      u.hasFragment) {
    throw const FormatException(
      '中心地址应类似 https://hub.example.com 或 http://127.0.0.1:8080',
    );
  }
  return u;
}

/// Plain HTTP to another machine: a token would cross the network readable.
bool hubAddressIsPlainRemote(Uri u) {
  if (u.scheme != 'http') return false;
  if (u.host == 'localhost') return false;
  final ip = InternetAddress.tryParse(u.host);
  return ip == null || !ip.isLoopback;
}

/// One published supplier or quotation as the hub lists it.
class HubSummary {
  HubSummary.fromJson(Map<String, Object?> j)
    : origin = j['origin']! as String,
      publicationId = j['publication_id']! as String,
      revision = j['revision']! as int,
      withdrawn = j['withdrawn'] == true,
      kind = j['kind']! as String,
      title = j['title'] as String? ?? '',
      rootId = j['root_id']! as String,
      context = (j['context'] as Map?)?.cast<String, Object?>() ?? const {};
  final String origin, publicationId, kind, title, rootId;
  final int revision;
  final bool withdrawn;
  final Map<String, Object?> context;
}

class HubClient {
  HubClient(
    this.base, {
    this.token,
    this.timeout = const Duration(seconds: 20),
    this.hosted = false,
    this.authority,
    this.review,
    this.journal,
    this.validateSession,
    AiCancellation? cancellation,
    HubTransport? transport,
  }) : cancellation = cancellation ?? AiCancellation(),
       transport = transport ?? _native;
  final bool hosted;
  final HubAuthority? authority;
  final HubReview? review;
  final HubPublicationJournal? journal;
  final void Function()? validateSession;
  final AiCancellation cancellation;
  final HubTransport transport;
  String? _origin;

  void _check() {
    if (base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        base.host.isEmpty ||
        !['http', 'https'].contains(base.scheme)) {
      throw HubException('中心地址不合法；凭据只能从安全存储传入');
    }
    cancellation.check();
    validateSession?.call();
    if (hosted && (authority == null || journal == null)) {
      throw HubException('宿主未提供资料中心授权通道或发布日志');
    }
  }

  final Uri base;
  final String? token;
  final Duration timeout;

  static const _maxResponse = 8 * 1024 * 1024;

  Future<Map<String, Object?>> status() async {
    final result = (await _send('GET', '/v1/status'))!;
    _origin = result['center_id'] as String?;
    return result;
  }

  Future<List<HubSummary>> search({
    String q = '',
    String? kind,
    bool includeWithdrawn = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final r = await _send(
      'GET',
      '/v1/publications',
      query: {
        'q': q.trim(),
        'kind': ?kind,
        if (includeWithdrawn) 'include_withdrawn': 'true',
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    return [
      for (final x in (r!['items'] as List? ?? const []))
        HubSummary.fromJson((x as Map).cast()),
    ];
  }

  /// The latest revision, or null when the hub has never seen it.
  Future<Map<String, Object?>?> publication(String origin, String id) =>
      _send('GET', '/v1/publications/$origin/$id', missingIsNull: true);

  Future<List<Map<String, Object?>>> history(String origin, String id) async {
    final r = await _send(
      'GET',
      '/v1/publications/$origin/$id/history',
      query: {'limit': '20'},
    );
    return [
      for (final x in (r!['items'] as List? ?? const []))
        (x as Map).cast<String, Object?>(),
    ];
  }

  /// Validates without writing.
  Future<void> preview(Map<String, Object?> draft) async {
    await _send('POST', '/v1/publications/preview', body: draft);
  }

  Future<Map<String, Object?>> publish(
    Map<String, Object?> draft, {
    String? origin,
  }) async {
    // Freeze before the first asynchronous boundary, including approval.
    final frozen =
        HubRequest('POST', base, draft).body! as Map<String, Object?>;
    _check();
    String? attempt;
    var sent = false;
    final log = journal;
    try {
      if (log != null) {
        final boundOrigin = origin ?? _origin;
        if (boundOrigin == null || boundOrigin != _origin)
          throw HubException('请先核对中心身份和发布版本');
        final digest = await hubDigest(frozen);
        _check();
        final prior = log.read(
          base.toString(),
          frozen['publication_id']! as String,
        );
        if (prior?['state'] == 'applied' &&
            prior?['origin'] == boundOrigin &&
            prior?['payload_digest'] == digest) {
          final actual = await publication(
            boundOrigin,
            frozen['publication_id']! as String,
          );
          _check();
          if (actual != null &&
              actual['origin'] == boundOrigin &&
              await hubDigest({
                    for (final key in const [
                      'publication_id',
                      'revision',
                      'withdrawn',
                      'root',
                      'records',
                    ])
                      key: actual[key],
                  }) ==
                  digest) {
            _check();
            return {'revision': prior!['revision'], 'already_applied': true};
          }
          throw HubException('历史发布已完成，但中心当前内容已变化；请重新核对，不会重复发送旧版本');
        }
        attempt = await log.reserve(
          base.toString(),
          boundOrigin,
          frozen,
          digest,
        );
        _check();
      }
      final result = (await _send(
        'POST',
        '/v1/publications',
        body: frozen,
        beforeSend: () => sent = true,
      ))!;
      if (result['revision'] != frozen['revision']) {
        throw HubException('中心未返回匹配的发布版本');
      }
      _check();
      if (attempt != null) await log!.applied(attempt);
      return result;
    } catch (error) {
      if (attempt != null && !sent) {
        try {
          await log!.noSend(attempt);
        } catch (_) {
          throw HubException('本次未发送，但本地发布日志未能确认；请重新核验');
        }
      }
      if (sent && log != null) {
        throw HubException('发布结果尚未确认，可能已写入中心。请核验中心状态；取消不代表远端撤回。');
      }
      if (error is HubException) rethrow;
      throw HubException('本次发布未发送；本地记录或授权不可用');
    }
  }

  /// A query is separately reviewed and recorded. Absence is NOT proof that
  /// an earlier in-flight write cannot still commit; no unsafe retry unlock.
  Future<bool> reconcile(String id) async {
    _check();
    final log = journal;
    final attempt = log?.read(base.toString(), id);
    final elsewhere = log?.unresolved(id);
    if (elsewhere != null && elsewhere['endpoint'] != base.toString()) {
      throw HubException(
        '此资料在 ${elsewhere['endpoint']} 仍有待确认发布，请恢复原中心配置并核验，不能换地址绕过重试限制',
      );
    }
    if (attempt == null || attempt['state'] == 'applied') return true;
    final remote = await publication(attempt['origin']! as String, id);
    _check();
    if (remote != null &&
        remote['origin'] == attempt['origin'] &&
        remote['publication_id'] == id &&
        remote['revision'] == attempt['revision']) {
      final business = {
        for (final key in const [
          'publication_id',
          'revision',
          'withdrawn',
          'root',
          'records',
        ])
          key: remote[key],
      };
      if (await hubDigest(business) == attempt['payload_digest']) {
        _check();
        await log!.applied(attempt['attempt_id']! as String);
        return true;
      }
    }
    if (remote != null) await log!.conflict(attempt['attempt_id']! as String);
    throw HubException(
      remote == null
          ? '中心暂未查到该发布，但先前请求仍可能晚到；保持阻止重试，需中心提供终态凭证。'
          : '中心内容与待确认发布不同；保持阻止重试，需核对冲突并取得先前请求终态。',
    );
  }

  Future<Map<String, Object?>?> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool missingIsNull = false,
    void Function()? beforeSend,
  }) async {
    final uri = base.replace(path: '${base.path}$path', queryParameters: query);
    final frozen = HubRequest(method, uri, body);
    try {
      _check();
      if (hubAddressIsPlainRemote(base)) {
        throw HubException('远程资料中心必须使用 HTTPS，避免资料和令牌明文传输');
      }
      Future<Map<String, Object?>?> operation(void Function() guard) async {
        guard();
        final response = await cancellation.wait(
          transport(
            frozen,
            token,
            timeout,
            cancellation,
            guard,
            beforeSend ?? () {},
          ),
        );
        guard();
        if (response.bytes.length > _maxResponse)
          throw HubException('中心返回的数据过大');
        if (missingIsNull && response.statusCode == 404) return null;
        Map<String, Object?>? json;
        try {
          final decoded = jsonDecode(utf8.decode(response.bytes));
          if (decoded is Map) json = decoded.cast<String, Object?>();
        } on FormatException {
          json = null;
        }
        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (json == null) throw HubException('中心返回的内容无法识别，请确认地址指向公司资料中心');
          if (frozen.publishes &&
              json['revision'] != (frozen.body as Map)['revision']) {
            throw HubException('中心未返回匹配的发布版本');
          }
          return json;
        }
        throw HubException(_failure(response.statusCode, json));
      }

      return authority == null
          ? await operation(_check)
          : await authority!.run(
              request: frozen,
              review: review,
              cancellation: cancellation,
              validateSession: _check,
              operation: operation,
            );
    } on HubException {
      rethrow;
    } catch (_) {
      // Transport and provider exceptions can contain request data or secrets.
      throw HubException('资料中心请求未完成或授权已失效，请核对连接和授权');
    }
  }

  static Future<HubResponse> _native(
    HubRequest frozen,
    String? token,
    Duration timeout,
    AiCancellation cancel,
    void Function() guard,
    void Function() beforeSend,
  ) async {
    var active = true;
    final authorityGuard = guard;
    void check() {
      if (!active) throw HubException('资料中心请求已结束');
      authorityGuard();
    }

    final client = HttpClient()
      ..connectionTimeout = timeout
      ..findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      check();
      final addresses = await cancel.wait(InternetAddress.lookup(uri.host));
      check();
      final address = addresses.first;
      final task = uri.scheme == 'https'
          ? await SecureSocket.startConnect(address, uri.port)
          : await Socket.startConnect(address, uri.port);
      final detach = cancel.onCancel(task.cancel);
      unawaited(
        task.socket.then<void>(
          (_) => detach(),
          onError: (Object _, StackTrace __) {
            detach();
          },
        ),
      );
      return task;
    };
    final detach = cancel.onCancel(() => client.close(force: true));
    try {
      Future<HubResponse> exchange() async {
        check();
        final request = await cancel.wait(
          client.openUrl(frozen.method, frozen.destination),
        );
        check();
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        if (token != null && token.isNotEmpty) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
        if (frozen.encodedBody != null)
          request.headers.contentType = ContentType.json;
        check();
        beforeSend();
        if (frozen.encodedBody != null)
          request.add(utf8.encode(frozen.encodedBody!));
        check();
        final response = await cancel.wait(request.close());
        check();
        final bytes = <int>[];
        await for (final chunk in response) {
          check();
          bytes.addAll(chunk);
          if (bytes.length > _maxResponse) throw HubException('中心返回的数据过大');
        }
        check();
        return HubResponse(response.statusCode, bytes);
      }

      return await cancel.wait(exchange().timeout(timeout));
    } finally {
      active = false;
      detach();
      client.close(force: true);
    }
  }

  static String _failure(int status, Map<String, Object?>? json) {
    final code = json?['error'], message = json?['message'];
    return switch (status) {
      401 => '访问令牌不对或没有填写',
      403 when code == 'local_origin_required' =>
        '这个中心只接受本机访问；从其他电脑连接需要中心配置访问令牌',
      403 => '中心拒绝访问（HTTP 403）',
      404 => '中心没有这份资料',
      409 => '中心已有其他人更新的版本，请重新发布一次',
      422 => '中心拒绝了这份资料：${message ?? code ?? '格式不符合要求'}',
      413 => '资料超过中心的大小上限',
      >= 500 => '公司资料中心暂时不可用，请稍后再试',
      _ => '中心返回错误（HTTP $status）',
    };
  }
}

const _hubTypes = {
  'supplier',
  'contact',
  'product',
  'quotation',
  'project',
  'project_item',
  'inquiry',
};

/// A publication of one supplier or quotation and everything it references,
/// as the hub requires. Contacts of a supplier go only when asked for:
/// they are people's phone numbers. No change log, attachments or unrelated
/// records; at most 256 records and 1 MiB.
Map<String, Object?> buildHubPublication(
  Store store, {
  required String type,
  required String id,
  required String publicationId,
  required int revision,
  bool withdrawn = false,
  bool includeContacts = false,
}) {
  if (!['supplier', 'quotation'].contains(type)) {
    throw ArgumentError('首版只支持 supplier 或 quotation 根记录');
  }
  requireUuid(id, 'entity_id');
  requireUuid(publicationId, 'publication_id');
  if (revision < 1 || revision > 2147483647) {
    throw ArgumentError('发布版本必须为 1..2147483647');
  }
  final records = <Map<String, Object?>>[];
  final seen = <String>{};
  final pending = [(type, id)];
  if (type == 'supplier' && includeContacts) {
    for (final r in store.db.select(
      "SELECT id FROM contact WHERE deleted = 0 "
      "AND json_extract(data,'\$.supplier_id') = ? ORDER BY id",
      [id],
    )) {
      pending.add(('contact', r['id'] as String));
    }
  }
  store.db.execute('BEGIN');
  try {
    while (pending.isNotEmpty) {
      final (kind, entityId) = pending.removeLast();
      if (!seen.add('$kind:$entityId')) continue;
      if (!_hubTypes.contains(kind) || seen.length > 256) {
        throw StateError('超出首版支持的实体类型或 256 条引用上限');
      }
      final record = store.get(kind, entityId);
      if (record == null || record.deleted) {
        throw StateError('记录不存在或已删除：$kind/$entityId');
      }
      final data = validatePayload(kind, record.data);
      if (kind == 'quotation' &&
          ((data['attachment_ids'] as List?)?.isNotEmpty ?? false)) {
        throw StateError('首版暂不传输附件；不能静默丢弃此报价的附件');
      }
      if (kind == 'product' &&
          ((data['source_attachment_ids'] as List?)?.isNotEmpty ?? false)) {
        throw StateError('首版暂不传输附件；不能静默丢弃此物料的来源附件');
      }
      records.add({
        'entity_type': kind,
        'entity_id': entityId,
        'source_version': record.version,
        'data': data,
      });
      for (final ref
          in (references[kind] ?? const <String, String>{}).entries) {
        if (data[ref.key] case final String referencedId) {
          pending.add((ref.value, referencedId));
        }
      }
      for (final ref
          in (listReferences[kind] ?? const <String, String>{}).entries) {
        for (final referencedId in (data[ref.key] as List?) ?? const []) {
          pending.add((ref.value, referencedId as String));
        }
      }
    }
    records.sort(
      (a, b) => '${a['entity_type']}:${a['entity_id']}'.compareTo(
        '${b['entity_type']}:${b['entity_id']}',
      ),
    );
    final result = <String, Object?>{
      'publication_id': publicationId,
      'revision': revision,
      'withdrawn': withdrawn,
      'root': {'entity_type': type, 'entity_id': id},
      'records': records,
    };
    if (utf8.encode(jsonEncode(result)).length > 1024 * 1024) {
      throw StateError('发布内容超过首版 1 MiB 上限');
    }
    store.db.execute('COMMIT');
    return result;
  } catch (_) {
    store.db.execute('ROLLBACK');
    rethrow;
  }
}

/// What publishing one record would send, decided against the hub's
/// current copy: a record is published under its own id, so republishing
/// after an edit becomes the next revision instead of a second entry.
class HubDraft {
  HubDraft(
    Map<String, Object?> draft, {
    required this.upToDate,
    required this.previous,
    this.origin,
  }) : draft = HubRequest('POST', Uri(), draft).body! as Map<String, Object?>;
  final Map<String, Object?> draft;
  final String? origin;

  /// The hub already has the complete frozen business content.
  final bool upToDate;

  /// The hub's latest revision, 0 when never published.
  final int previous;

  List<Map<String, Object?>> get records =>
      (draft['records']! as List).cast<Map<String, Object?>>();
}

Future<HubDraft> prepareHubPublication(
  HubClient client,
  Store store, {
  required String type,
  required String id,
  bool includeContacts = false,
}) async {
  final center = (await client.status())['center_id'];
  if (center is! String) throw HubException('中心状态缺少中心编号，请确认地址指向公司资料中心');
  await client.reconcile(id);
  final current = await client.publication(center, id);
  Map<String, Object?> build(int revision) => buildHubPublication(
    store,
    type: type,
    id: id,
    publicationId: id,
    revision: revision,
    includeContacts: includeContacts,
  );
  final previous = (current?['revision'] as int?) ?? 0;
  final fresh = build(previous + 1);
  final same =
      current != null &&
      current['origin'] == center &&
      current['withdrawn'] != true &&
      hubCanonical({
            for (final key in const [
              'publication_id',
              'revision',
              'withdrawn',
              'root',
              'records',
            ])
              key: current[key],
          }) ==
          hubCanonical(build(previous));
  if (!same) await client.preview(fresh);
  return HubDraft(
    same ? build(previous) : fresh,
    upToDate: same,
    previous: previous,
    origin: center,
  );
}

class HubResponse {
  HubResponse(this.statusCode, this.bytes);
  final int statusCode;
  final List<int> bytes;
}

typedef HubTransport = Future<HubResponse> Function(
  HubRequest request,
  String? token,
  Duration timeout,
  AiCancellation cancellation,
  void Function() checkBeforeEffect,
  void Function() beforeSend,
);
