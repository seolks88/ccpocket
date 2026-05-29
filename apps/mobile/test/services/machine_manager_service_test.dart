import 'dart:convert';
import 'dart:io';

import 'package:ccpocket/models/machine.dart';
import 'package:ccpocket/services/machine_manager_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return values[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<HttpServer> _startHealthServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    request.response.headers.contentType = ContentType.json;
    if (request.uri.path == '/version') {
      request.response.write(
        jsonEncode({'version': '1.99.2', 'platform': 'test'}),
      );
    } else {
      request.response.write(jsonEncode({'status': 'ok'}));
    }
    request.response.close();
  });
  return server;
}

void main() {
  group('MachineManagerService personal defaults', () {
    test('seeds MacBook and Mac mini when enabled', () async {
      final server = await _startHealthServer();
      addTearDown(server.close);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final manager =
          MachineManagerService(
            prefs,
            _FakeSecureStorage(),
            seedPersonalDefaults: true,
          )..configureBridgeTunnelResolvers(
            httpBaseUrlResolver:
                (machine, {password, promptForPassword}) async =>
                    'http://${server.address.host}:${server.port}',
          );

      await manager.init();

      final machines = manager.currentMachines;
      expect(machines.map((m) => m.name), containsAll(['MacBook', 'Mac mini']));
      expect(manager.findByHostPort('100.84.200.62', 8765)?.sshUsername, 'hon');
      expect(
        manager.findByHostPort('100.97.251.33', 8765)?.sshUsername,
        'kwangsooseol',
      );
      expect(machines.where((m) => m.isFavorite), hasLength(2));
    });

    test('merges defaults without clearing saved credentials', () async {
      final server = await _startHealthServer();
      addTearDown(server.close);
      SharedPreferences.setMockInitialValues({
        'machines_v2': jsonEncode([
          const Machine(
            id: 'existing-mini',
            name: '',
            host: '100.97.251.33',
            port: 8765,
            hasApiKey: true,
            hasCredentials: true,
          ).toJson(),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final manager =
          MachineManagerService(
            prefs,
            _FakeSecureStorage(),
            seedPersonalDefaults: true,
          )..configureBridgeTunnelResolvers(
            httpBaseUrlResolver:
                (machine, {password, promptForPassword}) async =>
                    'http://${server.address.host}:${server.port}',
          );

      await manager.init();

      final mini = manager.findByHostPort('100.97.251.33', 8765)!;
      expect(mini.id, 'existing-mini');
      expect(mini.name, 'Mac mini');
      expect(mini.hasApiKey, isTrue);
      expect(mini.hasCredentials, isTrue);
      expect(mini.sshEnabled, isTrue);
      expect(mini.sshUsername, 'kwangsooseol');
    });
  });
}
