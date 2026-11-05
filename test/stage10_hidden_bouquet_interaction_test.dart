import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexusbo/features/secret/about_version_tile.dart';
import 'package:nexusbo/features/secret/bouquet_reveal_overlay.dart';
import 'package:nexusbo/features/secret/secret_tap_controller.dart';
import 'package:nexusbo/features/secret/unlocked_bouquet_badge.dart';
import 'package:nexusbo/features/settings/presentation/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Etapa 10: Interacción Secreta y Animación de Bouquet (3 Taps)', () {
    // -------------------------------------------------------------------------
    // A. Tap 1 -> firstTapHint («Parece que hay algo especial escondido por aquí ...»)
    // -------------------------------------------------------------------------
    test('A. Primer tap retorna outcome firstTapHint y tapCount = 1', () {
      final controller = SecretTapController();

      final outcome = controller.registerTap();
      expect(outcome, SecretTapOutcome.firstTapHint);
      expect(controller.tapCount, 1);
    });

    // -------------------------------------------------------------------------
    // B. Tap 2 -> idle (sin mensajes adicionales)
    // -------------------------------------------------------------------------
    test('B. Segundo tap retorna outcome idle y tapCount = 2', () {
      final controller = SecretTapController();

      controller.registerTap(); // Tap 1
      final outcome2 = controller.registerTap(); // Tap 2

      expect(outcome2, SecretTapOutcome.idle);
      expect(controller.tapCount, 2);
    });

    // -------------------------------------------------------------------------
    // C. Tap 3 -> unlocked y resetea tapCount a 0
    // -------------------------------------------------------------------------
    test('C. Tercer tap retorna outcome unlocked y marca isUnlocked = true', () {
      final controller = SecretTapController();

      controller.registerTap(); // Tap 1
      controller.registerTap(); // Tap 2
      final outcome3 = controller.registerTap(); // Tap 3

      expect(outcome3, SecretTapOutcome.unlocked);
      expect(controller.tapCount, 0);
      expect(controller.isUnlocked, isTrue);
    });

    // -------------------------------------------------------------------------
    // D. Taps posteriores al desbloqueo -> alreadyUnlocked (no vuelve a ejecutar)
    // -------------------------------------------------------------------------
    test('D. Taps posteriores al desbloqueo retornan alreadyUnlocked', () {
      final controller = SecretTapController();

      controller.registerTap(); // 1
      controller.registerTap(); // 2
      controller.registerTap(); // 3 -> unlocked

      final outcome4 = controller.registerTap();
      final outcome5 = controller.registerTap();

      expect(outcome4, SecretTapOutcome.alreadyUnlocked);
      expect(outcome5, SecretTapOutcome.alreadyUnlocked);
      expect(controller.isUnlocked, isTrue);
    });

    // -------------------------------------------------------------------------
    // E. Inicializado con isUnlocked = true -> no re-ejecuta
    // -------------------------------------------------------------------------
    test('E. Controlador con isUnlocked = true retorna immediately alreadyUnlocked', () {
      final controller = SecretTapController(isUnlocked: true);

      final outcome = controller.registerTap();
      expect(outcome, SecretTapOutcome.alreadyUnlocked);
    });

    // -------------------------------------------------------------------------
    // F. Intervalo superior a 2.5s -> reinicia secuencia a tap 1
    // -------------------------------------------------------------------------
    test('F. Pausa superior a la ventana (2.5s) reinicia el contador de taps a 1', () {
      var currentTime = DateTime(2026, 11, 5, 12, 0, 0);
      final controller = SecretTapController(
        timeout: const Duration(milliseconds: 2500),
        nowProvider: () => currentTime,
      );

      // Tap 1
      final outcome1 = controller.registerTap();
      expect(outcome1, SecretTapOutcome.firstTapHint);
      expect(controller.tapCount, 1);

      // Pausa larga de 3 segundos (> 2.5s)
      currentTime = currentTime.add(const Duration(milliseconds: 3000));

      // El siguiente tap debe reiniciar la secuencia y retornar firstTapHint
      final outcomeAfterTimeout = controller.registerTap();
      expect(outcomeAfterTimeout, SecretTapOutcome.firstTapHint);
      expect(controller.tapCount, 1);
    });

    // -------------------------------------------------------------------------
    // G. Estado false -> mini bouquet ausente
    // -------------------------------------------------------------------------
    Widget buildTestView({required bool isUnlocked}) {
      return MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Center(child: Text('Portada de Noticias')),
              if (isUnlocked)
                const Positioned(
                  right: 16,
                  bottom: 16,
                  child: UnlockedBouquetBadge(),
                ),
            ],
          ),
        ),
      );
    }

    testWidgets('G. Estado false: el mini bouquet decorativo no se renderiza en portada', (tester) async {
      await tester.pumpWidget(buildTestView(isUnlocked: false));

      expect(find.byType(UnlockedBouquetBadge), findsNothing);
      expect(find.text('Portada de Noticias'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // H. Estado true -> mini bouquet visible
    // -------------------------------------------------------------------------
    testWidgets('H. Estado true: el mini bouquet decorativo se muestra posicionado', (tester) async {
      await tester.pumpWidget(buildTestView(isUnlocked: true));

      expect(find.byType(UnlockedBouquetBadge), findsOneWidget);
      expect(find.text('Portada de Noticias'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // I. Mini bouquet -> no intercepta interacción
    // -------------------------------------------------------------------------
    testWidgets('I. UnlockedBouquetBadge usa IgnorePointer y permite interactuar con widgets debajo', (tester) async {
      var buttonClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Center(
                  child: ElevatedButton(
                    onPressed: () {
                      buttonClicked = true;
                    },
                    child: const Text('Botón debajo'),
                  ),
                ),
                const Center(
                  child: UnlockedBouquetBadge(),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(UnlockedBouquetBadge), findsOneWidget);
      final ignorePointer = tester.widget<IgnorePointer>(
        find.descendant(
          of: find.byType(UnlockedBouquetBadge),
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(ignorePointer.ignoring, isTrue);

      await tester.tap(find.text('Botón debajo'));
      await tester.pump();

      expect(buttonClicked, isTrue);
    });

    // -------------------------------------------------------------------------
    // J. AboutVersionTile verifica los 3 toques:
    //    1: toast «Parece que hay algo especial escondido por aquí ...»
    //    2: sin mensajes adicionales
    //    3: desbloqueo y animación
    //    Posteriores: no vuelve a ejecutar la animación
    // -------------------------------------------------------------------------
    testWidgets('J. AboutVersionTile responde a 3 taps: toast en tap 1, silencio en tap 2, desbloqueo en tap 3', (tester) async {
      var unlockedCount = 0;
      final controller = SecretTapController();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AboutVersionTile(
                tapController: controller,
                onUnlocked: () {
                  unlockedCount++;
                },
              ),
            ),
          ),
        ),
      );

      final versionFinder = find.text('NexusBO v1.0.0 - Edición Android');
      expect(versionFinder, findsOneWidget);

      // Tap 1: Notificación toast con el mensaje exacto requerido
      await tester.tap(versionFinder);
      await tester.pump();
      expect(
        find.text(kSecretFirstTapHint),
        findsOneWidget,
      );
      expect(unlockedCount, 0);

      // Tap 2: No muestra mensajes adicionales ni desbloquea
      await tester.tap(versionFinder);
      await tester.pump();
      expect(unlockedCount, 0);

      // Tap 3: Ejecuta animación de desbloqueo y callback
      await tester.tap(versionFinder);
      await tester.pump();
      expect(unlockedCount, 1);

      BouquetRevealOverlay.dismiss();
      await tester.pump();

      // Tap 4: Toques posteriores no vuelven a ejecutar la animación
      await tester.tap(versionFinder);
      await tester.pump();
      expect(unlockedCount, 1); // No incrementó
    });

    // -------------------------------------------------------------------------
    // K. Si ya está desbloqueado previamente en preferencias, no re-ejecuta
    // -------------------------------------------------------------------------
    testWidgets('K. Si ya está desbloqueado, AboutVersionTile ignora taps y no vuelve a animar', (tester) async {
      var unlockedTriggered = false;
      final controller = SecretTapController(isUnlocked: true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            easterEggUnlockedProvider.overrideWithValue(true),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AboutVersionTile(
                tapController: controller,
                onUnlocked: () {
                  unlockedTriggered = true;
                },
              ),
            ),
          ),
        ),
      );

      final versionFinder = find.text('NexusBO v1.0.0 - Edición Android');
      expect(versionFinder, findsOneWidget);

      await tester.tap(versionFinder);
      await tester.pump();

      expect(unlockedTriggered, isFalse);
      expect(find.text(kSecretFirstTapHint), findsNothing);
    });
  });
}
