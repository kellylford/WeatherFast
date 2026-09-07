# Tip Jar — Implementation Plan

> Revised 2026-08-01. The original draft was a generic StoreKit 2 write-up; this
> version is fitted to Weather Fast (`com.weatherfast.app`, App Store app ID
> `6757891543`) and corrects three things the draft got wrong — see
> [Corrections from the first draft](#corrections-from-the-first-draft) at the end.

## Goal

Let users leave an optional tip via in-app purchase. Surface it as the **first**
section of the Settings tab. Keep it low-friction: a single sheet showing four tip
amounts and a clear thank-you.

## Current state (verified 2026-08-01)

| Item | State |
|------|-------|
| Bundle ID | `com.weatherfast.app` (widget: `com.weatherfast.app.widget`) |
| IAP products in App Store Connect | **none** — `inAppPurchasesV2` returns empty |
| Sandbox testers | **none** configured |
| StoreKit in the codebase | **none** — no `import StoreKit`, no `.storekit` file |
| App version | 1.6.0 build 1 |

---

## Prerequisite Steps (Done Before Writing Code)

### 0. Paid Applications Agreement — do this first

Nothing below works without it. In App Store Connect → **Business** (formerly
"Agreements, Tax, and Banking"):

1. **Paid Apps** agreement must show status **Active**. If it shows "Pending" or
   requires action, an Account Holder must accept it — no other role can.
2. **Bank account** must be added and verified.
3. **Tax forms** must be complete for every region you sell in (at minimum the
   U.S. forms).

Until all three are done you can still *create* IAP products, but `Product.products(for:)`
will return them as unpurchasable and real users cannot pay. This is easy to miss
because the sandbox works fine without it.

While you're in there: check whether you're enrolled in the **Small Business
Program** (15% commission instead of 30% under $1M/year). Enrollment is not
automatic — you apply, and it takes effect the following month.

### 1. Create the IAP products

App Store Connect → Weather Fast → **Monetization** → **In-App Purchases** → **+**.

Type: **Consumable** for all four. Consumables are the correct type for tips —
users can tip repeatedly, and consumables are neither restorable nor expected to
persist across reinstalls.

| Product ID | Reference Name | Display Name | Price |
|------------|----------------|--------------|-------|
| `com.weatherfast.app.tip.small` | Tip — Small | Small Tip | $0.99 |
| `com.weatherfast.app.tip.medium` | Tip — Medium | Medium Tip | $2.99 |
| `com.weatherfast.app.tip.large` | Tip — Large | Large Tip | $4.99 |
| `com.weatherfast.app.tip.xlarge` | Tip — Generous | Generous Tip | $9.99 |

> ⚠️ **Product IDs are permanent.** Once created, an IAP product ID can never be
> deleted or reused — not in this app, not in any app, ever. Get these right the
> first time. Same goes for the price tiers being sensible; prices *can* change,
> IDs cannot.

For each product you must also supply:

- **At least one localization** — display name + description (English is enough to
  start). A product with no localization cannot be submitted.
- **A tax category.** For a tip with no goods or services attached, the general
  "Other" / non-specific category is normally correct. If unsure, Apple's picker
  has a guided flow — don't guess and move on, a wrong category is a review
  rejection.
- **A review screenshot.** This is **required**, not optional. It must show the tip
  sheet as a reviewer would see it, at a supported screenshot size. Take it once
  the UI is built and reuse the same image for all four products.

### 2. Understand the review sequencing — this shapes the release

**The first in-app purchase must be submitted together with a new app version.**
Only after App Review has approved at least one IAP for the app can you submit
further IAPs standalone.

Practical consequence for Weather Fast:

- The four tip products and the **1.6.0 binary go to App Review as one submission**.
- Per the golden rule in [`RELEASING.md`](RELEASING.md), that binary must come from
  the GitHub Actions workflow (`.github/workflows/ios-release.yml`) — this dev Mac
  runs a beta macOS and its App Store builds are rejected as `INVALID_BINARY`.
- So budget for a full Actions release cycle, not a local build, and expect that a
  rejection of *either* the app or the IAPs blocks the whole submission.
- TestFlight is unaffected — TestFlight builds may be local, and sandbox purchases
  work in TestFlight without any of the review steps above.

Source: [Apple — Submit an in-app purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase).

### 3. Xcode setup

No new capability or entitlement is needed — StoreKit 2 is part of the standard SDK.
For local testing, create a StoreKit configuration file:

1. File → New → File → **StoreKit Configuration File**, name it `StoreKitConfig.storekit`.
2. Choose **"Sync this file with an app in App Store Connect"** and pick Weather Fast.
   This pulls the four product definitions down automatically — prefer it over
   hand-entering products, which invites typos in the IDs.
3. Scheme editor → **Run** → Options → **StoreKit Configuration** → select the file.
   Do the same for the **Test** action if you add tests that touch StoreKit.

This lets you exercise purchases in the Simulator with no App Store Connect
approval and no network.

### 4. Sandbox testers (for on-device testing)

App Store Connect → **Users and Access** → **Sandbox** → **Testers** → **+**.
None exist today. Create at least one with an email address not already tied to an
Apple ID. On the device, sign in under Settings → Developer → Sandbox Apple Account
(not the main iCloud account).

---

## Architecture

### New file: `Services/TipService.swift`

Follows the codebase's service pattern: a `@MainActor` `ObservableObject` singleton,
logging through `AppLogger.service`, never `print()`.

```swift
import StoreKit
import Foundation

@MainActor
final class TipService: ObservableObject {
    static let shared = TipService()

    enum PurchaseState: Equatable {
        case idle
        case loading
        case purchasing
        case thankYou
        case failed(String)   // user-facing message, never a raw error string
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var state: PurchaseState = .idle

    private let productIDs = [
        "com.weatherfast.app.tip.small",
        "com.weatherfast.app.tip.medium",
        "com.weatherfast.app.tip.large",
        "com.weatherfast.app.tip.xlarge"
    ]

    /// IDs of transactions already finished this launch, so a transaction that
    /// arrives via BOTH `Transaction.unfinished` and `Transaction.updates`
    /// is not counted twice.
    private var handledTransactionIDs = Set<UInt64>()
    private var updatesTask: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    /// Call once at app launch, before any UI. See `WeatherFastApp.init()`.
    func start() {
        guard updatesTask == nil else { return }

        updatesTask = Task(priority: .background) { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }

        Task {
            for await unfinished in Transaction.unfinished {
                await handle(unfinished)
            }
        }
    }

    // MARK: - Products

    func loadProducts() async {
        guard products.isEmpty else { return }
        state = .loading
        do {
            products = try await Product.products(for: productIDs)
                .sorted { $0.price < $1.price }
            state = .idle
            if products.isEmpty {
                AppLogger.service.error("TipService: no products returned; check Paid Apps agreement and product state")
                state = .failed("Tips aren't available right now.")
            }
        } catch {
            AppLogger.service.error("TipService: failed to load products: \(error.localizedDescription)")
            state = .failed("Couldn't reach the App Store. Please try again.")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        state = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await handle(verification)          // sets .thankYou on success
            case .userCancelled:
                state = .idle
            case .pending:
                // Ask to Buy, or a payment awaiting clearance. The transaction
                // will arrive later on `Transaction.updates`.
                state = .idle
            @unknown default:
                state = .idle
            }
        } catch {
            AppLogger.service.error("TipService: purchase failed: \(error.localizedDescription)")
            state = .failed("The purchase didn't go through.")
        }
    }

    /// Single funnel for every transaction, whatever sequence delivered it.
    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            AppLogger.service.error("TipService: unverified transaction, ignoring")
            return
        }
        defer { Task { await transaction.finish() } }

        guard handledTransactionIDs.insert(transaction.id).inserted else { return }
        guard productIDs.contains(transaction.productID) else { return }

        state = .thankYou
    }

    func dismissThankYou() { state = .idle }
}
```

**Why the listener matters.** A purchase can complete without ever returning from
`product.purchase()` — Ask to Buy approval arriving hours later, a payment method
that clears after the fact, or the app being killed mid-flow. Without
`Transaction.updates` those transactions are never finished, so StoreKit re-delivers
them on every launch forever, and the user is charged for a tip the app never
acknowledges. Apple's guidance is to start the listener at launch so it catches
transactions before any UI exists. `Transaction.unfinished` and `Transaction.updates`
can emit the same transaction, hence the `handledTransactionIDs` set.

### Wire into `WeatherFastApp.swift`

```swift
init() {
    iCloudSyncService.shared.start()
    TipService.shared.start()          // must be before any UI
}
```

```swift
ContentView()
    .environmentObject(weatherService)
    .environmentObject(settingsManager)
    .environmentObject(MyLocationService.shared)
    .environmentObject(TipService.shared)     // ← add
```

> Do **not** write `@StateObject private var tipService = TipService.shared` in the
> view. `@StateObject` claims ownership of a value it did not create; with a
> singleton that is a latent lifetime bug. This codebase injects services as
> `@EnvironmentObject` at the app root — follow that.

### New file: `Views/TipJarView.swift`

Presented as a sheet from `SettingsView`. Use `NavigationStack` — `NavigationView`
is deprecated and the project targets iOS 17+.

```swift
import SwiftUI
import StoreKit

struct TipJarView: View {
    @EnvironmentObject var tipService: TipService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // headline + description, product buttons, state handling
        }
        .task { await tipService.loadProducts() }
    }
}
```

Behaviour:

- Short "Support Weather Fast" headline and a one-line explanation that tips are
  entirely optional and unlock nothing.
- Four buttons in a vertical list, each labelled from `product.displayPrice`.
- `.loading` → progress indicator; `.purchasing` → buttons disabled with a spinner.
- `.thankYou` → thank-you message plus a success haptic; user may tip again or dismiss.
- `.failed` → short plain-language message. Never surface a raw `Error` string.

**Accessibility (non-negotiable, per CLAUDE.md):**

- `.accessibilityElement(children: .ignore)` with an explicit `.accessibilityLabel()`
  on each row — not `.combine`.
- Label: `"Tip \(product.displayPrice)"`.
- Hint: `"Opens Apple's payment confirmation."` — **not** "non-refundable." Apple
  does grant refunds, so that claim is false, and false claims about purchase terms
  are exactly what reviewers look for.
- Thank-you state must post an `.announcement` (or move focus) so VoiceOver users
  learn the purchase succeeded.
- Any decorative heart/icon gets `.accessibilityHidden(true)`.
- Test with VoiceOver before calling this done.

**Consider and reject:** iOS 17 ships SwiftUI's `StoreView`/`ProductView`, which
would remove most of this UI code. Not used here — the stock views don't give
enough control over labels, hints, and announcements to meet this app's
accessibility bar.

---

## Changes to `SettingsView.swift`

The tip section goes **first**, above "My Location".

```swift
@State private var showingTipJar = false
```

```swift
Section(header: Text("Support")) {
    Button {
        showingTipJar = true
    } label: {
        HStack {
            Image(systemName: "heart.fill")
                .foregroundColor(.pink)
                .accessibilityHidden(true)
            Text("Leave a Tip")
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
        }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Leave a Tip")
    .accessibilityHint("Opens the tip jar to support app development")
}
```

Plus `.sheet(isPresented: $showingTipJar) { TipJarView() }`.

> **Decision needed.** `SettingsView.swift:34` carries the comment
> `// My Location section (first, per user preference)`. Putting Support first
> displaces it. That's the stated intent here, but update or remove that comment so
> the code doesn't contradict itself.

---

## Purchase Flow (User's Perspective)

1. User taps "Leave a Tip" — the first row in Settings.
2. Sheet opens showing four amounts at local App Store prices.
3. Tap an amount → Apple's standard payment confirmation sheet.
4. On confirmation → thank-you state, success haptic, VoiceOver announcement.
5. User dismisses, or tips again.

If the account has Ask to Buy enabled, step 3 ends in `.pending` and the sheet
returns to idle; the thank-you appears later when `Transaction.updates` delivers
the approved transaction.

---

## Transaction Handling Notes

- Consumables do **not** use `Transaction.currentEntitlements` and are not restorable.
  Each tip is independent.
- Always `await transaction.finish()` — required by StoreKit 2 to clear the queue.
  The plan above does it in a `defer` so it happens on every path, including
  duplicates and foreign product IDs.
- Do **not** add a "Restore Purchases" button. Consumables can't be restored and
  Apple doesn't require one for a tip-only IAP. (Non-consumables do require it.)
- Apple's commission is 30%, or 15% if you're enrolled in the Small Business Program.

---

## Pricing & Currency

`product.displayPrice` returns a correctly formatted, correctly localized string.
Never hardcode `"$0.99"` anywhere in the UI. The `$` figures in this document are
U.S. reference points for choosing tiers, not display strings.

---

## Testing

| Scenario | How to Test |
|----------|-------------|
| Products load | Simulator with `StoreKitConfig.storekit` selected in the scheme |
| Successful purchase | Simulator — thank-you appears, haptic fires, VoiceOver announces |
| User cancels | Cancel the payment sheet — returns to idle, no error shown |
| Ask to Buy / pending | StoreKit config editor → enable Ask to Buy → confirm sheet returns to idle, then approve and confirm the thank-you arrives via the listener |
| Unfinished transaction on launch | Kill the app mid-purchase, relaunch, confirm the transaction is finished exactly once (not double-counted) |
| Product load failure | Airplane mode → confirm the graceful "couldn't reach the App Store" message, not a raw error |
| VoiceOver | Full sweep of the sheet in every state: loading, idle, purchasing, thank-you, failed |
| Sandbox on device | Sandbox tester account on a physical device via TestFlight build |

---

## App Store Review Considerations

- Tips are explicitly allowed — users voluntarily supporting a developer.
- Tips must unlock **nothing**. No features, no content, no removal of anything.
  Gating anything behind a tip changes the product type and the review treatment.
- Making it the first Settings row is fine; reviewers care that it's clearly
  voluntary, not where it sits.
- Have the review screenshot ready before submitting — it's required per product.

---

## Estimated Effort

| Phase | Work |
|-------|------|
| Paid Apps agreement / bank / tax verification | 30 min–days (depends on whether it's already Active) |
| App Store Connect product setup (4 products + localizations + tax category + screenshots) | 1–1.5 hours |
| StoreKit config file synced from ASC | 15 min |
| `TipService.swift` incl. updates/unfinished listener | 3 hours |
| `TipJarView.swift` (UI + accessibility + VoiceOver pass) | 3–4 hours |
| Wire into `WeatherFastApp` + `SettingsView` | 45 min |
| Testing (Simulator, Ask to Buy, sandbox on device) | 3 hours |
| Release cycle via GitHub Actions + combined app/IAP review submission | separate, ~1 day of wall clock plus review time |
| **Total engineering** | **~2 days** |

---

## Corrections from the first draft

Recorded so the same mistakes don't get re-introduced:

1. **"Products can be reviewed independently of an app update"** — false for the
   *first* IAP. It must be submitted with a new app version. Only subsequent IAPs
   can go standalone. This is why 1.6.0 and the tips ship as one submission.
2. **No `Transaction.updates` listener.** The draft handled only the return value of
   `product.purchase()`, silently dropping Ask to Buy approvals, deferred payments,
   and any purchase interrupted by app termination — leaving transactions unfinished
   and re-delivered forever.
3. **Paid Applications Agreement not mentioned.** Without an Active agreement plus
   bank and tax forms, no one can pay. The sandbox works without it, so this fails
   only in production.
4. Placeholder product IDs (`com.yourapp.*`) → real ones under `com.weatherfast.app`,
   with a note that IDs are permanent.
5. `@StateObject … = .shared` → `@EnvironmentObject`, matching the codebase pattern.
6. `NavigationView` → `NavigationStack` (iOS 17+ target).
7. `PurchaseState` made `Equatable` and carrying a user-facing `String` rather than
   a raw `Error`.
8. Accessibility hint "One-time purchase, non-refundable" — factually wrong; Apple
   grants refunds.
9. Added the omitted App Store Connect requirements: required review screenshot
   (draft said "may ask"), product localizations, tax category, sandbox testers.
10. Added the Small Business Program enrollment caveat (15% is not automatic).
