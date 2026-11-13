# Image and font credits

All food photography is bundled locally, downloaded from Pexels on 2026-11-11 and JPEG optimized. Pexels permits app use and modification under https://www.pexels.com/license/. No endorsement is implied. Restaurant names are fictional; photographs illustrate menu dishes rather than real restaurant premises.

| Asset / dish | Pexels source | Local use |
|---|---|---|
| Signature cheeseburger | https://www.pexels.com/photo/1639557/ | food, category, restaurant |
| Wood-fired pepperoni | https://www.pexels.com/photo/825661/ | food, category, restaurant, home hero |
| Tomato & basil penne | https://www.pexels.com/photo/1437267/ | food, category, restaurant |
| Mediterranean garden bowl | https://www.pexels.com/photo/1211887/ | food, category, restaurant |

Download URL pattern: `https://images.pexels.com/photos/ID/pexels-photo-ID.jpeg?auto=compress&cs=tinysrgb&w=1800` (burger: 1600). Source identifiers are retained because individual photographer page metadata was unavailable during sourcing. Category crops are 600 × 600. The same files serve both themes. Photographs were visually reviewed for dish correspondence. These are licensed stock photographs, not AI-generated imagery.

Manrope and Fraunces: Google Fonts repository https://github.com/google/fonts/tree/main/ofl, SIL Open Font License. Full licence texts are included in `assets/fonts/*-OFL.txt`. Font files are bundled for offline use.

## Retained image attribution update

The refinement verified full source pages for the retained images: burger — Valeria Boltneva, https://www.pexels.com/photo/ham-burger-with-vegetables-1639557/; pasta — Engin Akyurt, https://www.pexels.com/photo/closes-up-photo-of-macaroni-1437267/; pizza — Brett Jordan, https://www.pexels.com/photo/pizza-on-brown-wooden-board-825661/. Salad is credited to Iina Luoto at https://www.pexels.com/photo/vegetable-salad-on-white-ceramic-plate-1211887/ (attribution corroborated via https://lifeunmapped.com.au/attributions/; the original page was unavailable during this pass). All retain the Pexels licence above.

New Indian photography and current font licensing: [refinement/ASSETS.md](refinement/ASSETS.md). The burger description now explicitly mentions the bacon visible in the retained photograph; its ID, name and price are unchanged.

## Phase 2.5 Hyderabad Marketplace Photography

All 10 Hyderabad catalog assets below are original AI-generated editorial food photographs created specifically for the Food Delivery Demo Hyderabad marketplace catalog (2026-11-11). All existing Pexels stock photographs (`biryani`, `dosa`, `idli`, `paneer`, `pizza`, `pasta`, `burger`, `salad`, and hero crops `hero/dosa.jpg` and `hero/pizza.jpg`) remain completely untouched with their original Pexels attribution and license intact.

Visual inspection was performed and confirmed across all 10 source images and their cropped derivatives for dish authenticity, editorial lighting, and framing (`ImageOps.fit` with `centering=(0.5, 0.55)`). Packaged reproducibly using `tool/package_hyderabad_assets.py` into three JPEG-optimized derivative sets per key:
- `assets/images/food/<key>.jpg`: 1400 × 1400 (JPEG quality 88, `optimize=True`)
- `assets/images/categories/<key>.jpg`: 800 × 800 (JPEG quality 85, `optimize=True`)
- `assets/images/restaurants/<key>.jpg`: 1800 × 1100 (JPEG quality 86, `optimize=True`)

| Image key | Visual subject (inspected) | Source file | Source size | Bundled derivatives |
|---|---|---|---|---|
| `chicken-biryani` | Hyderabadi chicken dum biryani in hammered copper handi with boiled egg, mirchi ka salan, and raita | `chicken_biryani_1794416567326.jpg` | 1200 × 896 | food 1400×1400; category 800×800; restaurant 1800×1100 |
| `mutton-biryani` | Hyderabadi mutton dum biryani in brass handi with caramelized onions, cashews, whole spices, and raita | `mutton_biryani_raw_1794416565347.jpg` | 1200 × 896 | food 1400×1400; category 800×800; restaurant 1800×1100 |
| `haleem` | Slow-cooked Hyderabadi haleem in clay bowl topped with fried onions, cashews, ghee, ginger, and lime | `hyderabadi_haleem_1794416571856.jpg` | 1200 × 896 | food 1400×1400; category 800×800; restaurant 1800×1100 |
| `kebab` | Charcoal-grilled seekh kebabs and chicken tikka skewers with mint chutney, red onion rings, and lime | `kebab_raw_1794416572334.jpg` | 1200 × 896 | food 1400×1400; category 800×800; restaurant 1800×1100 |
| `noodles` | Indo-Chinese stir-fried hakka noodles with manchurian balls, bell peppers, and sesame scallions | `noodles_raw_1794416575398.jpg` | 1024 × 1024 | food 1400×1400; category 800×800; restaurant 1800×1100 |
| `meals` | Traditional South Indian banana-leaf thali with steamed rice, dal with ghee, sambar, curries, curd, and papadam | `meals_raw_1794416595758.jpg` | 1200 × 896 | food 1400×1400; category 800×800; restaurant 1800×1100 |
| `chaat` | Crispy samosa chaat plated with spiced yogurt, tamarind and mint chutneys, sev, onions, and pomegranate | `samosa_chaat_1794416596248.jpg` | 1200 × 896 | food 1400×1400; category 800×800; restaurant 1800×1100 |
| `bakery` | Stack of Hyderabadi Osmania biscuits paired with flaky golden vegetable puffs on parchment | `bakery_raw_1794416597697.jpg` | 1200 × 896 | food 1400×1400; category 800×800; restaurant 1800×1100 |
| `chai` | Steaming Hyderabadi Irani chai in porcelain cup and saucer served alongside Osmania biscuits | `hyderabadi_irani_chai_1794416601587.jpg` | 1200 × 896 | food 1400×1400; category 800×800; restaurant 1800×1100 |
| `dessert` | Hyderabadi double ka meetha garnished with saffron, pistachios, almonds, and rose petals beside gulab jamun | `dessert_raw_1794416603285.jpg` | 1200 × 896 | food 1400×1400; category 800×800; restaurant 1800×1100 |
