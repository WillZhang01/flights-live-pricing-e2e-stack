## Context
`payment_price_options` is a display enrichment — it tells users that paying with a
specific provider (e.g. Visa) yields a discounted final price. It must flow from
Quote Service → QRS → FPS → Conductor without influencing any pricing logic.
IC is deliberately excluded from this change.

## Goals / Non-Goals
- **Goals**: propagate the field end-to-end; expose on Conductor v1 REST API
- **Non-Goals**: use payment options in IC filtering/ranking/sorting; expose on v2
  proto API (deferred); import Quote Service proto as a dependency

## Decisions

### IC bypass
FPS retains the full quote collection from QRS in `State`. At response-build time,
`SearchItineraryPricingItemResponseMapper` already performs quote lookups by
`item.getQuoteIds()` via `MappingContext.getQuotes()`. Payment options are attached
here using the same existing pattern — no IC changes required.

### Independent proto copies
Each service defines its own `PaymentPriceOption` message rather than importing from
Quote Service. This follows the existing precedent for `DiscountCategory` and
`UpsellQuote`, which are also independent copies across services.

### int64 for monetary values
QRS and FPS protos use `int64` for price/tax fields (scaled integers, ×10000).
`PaymentPriceOption.payment_discount` and `final_price` follow the same convention.

### Deduplication across multi-quote pricing items
When a `PricingItem` references multiple quote IDs (leg-based pricing), take payment
options from the first matching quote only — payment options are agent-level and
consistent across legs.

### Proto field numbers
Chosen to not conflict with existing fields:
- QRS `Quote`: field 16
- FPS `SearchItineraryPricingItemResponseProto`: field 23
- Conductor `PricingOptionItem`: field 17

## Affected Files

| Service | File | Change |
|---------|------|--------|
| QRS | `quoteretrievalservice/proto/dps/quoteretrievalservice/quote.proto` | Add message + field |
| QRS | `...quoteservice/RawQuote.java` | Add field |
| QRS | `...quoteservice/RawPaymentPriceOption.java` | New value class |
| QRS | `...mappers/quoteservice/QuoteServiceMapper.java` | Map from Quote Service |
| QRS | RawQuote→proto serialiser (search `Quotes.Quote.newBuilder()` in QRS) | Add field |
| FPS | `flights-pricing-svc/proto/fps/flightspricingsvc/search_response.proto` | Add message + field |
| FPS | `...data/quoterequestsdata/Quote.java` | Add field |
| FPS | `...data/quoterequestsdata/PaymentPriceOption.java` | New value class |
| FPS | `...client/quoteretrieval/ResponseMapper.java` | Map from QRS proto |
| FPS | `...mapper/domaintoresponse/SearchItineraryPricingItemResponseMapper.java` | Enrich response |
| Conductor | `conductor/proto/dps/conductor/v1/response.proto` | Add message + field |
| Conductor | `...api/response/PaymentPriceOption.java` | New API model |
| Conductor | `...api/response/PricingOptionItem.java` (or equivalent) | Add field |
| Conductor | `...mapper/ResponseFromProtoMapper.java` | Map from FPS proto |

## Risks / Trade-offs
- If Quote Service stops populating `payment_price_options`, the field will be absent
  (empty list) — graceful degradation, no error impact.
- The enrichment lookup in `SearchItineraryPricingItemResponseMapper` adds a small
  per-item iteration cost; negligible given the existing quote-lookup already done there.
