import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/device_memory.dart';
import 'package:test_tiktok/core/gpu_profile.dart';
import 'package:test_tiktok/core/proxy_store.dart';

void main() {
  test('every phone is a Snapdragon phone with a unique id', () {
    expect(GpuProfile.all.length, greaterThanOrEqualTo(40));
    expect(
      GpuProfile.all.map((p) => p.id).toSet(),
      hasLength(GpuProfile.all.length),
    );
    for (final profile in GpuProfile.all) {
      expect(profile.vendor, 'Qualcomm', reason: profile.id);
      expect(profile.renderer, startsWith('Adreno (TM) '), reason: profile.id);
      // Firefox on a real Android phone: the driver's vendor and a
      // bucketed renderer (dom/canvas/SanitizeRenderer.cpp).
      expect(profile.webGlVendor, profile.vendor);
      expect(profile.webGlRenderer, endsWith(', or similar'));
    }
    expect(
      GpuProfile.byId('redmi-note-12').webGlRenderer,
      'Adreno (TM) 650, or similar',
    );
    expect(GpuProfile.byId('redmi-note-12').webGlVendor, 'Qualcomm');
    // Mali phones were dropped; their ids now fall back.
    expect(GpuProfile.isKnown('galaxy-a14'), isFalse);
    expect(GpuProfile.byId('unknown'), GpuProfile.fallback);
    expect(GpuProfile.find(' Samsung Galaxy S23 ')!.id, 'galaxy-s23');
    for (final profile in GpuProfile.all) {
      expect(GpuProfile.other(profile.id).id, isNot(profile.id));
    }
  });

  test('device memory is rounded like Chromium\'s navigator.deviceMemory', () {
    // Android's usable RAM: 3, 4, 6, 8 and 12 GB phones.
    expect(approximatedDeviceMemoryGb(2867), 2);
    expect(approximatedDeviceMemoryGb(3790), 4);
    expect(approximatedDeviceMemoryGb(5734), 4);
    expect(approximatedDeviceMemoryGb(7680), 8);
    expect(approximatedDeviceMemoryGb(11500), 8);
    expect(approximatedDeviceMemoryGb(100), 0.25);
  });

  test('phones are chosen only among those sold with this RAM', () {
    for (final profile in GpuProfile.all) {
      expect(profile.ramGb, isNotEmpty, reason: profile.id);
    }
    expect(GpuProfile.forDevice(), GpuProfile.all);
    final low = GpuProfile.forDevice(4).map((p) => p.id).toSet();
    expect(
      low,
      containsAll([
        'redmi-note-11',
        'redmi-note-12',
        'redmi-10c',
        'galaxy-a23',
        'moto-g62',
      ]),
    );
    expect(low, isNot(contains('galaxy-s23')));
    expect(low, isNot(contains('galaxy-s24-ultra')));
    final high = GpuProfile.forDevice(8).map((p) => p.id).toSet();
    expect(high, containsAll(['galaxy-s23', 'redmi-note-12']));
    expect(high, isNot(contains('redmi-note-11')));
    // Smaller phones than any listed one use the closest tier.
    expect(GpuProfile.forDevice(2), GpuProfile.forDevice(4));
    final random = Random(1);
    for (var i = 0; i < 50; i++) {
      expect(GpuProfile.random(random, 4).fits(4), isTrue);
      final other = GpuProfile.other('redmi-note-12', random, 4);
      expect(other.id, isNot('redmi-note-12'));
      expect(other.fits(4), isTrue);
    }
  });

  test('renderers bucket like Firefox', () {
    for (final (renderer, bucket) in [
      ('Adreno (TM) 750', 'Adreno (TM) 650'),
      ('Adreno (TM) 610', 'Adreno (TM) 650'),
      ('Adreno (TM) 540', 'Adreno (TM) 540'),
      ('Adreno (TM) 642L', 'Adreno (TM) 650'),
      ('Adreno (TM) 430', 'Adreno (TM) 430'),
    ]) {
      expect(firefoxRendererBucket(renderer), bucket, reason: renderer);
    }
    expect(() => firefoxRendererBucket('Mali-G52'), throwsArgumentError);
  });

  group('store', () {
    sqfliteFfiInit();
    late Directory directory;
    late String filename;
    late ProxyStore store;
    ProxyStore openStore() => ProxyStore(
      factory: databaseFactoryFfi,
      databasePath: filename,
      selectUserAgent: () async => 'agent',
    );
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('gpu_profile_');
      filename = path.join(directory.path, 'proxies.db');
      store = openStore();
    });
    tearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });

    test('a new configuration gets a random phone that stays fixed', () async {
      final id = await store.save(
        name: 'A',
        proxy: WebViewProxy.parse('192.0.2.7:8080')!,
      );
      final gpu = (await store.list()).single.gpuProfileId;
      expect(GpuProfile.isKnown(gpu), isTrue);
      // Edits without a GPU and a new proxy keep the same phone.
      await store.save(
        id: id,
        name: 'A',
        proxy: WebViewProxy.parse('192.0.2.9:8080')!,
      );
      await store.close();
      store = openStore();
      expect((await store.list()).single.gpuProfileId, gpu);
      await store.useSaved(id);
      expect((await store.getCurrentProfile())!.gpuProfileId, gpu);

      await store.save(id: id, name: 'A', proxy: null, gpuProfileId: 'pixel-5');
      expect((await store.list()).single.gpuProfile.device, 'Google Pixel 5');
      await expectLater(
        store.save(id: id, name: 'A', proxy: null, gpuProfileId: 'iphone'),
        throwsFormatException,
      );
    });

    test('unregistered configurations get a phone that fits the RAM', () async {
      final unregistered = await store.save(
        name: 'New',
        proxy: null,
        gpuProfileId: 'galaxy-s23',
      );
      final registered = await store.save(
        name: 'Old',
        proxy: WebViewProxy.parse('192.0.2.7:8080')!,
        account: const AccountCredentials(
          email: 'old@example.com',
          password: 'password',
          mailboxPassword: 'mail',
        ),
        statusAccount: AccountStatus.registered,
        gpuProfileId: 'galaxy-s23',
      );
      final fitting = await store.save(
        name: 'Fits',
        proxy: WebViewProxy.parse('192.0.2.8:8080')!,
        gpuProfileId: 'redmi-note-12',
      );
      expect(await store.fitGpuProfilesToDevice(), isEmpty);
      final changed = await store.fitGpuProfilesToDevice(4);
      expect(changed.keys, [unregistered]);
      final gpu = {
        for (final entry in await store.list()) entry.id: entry.gpuProfile,
      };
      expect(gpu[unregistered]!.fits(4), isTrue);
      expect(gpu[unregistered]!.id, changed[unregistered]);
      // A registered account keeps its phone; a fitting one is untouched.
      expect(gpu[registered]!.id, 'galaxy-s23');
      expect(gpu[fitting]!.id, 'redmi-note-12');
    });

    test('v18 configurations each receive a phone', () async {
      await store.save(name: 'A', proxy: null);
      await store.save(name: 'B', proxy: WebViewProxy.parse('192.0.2.8:80')!);
      await store.close();
      final old = await databaseFactoryFfi.openDatabase(filename);
      await old.execute('ALTER TABLE configurations DROP COLUMN gpu_profile');
      await old.setVersion(18);
      await old.close();
      store = openStore();
      final ids = [for (final entry in await store.list()) entry.gpuProfileId];
      expect(ids, hasLength(2));
      expect(ids.every(GpuProfile.isKnown), isTrue);
    });

    test('v19 Mali phones are replaced by Snapdragon phones', () async {
      final kept = await store.save(
        name: 'A',
        proxy: WebViewProxy.parse('192.0.2.7:8080')!,
        gpuProfileId: 'galaxy-s23',
      );
      final mali = await store.save(
        name: 'B',
        proxy: WebViewProxy.parse('192.0.2.8:8080')!,
      );
      await store.close();
      final old = await databaseFactoryFfi.openDatabase(filename);
      await old.update('configurations', {
        'gpu_profile': 'galaxy-a14',
      }, where: 'id = $mali');
      await old.setVersion(19);
      await old.close();
      store = openStore();
      final gpu = {
        for (final entry in await store.list()) entry.id: entry.gpuProfile,
      };
      expect(gpu[kept]!.id, 'galaxy-s23');
      expect(gpu[mali]!.vendor, 'Qualcomm');
      expect(GpuProfile.isKnown(gpu[mali]!.id), isTrue);
    });
  });
}
