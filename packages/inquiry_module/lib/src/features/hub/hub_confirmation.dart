import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supplier_core/supplier_core.dart';

/// First-party per-request approval, separate from the publication's business
/// record/contact review. This callback is never sourced from hub/model data.
HubReview reviewHubRequest(BuildContext context) => (preview, cancel) async {
  if (!context.mounted || cancel.isCancelled) return false;
  final request = preview.request;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(request.publishes ? '确认向中心发布' : '确认资料中心请求'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText('${request.method} ${request.destination}'),
                  if (request.body != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      request.publishes
                          ? '将发送以下完整内容并写入公司资料中心：'
                          : '核对预览也会向中心发送以下完整内容：',
                    ),
                    SelectableText(
                      const JsonEncoder.withIndent('  ').convert(request.body),
                    ),
                  ],
                  if (request.publishes)
                    const Text('停止本地操作不会撤回远端写入；结果不明时必须先核验。'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('拒绝'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('允许本次请求'),
            ),
          ],
        ),
      ) ??
      false;
};
