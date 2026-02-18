import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as bindings;
import 'package:lazynote_flutter/core/bindings/frb_generated.dart';

class _WorkspaceContractSmokeApi implements RustLibApi {
  final Map<String, bindings.WorkspaceNodeItem> _nodes = {};

  String? lastListParentNodeId;
  String? lastCreateParentNodeId;
  String? lastCreateName;
  String? lastRenameNodeId;
  String? lastRenameName;
  String? lastMoveNodeId;
  String? lastMoveParentId;
  PlatformInt64? lastMoveTargetOrder;

  @override
  Future<bindings.WorkspaceNodeResponse> crateApiWorkspaceCreateFolder({
    String? parentNodeId,
    required String name,
  }) async {
    lastCreateParentNodeId = parentNodeId;
    lastCreateName = name;

    final nodeId = '00000000-0000-0000-0000-000000000001';
    final node = bindings.WorkspaceNodeItem(
      nodeId: nodeId,
      kind: 'folder',
      parentNodeId: parentNodeId,
      atomId: null,
      displayName: name,
      sortOrder: 0,
    );
    _nodes[nodeId] = node;

    return bindings.WorkspaceNodeResponse(
      ok: true,
      message: 'created',
      node: node,
    );
  }

  @override
  Future<bindings.WorkspaceListChildrenResponse> crateApiWorkspaceListChildren({
    String? parentNodeId,
  }) async {
    lastListParentNodeId = parentNodeId;
    final items = _nodes.values
        .where((node) => node.parentNodeId == parentNodeId)
        .toList(growable: false);
    return bindings.WorkspaceListChildrenResponse(
      ok: true,
      message: 'listed',
      items: items,
    );
  }

  @override
  Future<bindings.WorkspaceActionResponse> crateApiWorkspaceRenameNode({
    required String nodeId,
    required String newName,
  }) async {
    lastRenameNodeId = nodeId;
    lastRenameName = newName;
    final existing = _nodes[nodeId];
    if (existing == null) {
      return const bindings.WorkspaceActionResponse(
        ok: false,
        errorCode: 'node_not_found',
        message: 'node not found',
      );
    }
    _nodes[nodeId] = bindings.WorkspaceNodeItem(
      nodeId: existing.nodeId,
      kind: existing.kind,
      parentNodeId: existing.parentNodeId,
      atomId: existing.atomId,
      displayName: newName,
      sortOrder: existing.sortOrder,
    );
    return const bindings.WorkspaceActionResponse(ok: true, message: 'renamed');
  }

  @override
  Future<bindings.WorkspaceActionResponse> crateApiWorkspaceMoveNode({
    required String nodeId,
    String? newParentId,
    PlatformInt64? targetOrder,
  }) async {
    lastMoveNodeId = nodeId;
    lastMoveParentId = newParentId;
    lastMoveTargetOrder = targetOrder;

    final existing = _nodes[nodeId];
    if (existing == null) {
      return const bindings.WorkspaceActionResponse(
        ok: false,
        errorCode: 'node_not_found',
        message: 'node not found',
      );
    }
    _nodes[nodeId] = bindings.WorkspaceNodeItem(
      nodeId: existing.nodeId,
      kind: existing.kind,
      parentNodeId: newParentId,
      atomId: existing.atomId,
      displayName: existing.displayName,
      sortOrder: targetOrder ?? existing.sortOrder,
    );
    return const bindings.WorkspaceActionResponse(ok: true, message: 'moved');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      'Unexpected API call in workspace smoke test: ${invocation.memberName}',
    );
  }
}

void main() {
  tearDown(() {
    RustLib.dispose();
  });

  test('workspace wrappers cover create/list/rename/move call path', () async {
    final mockApi = _WorkspaceContractSmokeApi();
    RustLib.initMock(api: mockApi);

    final createResponse = await bindings.workspaceCreateFolder(name: 'Inbox');
    expect(createResponse.ok, isTrue);
    final nodeId = createResponse.node?.nodeId;
    expect(nodeId, isNotNull);

    final listResponse = await bindings.workspaceListChildren();
    expect(listResponse.ok, isTrue);
    expect(listResponse.items.length, 1);
    expect(listResponse.items.single.displayName, 'Inbox');

    final renameResponse = await bindings.workspaceRenameNode(
      nodeId: nodeId!,
      newName: 'Inbox-Renamed',
    );
    expect(renameResponse.ok, isTrue);

    final moveResponse = await bindings.workspaceMoveNode(
      nodeId: nodeId,
      newParentId: null,
      targetOrder: 3,
    );
    expect(moveResponse.ok, isTrue);

    final afterResponse = await bindings.workspaceListChildren();
    expect(afterResponse.ok, isTrue);
    expect(afterResponse.items.single.displayName, 'Inbox-Renamed');
    expect(afterResponse.items.single.sortOrder, 3);

    expect(mockApi.lastCreateParentNodeId, isNull);
    expect(mockApi.lastCreateName, 'Inbox');
    expect(mockApi.lastListParentNodeId, isNull);
    expect(mockApi.lastRenameNodeId, nodeId);
    expect(mockApi.lastRenameName, 'Inbox-Renamed');
    expect(mockApi.lastMoveNodeId, nodeId);
    expect(mockApi.lastMoveParentId, isNull);
    expect(mockApi.lastMoveTargetOrder, 3);
  });
}
