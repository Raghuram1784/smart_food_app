import '../catalog/catalog.dart';
import '../commerce/commerce_repository.dart' show Json;
export '../commerce/commerce_repository.dart' show Json;


int _int(Object? v) => v is num ? v.round() : 0;
int? _intOrNull(Object? v) => v is num ? v.round() : null;

/// One dish the backend recommended. Every amount comes from the server's pricing
/// engine; the app never computes or adjusts a total.
class FinderRecommendation {
  final String menuItemId, restaurantId, restaurantName, name, description, imageKey;
  final String? locality, variantId, variantName;
  final bool isVegetarian, hasVariantChoices, hasAddOns;
  final int quantity;
  final int foodPaise, discountPaise, packagingPaise, deliveryPaise, platformPaise, taxPaise, totalPaise;
  final int? budgetPaise, budgetDifferencePaise;
  final String budgetStatus, matchType;
  final Nutrition? nutrition;
  final List<String> tasteTags, reasons;
  final int spiceLevel;

  const FinderRecommendation({
    required this.menuItemId,
    required this.restaurantId,
    required this.restaurantName,
    required this.name,
    required this.description,
    required this.imageKey,
    this.locality,
    this.variantId,
    this.variantName,
    required this.isVegetarian,
    this.hasVariantChoices = false,
    this.hasAddOns = false,
    this.quantity = 1,
    required this.foodPaise,
    this.discountPaise = 0,
    this.packagingPaise = 0,
    this.deliveryPaise = 0,
    this.platformPaise = 0,
    this.taxPaise = 0,
    required this.totalPaise,
    this.budgetPaise,
    this.budgetDifferencePaise,
    required this.budgetStatus,
    required this.matchType,
    this.nutrition,
    this.tasteTags = const [],
    this.reasons = const [],
    this.spiceLevel = 0,
  });

  bool get overBudget => budgetStatus == 'ABOVE_BUDGET';
  String get photoKey => Dish.photoKeyFor(imageKey, name);

  /// Selection for the existing cart API (same variant the quote used, no add-ons).
  Json selection(String? area) => {
        'restaurantId': restaurantId,
        'menuItemId': menuItemId,
        'quantity': quantity,
        'addOnIds': <String>[],
        'variantId': ?variantId,
        'area': ?area,
      };

  factory FinderRecommendation.fromJson(Json j) {
    final p = (j['pricing'] as Map?)?.cast<String, dynamic>() ?? const {};
    final v = (j['variant'] as Map?)?.cast<String, dynamic>();
    return FinderRecommendation(
      menuItemId: j['menuItemId'] as String,
      restaurantId: j['restaurantId'] as String,
      restaurantName: j['restaurantName'] as String? ?? '',
      locality: j['locality'] as String?,
      name: j['name'] as String,
      description: j['description'] as String? ?? '',
      imageKey: j['imageKey'] as String? ?? 'meals',
      isVegetarian: j['isVegetarian'] == true,
      quantity: _int(j['quantity']).clamp(1, 20),
      variantId: v?['id'] as String?,
      variantName: v?['name'] as String?,
      hasVariantChoices: j['hasVariantChoices'] == true,
      hasAddOns: j['hasAddOns'] == true,
      foodPaise: _int(p['foodPaise']),
      discountPaise: _int(p['discountPaise']),
      packagingPaise: _int(p['packagingPaise']),
      deliveryPaise: _int(p['deliveryPaise']),
      platformPaise: _int(p['platformPaise']),
      taxPaise: _int(p['taxPaise']),
      totalPaise: _int(p['totalPaise']),
      budgetPaise: _intOrNull(j['budgetPaise']),
      budgetDifferencePaise: _intOrNull(j['budgetDifferencePaise']),
      budgetStatus: j['budgetStatus'] as String? ?? 'NO_BUDGET',
      matchType: j['matchType'] as String? ?? 'SIMILAR',
      nutrition: Nutrition.fromJson(j['nutrition']),
      tasteTags: [for (final t in j['tasteTags'] as List? ?? const []) '$t'],
      reasons: [for (final t in j['reasons'] as List? ?? const []) '$t'],
      spiceLevel: _int(j['spiceLevel']).clamp(0, 3),
    );
  }
}

class FinderResult {
  final String status, areaName, notice;
  final int? budgetPaise;
  final int excludedForMissingNutrition;
  final List<FinderRecommendation> exact, nearBudget, similar;
  const FinderResult({
    required this.status,
    required this.areaName,
    this.notice = '',
    this.budgetPaise,
    this.excludedForMissingNutrition = 0,
    this.exact = const [],
    this.nearBudget = const [],
    this.similar = const [],
  });
  bool get isEmpty => exact.isEmpty && nearBudget.isEmpty && similar.isEmpty;
  factory FinderResult.fromJson(Json j) {
    List<FinderRecommendation> list(String k) => [
          for (final r in j[k] as List? ?? const []) FinderRecommendation.fromJson((r as Map).cast<String, dynamic>()),
        ];
    return FinderResult(
      status: j['status'] as String? ?? 'NO_RESULTS',
      areaName: ((j['area'] as Map?)?['name'] as String?) ?? '',
      notice: j['notice'] as String? ?? '',
      budgetPaise: _intOrNull(j['budgetPaise']),
      excludedForMissingNutrition: _int(j['excludedForMissingNutrition']),
      exact: list('exact'),
      nearBudget: list('nearBudget'),
      similar: list('similar'),
    );
  }
}

class FinderArea {
  final String id, name;
  const FinderArea(this.id, this.name);
}

class FinderReply {
  final String conversationId, status, reply, interpreter;
  final String? intentSummary, aiNotice;
  final FinderResult? result;
  final FinderRecommendation? selected;
  final bool requiresBudgetConfirmation;
  final List<FinderArea> areas;
  const FinderReply({
    required this.conversationId,
    required this.status,
    required this.reply,
    this.interpreter = 'none',
    this.intentSummary,
    this.aiNotice,
    this.result,
    this.selected,
    this.requiresBudgetConfirmation = false,
    this.areas = const [],
  });
  factory FinderReply.fromJson(Json j) => FinderReply(
        conversationId: j['conversationId'] as String,
        status: j['status'] as String? ?? 'RESULTS',
        reply: j['reply'] as String? ?? '',
        interpreter: j['interpreter'] as String? ?? 'none',
        intentSummary: j['intentSummary'] as String?,
        aiNotice: j['aiNotice'] as String?,
        result: j['result'] is Map ? FinderResult.fromJson((j['result'] as Map).cast<String, dynamic>()) : null,
        selected: j['selected'] is Map ? FinderRecommendation.fromJson((j['selected'] as Map).cast<String, dynamic>()) : null,
        requiresBudgetConfirmation: j['requiresBudgetConfirmation'] == true,
        areas: [
          for (final a in j['areas'] as List? ?? const [])
            if (a is Map && a['id'] is String) FinderArea(a['id'] as String, (a['name'] as String?) ?? a['id'] as String),
        ],
      );
}

sealed class FinderMessage {
  const FinderMessage();
}

class UserFinderMessage extends FinderMessage {
  final String text;
  const UserFinderMessage(this.text);
}

class AssistantFinderMessage extends FinderMessage {
  final FinderReply reply;
  const AssistantFinderMessage(this.reply);
}

class NoteFinderMessage extends FinderMessage {
  final String text;
  final bool isError;
  final String? retryText;
  const NoteFinderMessage(this.text, {this.isError = false, this.retryText});
}
