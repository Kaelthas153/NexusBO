import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexusbo/features/secret/about_version_tile.dart';
import 'package:nexusbo/features/secret/bouquet_reveal_overlay.dart';
import 'package:nexusbo/features/secret/secret_tap_controller.dart';
import 'package:nexusbo/features/secret/unlocked_bouquet_badge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Etapa 10: Interacción Secreta y Animación de Bouquet', () {
    // -------------------------------------------------------------------------
    // A. 1 a 4 taps -> no desbloquea; no mensaje
    // -------------------------------------------------------------------------
    test('A. 1 a 4 taps consecutivos retornan outcome idle y no desbloquean', () {
      final controller = SecretTapController();

      for (var i = 1; i <= 4; i++) {
        final outcome = controller.registerTap();
        expect(outcome, SecretTapOutcome.idle);
        expect(controller.tapCount, i);
      }
    });

    // -------------------------------------------------------------------------
    // B. Tap 5 -> mensaje de 2 pasos
    // -------------------------------------------------------------------------
    test('B. Quinto tap retorna outcome twoStepsRemaining', () {
      final controller = SecretTapController();

      for (var i = 1; i <= 4; i++) {
        controller.registerTap();
      }

      final outcome = controller.registerTap();
      expect(outcome, SecretTapOutcome.twoStepsRemaining);
      expect(controller.tapCount, 5);
    });

    // -------------------------------------------------------------------------
    // C. Tap 6 -> mensaje de 1 paso
    // -------------------------------------------------------------------------
    test('C. Sexto tap retorna outcome oneStepRemaining', () {
      final controller = SecretTapController();

      for (var i = 1; i <= 5; i++) {
        controller.registerTap();
      }

      final outcome = controller.registerTap();
      expect(outcome, SecretTapOutcome.oneStepRemaining);
      expect(controller.tapCount, 6);
    });

    // -------------------------------------------------------------------------
    // D. Tap 7 -> estado persistido true y desbloqueo
    // -------------------------------------------------------------------------
    test('D. Séptimo tap retorna outcome unlocked y reinicia el contador interno', () {
      final controller = SecretTapController();

      for (var i = 1; i <= 6; i++) {
        controller.registerTap();
      }

      final outcome = controller.registerTap();
      expect(outcome, SecretTapOutcome.unlocked);
      // El contador se resetea para permitir una futura secuencia completa
      expect(controller.tapCount, 0);
    });

    // -------------------------------------------------------------------------
    // E. Intervalo demasiado largo -> contador reiniciado
    // -------------------------------------------------------------------------
    test('E. Pausa superior a la ventana (2.5s) reinicia el contador de taps a 1', () {
      var currentTime = DateTime(2026, 10, 31, 12, 0, 0);
      final controller = SecretTapController(
        timeout: const Duration(milliseconds: 2500),
        nowProvider: () => currentTime,
      );

      // 4 taps rápidos (100ms entre cada uno)
      for (var i = 1; i <= 4; i++) {
        currentTime = currentTime.add(const Duration(milliseconds: 100));
        final outcome = controller.registerTap();
        expect(outcome, SecretTapOutcome.idle);
      }
      expect(controller.tapCount, 4);

      // Pausa larga de 3 segundos (> 2.5s timeout)
      currentTime = currentTime.add(const Duration(milliseconds: 3000));

      // El siguiente tap debe reiniciar el contador a 1 y seguir en idle
      final outcomeAfterTimeout = controller.registerTap();
      expect(outcomeAfterTimeout, SecretTapOutcome.idle);
      expect(controller.tapCount, 1);
    });

    // -------------------------------------------------------------------------
    // F. Estado false -> mini bouquet ausente
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

    testWidgets('F. Estado false: el mini bouquet decorativo no se renderiza en portada', (tester) async {
      await tester.pumpWidget(buildTestView(isUnlocked: false));

      expect(find.byType(UnlockedBouquetBadge), findsNothing);
      expect(find.text('Portada de Noticias'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // G. Estado true -> mini bouquet visible
    // -------------------------------------------------------------------------
    testWidgets('G. Estado true: el mini bouquet decorativo se muestra posicionado', (tester) async {
      await tester.pumpWidget(buildTestView(isUnlocked: true));

      expect(find.byType(UnlockedBouquetBadge), findsOneWidget);
      expect(find.text('Portada de Noticias'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // H. Mini bouquet -> no intercepta interacción
    // -------------------------------------------------------------------------
    testWidgets('H. UnlockedBouquetBadge usa IgnorePointer y permite interactuar con widgets debajo', (tester) async {
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
                // Superponer el badge directamente sobre el botón
                const Center(
                  child: UnlockedBouquetBadge(),
                ),
              ],
            ),
          ),
        ),
      );

      // Confirmar presencia del badge y del IgnorePointer
      expect(find.byType(UnlockedBouquetBadge), findsOneWidget);
      final ignorePointer = tester.widget<IgnorePointer>(
        find.descendant(
          of: find.byType(UnlockedBouquetBadge),
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(ignorePointer.ignoring, isTrue);

      // Pulsar sobre el centro donde se superpone el badge
      await tester.tap(find.text('Botón debajo'));
      await tester.pump();

      // El evento debe traspasar el IgnorePointer y ejecutar el callback
      expect(buttonClicked, isTrue);
    });

    // -------------------------------------------------------------------------
    // I. AboutVersionTile dispara feedbacks visuales en taps 5, 6 y 7
    // -------------------------------------------------------------------------
    testWidgets('I. AboutVersionTile muestra SnackBar en taps 5 y 6, y ejecuta callback en tap 7', (tester) async {
      var unlockedTriggered = false;
      final controller = SecretTapController();

      await tester.pumpWidget(
        ProviderScope(
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

      final versionFinder = find.text('Versión 1.0.0');
      expect(versionFinder, findsOneWidget);

      // Taps 1 a 4: sin snackbar
      for (var i = 1; i <= 4; i++) {
        await tester.tap(versionFinder);
        await tester.pump();
        expect(find.byType(SnackBar), findsNothing);
      }

      // Tap 5: 2 pasos
      await tester.tap(versionFinder);
      await tester.pump();
      expect(find.text('Estás a 2 pasos de desbloquear un secreto'), findsOneWidget);

      // Tap 6: 1 paso
      await tester.tap(versionFinder);
      await tester.pump();
      expect(find.text('Estás a 1 paso de desbloquear un secreto'), findsOneWidget);

      // Tap 7: desbloqueo
      await tester.tap(versionFinder);
      await tester.pump();
      expect(unlockedTriggered, isTrue);

      BouquetRevealOverlay.dismiss();
      await tester.pump();
    });
  });
}
