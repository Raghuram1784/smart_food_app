import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_food_demo/features/scheduling/schedule_widgets.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';

class SlotRepository implements CommerceRepository {
 @override Future<dynamic> request(String method,String path,[Json? data])async=>{'dates':['2026-11-15','2026-11-16'],'date':'2026-11-15','slots':[{'scheduledDeliveryAt':'2026-11-15T14:30:00.000Z','deliveryWindowStart':'2026-11-15T14:25:00Z','deliveryWindowEnd':'2026-11-15T14:35:00Z'}]};
 @override dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}
void main() {
  test('IST formatting is independent of the device time zone', () {
    expect(
      scheduleTime('2026-11-15T14:30:00Z', date: true),
      '15/11 · 8:00 PM IST',
    );
    expect(
      scheduleWindow({
        'deliveryWindowStart': '2026-11-15T14:25:00Z',
        'deliveryWindowEnd': '2026-11-15T14:35:00Z',
      }),
      '7:55 PM – 8:05 PM IST',
    );
  });
  testWidgets(
    'immediate checkout is default and later requires an available slot',
    (tester) async {
      Json? choice = {};
      await tester.pumpWidget(
        ProviderScope(
          overrides:[commerceRepositoryProvider.overrideWithValue(SlotRepository())],
          child: MaterialApp(
            home: Scaffold(
              body: SchedulePicker(
                restaurantId: 'test',
                onChanged: (v) => choice = v,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Deliver Now'), findsOneWidget);
      expect(find.text('Schedule for Later'), findsOneWidget);
      expect(choice, isEmpty);
      await tester.tap(find.byKey(const ValueKey('schedule-later')));expect(choice,isNull);await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slot-0')));await tester.pumpAndSettle();
      expect(choice?['deliveryMode'],'SCHEDULED');expect(choice?['scheduledDeliveryAt'],'2026-11-15T14:30:00.000Z');
      expect(find.text('7:55 PM – 8:05 PM IST'),findsOneWidget);
      await tester.tap(find.text('Deliver Now'));await tester.pumpAndSettle();expect(choice,isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'scheduled status displays the target and recorded delivery without claiming GPS',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScheduleCard(
              order: {
                'deliveryMode': 'SCHEDULED',
                'status': 'DELIVERED',
                'scheduleIndicator': 'DELIVERED_OUTSIDE_WINDOW',
                'scheduledDeliveryAt': '2026-11-15T14:30:00Z',
                'deliveryWindowStart': '2026-11-15T14:25:00Z',
                'deliveryWindowEnd': '2026-11-15T14:35:00Z',
                'preparationStartAt': '2026-11-15T13:45:00Z',
                'expectedPickupAt': '2026-11-15T14:05:00Z',
                'actualDeliveryAt': '2026-11-15T14:40:00Z',
              },
            ),
          ),
        ),
      );
      expect(find.text('Delivered outside window'), findsOneWidget);
      expect(find.text('7:55 PM – 8:05 PM IST'), findsOneWidget);
      expect(find.textContaining('no live GPS'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
