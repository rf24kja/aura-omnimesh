// lib/transport/bridge_support_stub.dart
//
// Web build of the bridge factory. Light Clients are bridge consumers,
// never bridge hosts, so the factory yields nothing by design.

import '../domain/domain_models.dart';
import '../engine/mesh_sync_engine.dart';
import '../services/services.dart';
import 'bridge_handle.dart';

BridgeHandle? createBridgeServer({
  required IdentitySigner signer,
  required NodeIdentity selfIdentity,
  required MeshSyncEngine engine,
  required LocalMeshTransportService transport,
  required MeshRepository repository,
}) =>
    null;
