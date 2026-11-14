import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../commerce/commerce_repository.dart';
import '../location/delivery_destination.dart';
import 'finder_models.dart';

class FinderState {
  final List<FinderMessage> messages;
  final String? conversationId, chosenAreaId;
  final bool busy;
  const FinderState({this.messages = const [], this.conversationId, this.chosenAreaId, this.busy = false});
  FinderState copyWith({List<FinderMessage>? messages, String? conversationId, bool clearConversation = false, String? chosenAreaId, bool? busy}) => FinderState(
        messages: messages ?? this.messages,
        conversationId: clearConversation ? null : conversationId ?? this.conversationId,
        chosenAreaId: chosenAreaId ?? this.chosenAreaId,
        busy: busy ?? this.busy,
      );

  /// The latest assistant reply (refinement chips and selection refer to it).
  FinderReply? get lastReply => messages.whereType<AssistantFinderMessage>().lastOrNull?.reply;
}

/// One Smart Food Finder conversation per signed-in customer. Rebuilt (and so
/// emptied) whenever the customer changes, so nothing leaks across accounts.
class FinderController extends Notifier<FinderState> {
  @override
  FinderState build() {
    ref.watch(customerIdProvider);
    return const FinderState();
  }

  String? get area => ref.read(deliveryServiceAreaProvider)?.id ?? state.chosenAreaId;

  Future<void> send(String text, {bool isRetry = false}) async {
    final message = text.trim();
    if (message.isEmpty || state.busy) return;
    final messages = [...state.messages];
    if (isRetry && messages.lastOrNull is NoteFinderMessage) messages.removeLast();
    if (!isRetry) messages.add(UserFinderMessage(message));
    state = state.copyWith(messages: messages, busy: true);
    await _ask({'message': message}, retryText: message);
  }

  /// The customer picked a delivery area from the chips; re-run the remembered search.
  Future<void> chooseArea(FinderArea a) async {
    if (state.busy) return;
    state = state.copyWith(chosenAreaId: a.id, busy: true, messages: [...state.messages, UserFinderMessage('Deliver to ${a.name}')]);
    await _ask({'refresh': true});
  }

  Future<void> _ask(Json body, {String? retryText, bool recovering = false}) async {
    final customer = ref.read(customerIdProvider);
    final repo = ref.read(commerceRepositoryProvider);
    try {
      final data = await repo.request('POST', 'food-finder/ask', {
        ...body,
        'conversationId': ?state.conversationId,
        'area': ?area,
      });
      if (!ref.mounted || ref.read(customerIdProvider) != customer) return; // account changed meanwhile
      final reply = FinderReply.fromJson((data as Map).cast<String, dynamic>());
      state = state.copyWith(conversationId: reply.conversationId, busy: false, messages: [...state.messages, AssistantFinderMessage(reply)]);
    } on DioException catch (e) {
      if (!ref.mounted) return;
      if (e.response?.statusCode == 404 && state.conversationId != null && !recovering && retryText != null) {
        // Server restarted or the conversation expired: start fresh with the same request.
        state = state.copyWith(clearConversation: true, messages: [...state.messages, const NoteFinderMessage('Your earlier search expired, so I started a new one.')]);
        return _ask(body, retryText: retryText, recovering: true);
      }
      state = state.copyWith(busy: false, messages: [...state.messages, NoteFinderMessage(_error(e), isError: true, retryText: retryText)]);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(busy: false, messages: [...state.messages, NoteFinderMessage(commerceError(e), isError: true, retryText: retryText)]);
    }
  }

  String _error(DioException e) {
    final code = e.response?.statusCode;
    if (code == 429) return 'You\'re sending messages quickly. Please wait a moment and try again.';
    if (code == 409) return 'Still working on your previous message.';
    if (e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.connectionTimeout) return 'That took too long. Please try again.';
    if (e.response == null) return 'Can\'t reach the server. Check your connection and try again.';
    return commerceError(e);
  }

  Future<void> reset() async {
    final id = state.conversationId;
    state = FinderState(chosenAreaId: state.chosenAreaId);
    if (id != null) {
      try {
        await ref.read(commerceRepositoryProvider).request('DELETE', 'food-finder/conversations/$id');
      } catch (_) {}
    }
  }
}

final finderControllerProvider = NotifierProvider<FinderController, FinderState>(FinderController.new);
