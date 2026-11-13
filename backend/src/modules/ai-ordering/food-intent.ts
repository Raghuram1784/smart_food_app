
export interface FoodIntent {
  dishQuery: string | null;
  quantity: number | null;
  vegetarian: boolean | null;
  maxPayablePaise: number | null;
  minRating: number | null;
  maxDeliveryMinutes: number | null;
  clarificationQuestion: string | null;
}

export function normalizeFoodIntent(raw: unknown): FoodIntent {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new Error('AI intent must be an object');
  }

  const data = raw as Record<string, unknown>;

  const allowed = new Set<keyof FoodIntent>([
    'dishQuery',
    'quantity',
    'vegetarian',
    'maxPayablePaise',
    'minRating',
    'maxDeliveryMinutes',
    'clarificationQuestion',
  ]);

  if (Object.keys(data).some(key => !allowed.has(key as keyof FoodIntent))) {
    throw new Error('Unexpected AI intent field');
  }

  function text(key: keyof FoodIntent, maxLength: number): string | null {
    const value = data[key];
    if (value === undefined || value === null) return null;
    if (typeof value !== 'string' || value.length > maxLength) {
      throw new Error(`Invalid ${key}`);
    }
    return value.trim() || null;
  }

  function number(
    key: keyof FoodIntent,
    min: number,
    max: number,
    integer = true,
  ): number | null {
    const value = data[key];
    if (value === undefined || value === null) return null;
    if (
      typeof value !== 'number' ||
      !Number.isFinite(value) ||
      value < min ||
      value > max ||
      (integer && !Number.isInteger(value))
    ) {
      throw new Error(`Invalid ${key}`);
    }
    return value;
  }

  const vegetarian = data.vegetarian;

  if (
    vegetarian !== undefined &&
    vegetarian !== null &&
    typeof vegetarian !== 'boolean'
  ) {
    throw new Error('Invalid vegetarian preference');
  }

  return {
    dishQuery: text('dishQuery', 120),
    quantity: number('quantity', 1, 20),
    vegetarian: vegetarian == null ? null : vegetarian as boolean,
    maxPayablePaise: number('maxPayablePaise', 1, 100000000),
    minRating: number('minRating', 0, 5, false),
    maxDeliveryMinutes: number('maxDeliveryMinutes', 1, 180),
    clarificationQuestion: text('clarificationQuestion', 240),
  };
}

export const CLEARABLE_INTENT_FIELDS = [
  'dishQuery',
  'quantity',
  'vegetarian',
  'maxPayablePaise',
  'minRating',
  'maxDeliveryMinutes',
] as const;

export type ClearableIntentField =
  typeof CLEARABLE_INTENT_FIELDS[number];

export function mergeIntentWithClears(
  previous: FoodIntent | null,
  update: FoodIntent,
  clearFields: unknown = [],
): FoodIntent {
  if (
    !Array.isArray(clearFields) ||
    clearFields.length > CLEARABLE_INTENT_FIELDS.length ||
    clearFields.some(
      field =>
        typeof field !== 'string' ||
        !CLEARABLE_INTENT_FIELDS.includes(
          field as ClearableIntentField,
        ),
    ) ||
    new Set(clearFields).size !== clearFields.length
  ) {
    throw new Error('Invalid intent fields to clear');
  }

  const cleared = clearFields as ClearableIntentField[];

  for (const field of cleared) {
    if (update[field] !== null) {
      throw new Error(`Conflicting update for ${field}`);
    }
  }

  const merged: FoodIntent = {
    dishQuery: update.dishQuery ?? previous?.dishQuery ?? null,
    quantity: update.quantity ?? previous?.quantity ?? null,
    vegetarian: update.vegetarian ?? previous?.vegetarian ?? null,
    maxPayablePaise:
      update.maxPayablePaise ?? previous?.maxPayablePaise ?? null,
    minRating: update.minRating ?? previous?.minRating ?? null,
    maxDeliveryMinutes:
      update.maxDeliveryMinutes ??
      previous?.maxDeliveryMinutes ??
      null,
    clarificationQuestion: update.clarificationQuestion,
  };

  for (const field of cleared) {
    merged[field] = null;
  }

  return merged;
}
