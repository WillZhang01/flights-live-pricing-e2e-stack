## 1. QRS

- [x] 1.1 Add `PaymentPriceOption` message and `payment_price_options` field (16) to
        `quoteretrievalservice/proto/dps/quoteretrievalservice/quote.proto`
- [x] 1.2 Create `RawPaymentPriceOption.java` (`@Value @Builder`) in
        `quoteretrievalservice/src/main/java/net/skyscanner/dps/quoteservice/`
        Fields: `String providerName; BigDecimal paymentDiscount; BigDecimal finalPrice`
- [x] 1.3 Add `List<RawPaymentPriceOption> paymentPriceOptions` to `RawQuote.java`
- [x] 1.4 Map `payment_price_options` from Quote Service `Quote` in `QuoteServiceMapper.java`
        (follow the existing `upsellQuotes` mapping as precedent)
- [x] 1.5 Find the RawQuote → QRS proto `Quote` serialiser
        (search `Quotes.Quote.newBuilder()` in QRS source) and add the field mapping
- [x] 1.6 `./gradlew generateProto build` in `quoteretrievalservice/`

## 2. FPS

- [x] 2.1 Add `PaymentPriceOption` message and `payment_price_options` field (23) to
        `flights-pricing-svc/proto/fps/flightspricingsvc/search_response.proto`
        on `SearchItineraryPricingItemResponseProto`
- [x] 2.2 Create `PaymentPriceOption.java` (`@Value @Builder`) in
        `flights-pricing-svc/src/main/java/net/skyscanner/fps/flightspricingsvc/data/quoterequestsdata/`
        Fields: `String providerName; long paymentDiscount; long finalPrice`
- [x] 2.3 Add `List<PaymentPriceOption> paymentPriceOptions` to `Quote.java` domain class
- [x] 2.4 Map `getPaymentPriceOptionsList()` from QRS proto in `ResponseMapper.java`
        (follow the `mapUpsellQuotes` guard pattern for null/empty)
- [x] 2.5 Enrich proto response in `SearchItineraryPricingItemResponseMapper.java`:
        look up the first quote matching `item.getQuoteIds()` via `mappingContext.getQuotes()`,
        map its `paymentPriceOptions` to proto, call `builder.addAllPaymentPriceOptions(...)`
- [x] 2.6 `./gradlew generateProto build` in `flights-pricing-svc/`

## 3. Conductor

- [x] 3.1 Add `PaymentPriceOption` message and `payment_price_options` field (17) to
        `conductor/proto/dps/conductor/v1/response.proto` on `PricingOptionItem`
- [x] 3.2 Create `PaymentPriceOption.java` API model in Conductor's response package
        (alongside `DiscountCategory.java`)
        Fields: `String providerName; long paymentDiscount; long finalPrice`
- [x] 3.3 Add `List<PaymentPriceOption> paymentPriceOptions` to the `PricingOptionItem`
        API model (wherever `discountCategory` is already a field)
- [x] 3.4 Map `getPaymentPriceOptionsList()` from FPS proto in `ResponseFromProtoMapper.java`
        (follow the `mapDiscountCategory` method as pattern reference)
- [x] 3.5 `./gradlew generateProto build` in `conductor/`

## 4. Build Validation

- [x] 4.1 Run full build in dependency order to catch any mapping errors at compile time:
        ```
        local-testing/build-all-services.sh
        ```
        (runs `clean generateProto build publishToMavenLocal` for IC → QRS → FPS → Conductor)

## 5. End-to-End Testing

> Uses the local-testing guide workflow. Requires: AWS credentials (`mshell login`)
> and proxy (`sudo mshell proxy`) running.

- [x] 5.1 Start Redis and the full local stack:
        ```bash
        redis-server --port 6380 --daemonize yes
        local-testing/start-local-stack.sh
        local-testing/check-services.sh   # all 4 services must be healthy
        ```

- [x] 5.2 **Regression check** — run baseline e2e to confirm no regressions for
        existing searches (UK/GBP, EDI→LHR):
        ```bash
        local-testing/test-e2e.sh
        ```
        Must pass with all agents completing and required fields present.

- [x] 5.3 **Payment options check** — run with website channel, ICN→SIN where Quote Service
        is known to return `payment_price_options`:
        ```bash
        RESPONSE=$(curl -s -X POST http://localhost:5020/v1/fps3/search \
          -H "Content-Type: application/json" \
          -H "Accept: application/json" \
          -H "X-Skyscanner-ChannelId: website" \
          -d '{
            "market": "KR",
            "currency": "KRW",
            "locale": "ko-KR",
            "adults": 1,
            "cabin_class": "economy",
            "legs": [{"origin": "ICN", "destination": "SIN", "date": "2026-04-15"}]
          }')
        SESSION_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['context']['session_id'])")
        ```

- [x] 5.4 Poll until all agents complete (within 60 seconds):
        ```bash
        curl -s http://localhost:5020/v1/fps3/search/$SESSION_ID \
          -H "Accept: application/json" \
          -H "X-Skyscanner-ChannelId: website" > /tmp/poll_response.json
        ```

- [x] 5.5 Verify `payment_price_options` appears in at least one pricing option item,
        at the same level as `price`:
        ```bash
        python3 -c "
        import json, sys
        d = json.load(open('/tmp/poll_response.json'))
        found = []
        for itin in d.get('itineraries', []):
            for opt in itin.get('pricing_options', []):
                for item in opt.get('items', []):
                    if item.get('payment_price_options'):
                        found.append(item['payment_price_options'])
        print(f'Found payment_price_options in {len(found)} pricing item(s)')
        if found:
            print('Example:', json.dumps(found[0], indent=2))
        else:
            print('WARNING: No payment_price_options found')
        "
        ```

- [x] 5.6 Verify each payment option entry contains `provider_name`, `payment_discount`,
        and `final_price` fields.

- [x] 5.7 Re-run baseline test (UK/GBP) and confirm `payment_price_options` is an empty
        list (not an error) for searches where Quote Service returns no options.

- [x] 5.8 Stop the stack:
        ```bash
        local-testing/stop-local-stack.sh
        ```
