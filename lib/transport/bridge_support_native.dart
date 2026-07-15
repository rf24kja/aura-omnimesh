// lib/transport/bridge_support_native.dart
//
// Native (dart:io) build of the bridge factory: wraps CoreNodeBridgeServer
// behind the platform-free BridgeHandle so the composition root stays
// importable on every target.

import 'dart:io';

import '../domain/domain_models.dart';
import '../engine/mesh_sync_engine.dart';
import '../services/services.dart';
import 'bridge_handle.dart';
import 'bridge_server.dart';

BridgeHandle? createBridgeServer({
  required IdentitySigner signer,
  required NodeIdentity selfIdentity,
  required MeshSyncEngine engine,
  required LocalMeshTransportService transport,
  required MeshRepository repository,
}) =>
    _CoreNodeBridgeHandle(CoreNodeBridgeServer(
      signer: signer,
      selfIdentity: selfIdentity,
      engine: engine,
      transport: transport,
      repository: repository,
    ));

class _CoreNodeBridgeHandle implements BridgeHandle {
  _CoreNodeBridgeHandle(this._server);

  final CoreNodeBridgeServer _server;

  @override
  Uri get advertisedEndpoint => _server.advertisedEndpoint;

  @override
  Future<List<Uri>> pairingEndpoints() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    return [
      for (final interface in interfaces)
        for (final address in interface.addresses)
          Uri(scheme: 'ws', host: address.address, port: _server.port),
    ];
  }

  @override
  Future<void> start() => _server.start();

  @override
  Future<void> dispose() => _server.dispose();
}
