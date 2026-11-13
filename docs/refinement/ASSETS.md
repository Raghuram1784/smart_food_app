#Refinement asset manifest

All new photos are actual downloaded Pexels stock photographs, not generated images. Downloaded 11 November 2026; source pages and visual review both checked. Pexels licence: https://www.pexels.com/license/ (app use and modification permitted; attribution optional, provided here; no implied endorsement).

| Asset | Creator | Source page | Downloaded source size | Bundled derivatives |
|---|---|---|---|---|
| dosa | Saveurs Secretes | https://www.pexels.com/photo/close-up-of-food-12392915/ | 2400×3600 | food 1400×1400; category 800×800; restaurant/hero 1800×1100 |
| idli | Lunarly | https://www.pexels.com/photo/traditional-indian-dish-on-a-plate-17869141/ | 2400×3695 | food 1400×1400; category 800×800; restaurant 1800×1100 |
| biryani | Milton Das | https://www.pexels.com/photo/vegetable-biryani-in-pressure-cooker-with-colorful-sides-35041655/ | 2400×1600 | food 1400×1400; category 800×800; restaurant 1800×1100 |
| paneer | dhiraj jain | https://www.pexels.com/photo/delicious-spicy-meal-12737816/ | 2400×1600 | food 1400×1400; category 800×800; restaurant 1800×1100 |

Download pattern: `https://images.pexels.com/photos/ID/pexels-photo-ID.jpeg?auto=compress&cs=tinysrgb&w=2400`. Images are JPEG quality 85–88 with optimized encoding. Crops use center x=.5/y=.55. Runtime decode widths are bounded to the display's physical width, capped at 1600 px. Category, card and hero images have separately prepared crops.

Dish checks: dosa visibly shows potato filling; idli photograph shows vegetable-studded rounds (labelled Vegetable idli); biryani source explicitly identifies vegetables and the photograph shows peas, carrots and beans; paneer source explicitly identifies paneer and peppers. No meat photo is assigned to a vegetarian dish. Each image maps only to its named dish or that dish's kitchen/collection.

Home hero replaced: pizza → masala dosa. Original pizza, pasta, salad and burger photographs retained for their original dishes, IDs and prices. A single fictional vegetarian kitchen and four accurately mapped dishes were added to satisfy the Indian cuisine direction without repurposing existing items. The kitchen hero is signature-food photography, not a claim to depict real premises.

A first dosa candidate (Pexels 32229637) was unreachable; it was replaced by the verified 12392915 source. No missing required asset remains. No unrelated placeholder was substituted.

## Typography

- Bricolage Grotesque: https://github.com/google/fonts/tree/main/ofl/bricolagegrotesque
- Sora: https://github.com/google/fonts/tree/main/ofl/sora
- Fraunces comparison: https://github.com/google/fonts/tree/main/ofl/fraunces

Actual variable TTF files downloaded from these directories. SIL Open Font Licence texts are bundled beside them and registered with Flutter's licence registry. Default active pair: Bricolage Grotesque + Sora. Fraunces remains registered solely for the build-time A/B comparison (`--dart-define=EDITORIAL_FONT=Fraunces`); it is not used by the default UI. The archived Manrope file is no longer registered or active.
