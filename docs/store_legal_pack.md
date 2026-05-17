# Store and legal rollout pack (templates)

This document helps operations and legal counsel assemble **store submissions** and **privacy posture** artifacts.  
**Not legal advice** — templates must be reviewed by qualified counsel and adapted to your entity, jurisdictions, products, and data flows.

---

## 1. Data controller / roles

Fill in factual details:

| Question | Answer (your org) |
|----------|-------------------|
| Legal entity name | _________________________ |
| Contact email | _________________________ |
| Data Processor (backend) — e.g., Supabase region | _________________________ |
| Crash analytics provider | Firebase Crashlytics □ Yes / □ No — region __________ |
| Payment processor | RevenueCat / Apple / Google specifics __________ |

---

## 2. Privacy policy checklist (URLs and coverage)

Produce a publicly hosted Privacy Policy referenced from app stores listing.

Suggested sections mapped to common LoboHub / Huddle features:

| Topic | Mention in policy? | Notes |
|-------|---------------------|-------|
| Account + auth (Supabase) | □ | Session, JWT, PKCE login |
| Family shared data stored in Postgres | □ | RLS-bound family-visible modules |
| Local device storage (`sembast`/prefs) | □ | Offline cache, tombstones |
| Push notifications (`firebase_messaging`) | □ | Token handling, suppression |
| Health / Fitness integrations | □ | If enabled in your SKU — Apple Health / Health Connect |
| Location | □ | If geolocation surfaces are marketed |
| AI / LLM mediated features | □ | What is sent server-side vs on-device (edge functions) |
| Payments / subscriptions | □ | RC + store receipts |

**Policy URL hosted at:** _________________________  
**Effective date:** _________________________

---

## 3. Terms of Use / Acceptable Use (optional SKU)

Brief outline for counsel:

- Intended audience (family adults vs mixed ages).
- Prohibitions (illegal content, harassment via chat, etc.).
- Limitation of liability / disclaimer of warranties (jurisdiction-dependent).
- Governing law / venue.

Draft URL(s): _________________________

---

## 4. Child safety / minor access (evaluate with counsel)

If minors may realistically use shared devices or receive invites:

| Item | Completed |
|------|-----------|
| Age gate / COPPA-aligned flow assessment | □ Counsel review |
| Parental oversight for paid actions | □ |
| Disclosure of parental access to telemetry | □ |

**Decision:** minors allowed □ Yes (with _____) □ Not targeted

---

## 5. Data deletion / account closure

Operational script (fill for support runbooks):

| Action | Backend step | Verification |
|--------|---------------|---------------|
| User requests erasure | Supabase deletion / pseudonymisation plan | Confirmation email ______ |
| Family owner deletes family | Cascading FK policy ______ | Screenshots QA ______ |

Reference app-side hooks: logout paths call local wipe patterns in [`DatabaseService`](../lib/services/database_service.dart) (`clearLocal`, `wipeAllLocalStorage`).

---

## 6. Platform-specific review queue

### Apple App Store Connect

| Field | Guidance |
|-------|----------|
| App Privacy labels | Align with Sections 2–5 |
| Health frameworks | Declare if binaries link `HealthKit` / Health APIs |
| Sign in with Apple (if offered) | Entitlement completeness |
| Account deletion Deep link requirement | Mandatory since 2022-ish policy churn — confirm path |

### Google Play

| Field | Guidance |
|-------|----------|
| Data Safety form | Map to Sections 2 & 6 |
| Health Connect declaration | Only if SKU uses health package features |
| Content rating questionnaire | Violence / messaging modules |

---

## 7. Pre-submission QA legal-adjacent

| Check | Pass |
|-------|------|
| In-app “Privacy Policy” opens correct HTTPS URL | □ |
| Notification permission rationales truthful | □ |
| Purchase screens show accurate renewal terms where required | □ |

---

## 8. Ownership sign-off

```
Product owner: _________ Date: _____
Legal reviewer: _________ Date: _____
Security / infra reviewer: _________ Date: _____
```

Append links to finalized PDFs/HTML for archive.
