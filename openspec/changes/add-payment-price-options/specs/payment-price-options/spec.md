## ADDED Requirements

### Requirement: Payment Price Options Propagation
The pricing stack SHALL propagate `payment_price_options` from Quote Service through
QRS and FPS to Conductor without modification to any filtering, ranking, or sorting
logic. ItineraryConstruction SHALL NOT be involved in this propagation.

#### Scenario: Options flow end-to-end
- **WHEN** Quote Service returns a `Quote` with non-empty `payment_price_options`
  (e.g. EDI→LON, market: KR, currency: KRW, channel: tvis)
- **THEN** each option's `provider_name`, `payment_discount`, and `final_price` SHALL
  be present in the Conductor v1 REST API response for the corresponding pricing option item

#### Scenario: Graceful absence when no options returned
- **WHEN** Quote Service returns a `Quote` with empty `payment_price_options`
  (e.g. EDI→LHR, market: UK, currency: GBP)
- **THEN** the corresponding pricing option item in the Conductor v1 REST API response
  SHALL contain an empty list for `payment_price_options` — not null, not an error

#### Scenario: IC not modified
- **WHEN** this change is deployed
- **THEN** the ItineraryConstruction gRPC request and response message schemas
  SHALL remain unchanged

### Requirement: Conductor v1 REST API Payment Price Options Shape
The Conductor v1 REST API SHALL include `payment_price_options` on each pricing option
item at the same level as `price`, as a display enrichment field only.

#### Scenario: Field placement in poll response
- **WHEN** a client polls `GET /v1/fps3/search/{sessionId}` with
  `X-Skyscanner-ChannelId: tvis`, market `KR`, currency `KRW`
- **THEN** each pricing option item SHALL contain `payment_price_options` as a list
  at the same nesting level as `price`, `agent_id`, and `url`

#### Scenario: Per-option fields present
- **WHEN** `payment_price_options` is non-empty in the response
- **THEN** each entry SHALL contain:
  - `provider_name`: non-empty string (e.g. "Visa", "MasterCard")
  - `payment_discount`: monetary value in search currency representing the discount amount
  - `final_price`: monetary value in search currency after applying the discount

### Requirement: End-to-End Validation via Local Stack
Changes to the payment options propagation path SHALL be validated using the
local full-stack testing workflow defined in `local-testing/README.md`.

#### Scenario: KR/KRW/tvis search returns payment options
- **WHEN** the full local stack is running (all 4 services + Redis)
- **AND** a create request is sent to Conductor v1 with market `KR`, currency `KRW`,
  channel `tvis`, route EDI→LON
- **AND** the session is polled until all agents reach `update_status: current`
- **THEN** at least one pricing option item in the final poll response SHALL contain
  a non-empty `payment_price_options` list

#### Scenario: Regression — existing searches unaffected
- **WHEN** the same local stack processes a standard UK/GBP search (EDI→LHR)
- **THEN** the `local-testing/test-e2e.sh` script SHALL pass with all existing
  required fields (`itineraries`, `agents`, `legs`, `segments`, `context`) present
  and `payment_price_options` returning as an empty list without errors
