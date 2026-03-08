# Change: Add Payment Price Options to Flight Pricing API

## Why
Quote Service exposes `payment_price_options` on each `Quote` (field 13), providing
per-payment-method pricing (provider name, discount amount, final price). This data is
currently dropped at every layer of the stack. Surfacing it through the Conductor v1
REST API gives clients transparency to show users payment-method-specific prices
alongside the base fare — for example, Korean market searches (market: KR, currency: KRW)
already return payment discount data from partners.

## What Changes
- **QRS**: Add `PaymentPriceOption` message + field to `Quote` proto; propagate through
  `RawQuote` model and `QuoteServiceMapper`
- **FPS**: Add `PaymentPriceOption` to `Quote` domain and `ResponseMapper`; enrich
  `SearchItineraryPricingItemResponseProto` at response-build time using the existing
  quote-ID lookup in `SearchItineraryPricingItemResponseMapper`
- **Conductor**: Expose `payment_price_options` on `PricingOptionItem` in the v1
  REST API response at the same level as `price`
- **IC**: No changes — IC's `quote_ids` in `PricingItem` already links back to the
  original quotes; enrichment happens in FPS without IC involvement

## Impact
- Affected specs: `payment-price-options` (new)
- Affected code: see design.md for full file list
- Non-breaking: new optional repeated field on existing response messages; empty list
  when Quote Service returns no options
- No logic changes: additive enrichment only — no filtering, ranking, or sorting affected
