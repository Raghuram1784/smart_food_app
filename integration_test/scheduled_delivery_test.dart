import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:smart_food_demo/app.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/auth/auth_provider.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';
import 'package:smart_food_demo/features/scheduling/schedule_widgets.dart';
void main(){
 final binding=IntegrationTestWidgetsFlutterBinding.ensureInitialized();
 testWidgets('Samsung scheduled checkout, timed kitchen release, rider invitation and OTP',(tester)async{
  const base=String.fromEnvironment('API_BASE_URL');const password=String.fromEnvironment('F3_PASSWORD');const rid=String.fromEnvironment('F3_RESTAURANT');const dish=String.fromEnvironment('F3_DISH');
  const emails={'customer':String.fromEnvironment('F3_CUSTOMER_EMAIL'),'owner':String.fromEnvironment('F3_OWNER_EMAIL'),'rider':String.fromEnvironment('F3_RIDER_EMAIL')};
  final clients=<String,Dio>{};for(final role in emails.keys){final d=Dio(BaseOptions(baseUrl:base));final auth=(await d.post('auth/login',data:{'email':emails[role],'password':password})).data['data'];d.options.headers['Authorization']='Bearer ${auth['session']['token']}';clients[role]=d;}
  final customer=clients['customer']!,owner=clients['owner']!,rider=clients['rider']!;
  final address=(await customer.post('addresses',data:{'label':'Demo office','recipientName':'NeuroX Demo','contactNumber':'9000000000','addressLine1':'1 Synthetic Test Lane','localityId':'madhapur','postalCode':'500081','isDefault':true})).data['data'];
  var cart=(await customer.get('cart')).data['data'];cart=(await customer.post('cart/items',data:{'restaurantId':rid,'menuItemId':dish,'quantity':1,'addOnIds':[],'expectedVersion':cart['version']})).data['data'];
  final quote=Json.from((await customer.post('cart/quote',data:{'addressId':address['id'],'expectedVersion':cart['version']})).data['data']);
  await SecureTokenStorage().delete();final prefs=await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(overrides:[preferencesProvider.overrideWithValue(prefs)],child:const FoodApp()));await tester.pumpAndSettle();
  final container=ProviderScope.containerOf(tester.element(find.byType(FoodApp)));final router=GoRouter.of(tester.element(find.byType(Scaffold).first));
  Future<void> login(String role,String path)async{await container.read(authProvider.future);if(container.read(authProvider).asData?.value!=null)await container.read(authProvider.notifier).logout();await container.read(authProvider.notifier).login(emails[role]!,password);router.go(path);await tester.pumpAndSettle();}
  Future<void> waitFor(Finder finder)async{for(var i=0;i<300;i++){await tester.pump(const Duration(milliseconds:100));if(finder.evaluate().isNotEmpty)return;}expect(finder,findsWidgets);}
  Future<void> shot(String name)async{await tester.pumpAndSettle();await binding.takeScreenshot(name);}
  Future<void> pause()async{await tester.runAsync(()=>Future<void>.delayed(const Duration(seconds:1)));await tester.pump();}
  Future<Json> transition(Dio client,String scope,String id,String action)async{
   for(var i=0;i<180;i++){
    final current=(await client.get('operations/$scope/orders/$id')).data['data'];
    final response=await client.post('operations/$scope/orders/$id/$action',data:{'expectedVersion':current['version']},options:Options(validateStatus:(_)=>true));
    if(response.statusCode==200)return Json.from(response.data['data']);
    expect(response.statusCode,409);await pause();
   }
   throw StateError('Timed transition did not become available: $action');
  }
  await login('customer','/cart');router.go('/checkout',extra:{...quote,'addressId':address['id']});await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('schedule-later')));await waitFor(find.byKey(const ValueKey('slot-0')));await tester.pumpAndSettle();await tester.tap(find.byKey(const ValueKey('slot-0')));await tester.pumpAndSettle();
  await binding.convertFlutterSurfaceToImage();await tester.pump();await shot('01-samsung-slot-selection');
  await tester.tap(find.byKey(const ValueKey('place-order')));await tester.pumpAndSettle();await waitFor(find.text('Order confirmation'));
  var order=Json.from(((await customer.get('orders')).data['data']['items'] as List).first);final id=order['id'];expect(order['deliveryMode'],'SCHEDULED');await shot('02-samsung-booking-confirmed');
  final events=<String>[];final connected=Completer<void>();final token=customer.options.headers['Authorization'].toString().substring(7);
  final socket=io.io(Uri.parse(base).origin,io.OptionBuilder().setTransports(['websocket']).enableForceNew().disableAutoConnect().setAuth({'token':token}).build());
  socket.onConnect((_){if(!connected.isCompleted)connected.complete();});socket.on('order.updated',(e){if(e['orderId']==id)events.add(e['eventType'] as String);});socket.connect();await tester.runAsync(()=>connected.future.timeout(const Duration(seconds:15)));
  try{
   await login('owner','/inbox/$rid?tab=scheduled');await waitFor(find.textContaining('Scheduled Orders'));await shot('03-samsung-owner-scheduled');
   // Owner action is authorized through the production REST transition; the screen refetches via Socket.IO.
   order=await transition(owner,'restaurant',id,'accept');
   final early=await owner.post('operations/restaurant/orders/$id/start-preparing',data:{'expectedVersion':order['version']},options:Options(validateStatus:(_)=>true));expect(early.statusCode,409);
   order=await transition(owner,'restaurant',id,'start-preparing');
   order=await transition(owner,'restaurant',id,'ready');
   await rider.post('rider/presence/online',data:{});
   for(var i=0;i<180;i++){final offers=(await rider.get('operations/delivery/offers')).data['data']['offers'] as List;if(offers.any((o)=>o['orderId']==id))break;await pause();}
   await login('rider','/deliveries');await waitFor(find.text('New Delivery Request'));await shot('04-samsung-timed-rider-invitation');// The dialog sits above the offer card; tap its own button (the card's identical label is obscured).
   // Other synthetic invitations may be pending in the shared dev DB: decline those, accept only this order.
   final accept=find.byKey(const ValueKey('offer-dialog-accept'));
   for(var attempt=0;attempt<8;attempt++){
    await waitFor(accept);
    final ours=find.descendant(of:find.byType(AlertDialog),matching:find.text('Order: ${order['orderNumber']}')).evaluate().isNotEmpty;
    if(ours){await tester.tap(accept);await tester.pumpAndSettle();break;}
    await tester.tap(find.descendant(of:find.byType(AlertDialog),matching:find.text('Decline')));await tester.pumpAndSettle();await pause();
   }
   String? notice;for(var i=0;i<30&&notice==null;i++){await tester.pump(const Duration(milliseconds:100));final bar=find.descendant(of:find.byType(SnackBar),matching:find.byType(Text));if(bar.evaluate().isNotEmpty)notice=(tester.widget<Text>(bar.first).data);}
   debugPrint('F3_ACCEPT_NOTICE: ${notice ?? 'none'}');
   var assigned=false;for(var i=0;i<40&&!assigned;i++){await pause();final data=(await rider.get('operations/delivery/orders')).data['data'];assigned=(data['items'] as List).any((o)=>o['id']==id);}
   expect(assigned,isTrue,reason:'rider accepted the invitation from the UI (app said: ${notice ?? 'nothing'})');
   order=Json.from((await rider.get('operations/delivery/orders/$id')).data['data']);expect(order['assignment'],isNotNull);
   order=await transition(rider,'delivery',id,'pickup');
   order=await transition(rider,'delivery',id,'out-for-delivery');
   final pin=(await customer.get('orders/$id/handover')).data['data']['pin'];
   order=Json.from((await rider.post('operations/delivery/orders/$id/complete-handover',data:{'pin':pin,'expectedVersion':order['version']})).data['data']);expect(order['status'],'DELIVERED');expect(order['actualDeliveryAt'],isNotNull);
   await login('customer','/orders/$id');await waitFor(find.byType(ScheduleCard));await shot('05-samsung-delivered-window');
   expect(order['scheduleIndicator'],'DELIVERED_WITHIN_WINDOW');expect(events.contains('SCHEDULE_PREPARATION_DUE'),isTrue);expect(events.contains('ORDER_DELIVERED'),isTrue);
   binding.reportData={...?binding.reportData,'orderId':id,'orderNumber':order['orderNumber'],'device':'Samsung S23 Ultra SM-S918B','scheduledDeliveryAt':order['scheduledDeliveryAt'],'actualDeliveryAt':order['actualDeliveryAt'],'indicator':order['scheduleIndicator'],'events':events,'earlyPreparationStatus':early.statusCode,'flow':'UI slot selection and checkout; authorized API kitchen/pickup/OTP actions; UI rider invitation acceptance; real clock waits'};
  }finally{socket.dispose();for(final client in clients.values){client.close();}}
 },timeout:const Timeout(Duration(minutes:12)));
}
