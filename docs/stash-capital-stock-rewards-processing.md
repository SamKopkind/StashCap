# How Stash Capital processes stock rewards

Prepared: September 22, 2026  
Google Doc: https://docs.google.com/document/d/1PE3im-psTLe5iYqBiGJBYTNpTh_MJhbi9ulCM3jYewM/edit
Scope: operational process at **Stash Capital LLC** (introducing broker-dealer), after a stock reward has been earned. This is not a product description of Stock-Back®, Stock Party, or referrals, and it is not legal advice.

Confirm Rewards Window timing and settlement-cycle counts with the trading desk before using this in an exam or exam-prep meeting. Those details can change.

---

## 1. What this process is

Stock rewards (Stock-Back® card purchases, Stock Party, referrals, onboarding/single-stock offers, and similar promotions) are **not** filled the same way as everyday client buy orders.

Everyday client orders are bunched, sent as whole-share **agency** market orders through Apex, then allocated (including fractionals) to client accounts.

Stock rewards are filled by **Stash Capital buying shares into its own proprietary inventory**, then **journaling** fully paid positions into the client’s Personal Portfolio **after settlement**. On the client’s activity feed, capacity is **Principal**. The client does **not** receive an Apex/Broadridge trade confirmation for the reward. The statement shows a stock-reward journal, separate from ordinary buy/sell activity.

The rewards **program** is offered and administered by **Stash Investments LLC** (the RIA). Stash Capital is not the program sponsor. Stash Capital’s role is to **purchase and manage inventory** in a proprietary account and to **journal** the position to the client. Stash Investments pays Stash Capital a **service fee** under an inter-affiliate services arrangement for that inventory work.

Until the journal books, the shares are **Stash Capital’s inventory**, not customer securities or customer funds.

---

## 2. Who does what

| Party | Role in rewards |
| --- | --- |
| **Stash Investments LLC** | Determines that a client has earned a dollar-denominated reward, which security, and which account should receive it. Provides Stash Capital with the information needed to size and later journal the reward. Does **not** execute the inventory trade. |
| **Stash Capital LLC** | FINRA-registered introducing broker. A **Stash Capital trader** decides what to buy for the proprietary account, executes those purchases, reports them, and after settlement journals shares to clients. This is broker-dealer proprietary trading, not an RIA-directed customer order. |
| **Apex Clearing** | Qualified custodian and clearing firm. Holds the proprietary inventory account and client accounts. Accepts position journals and remainder-share sell orders. Does not send a customer trade confirm for the journal. |
| **TraFix** | Stash Capital’s OMS. Inventory purchases are reported to the tape / CAT through TraFix. Remainder liquidations via Apex’s Orders API are CAT-reported through Apex. |

Traders on the desk are dual-hatted (supervised by both Investments and Capital). For **rewards inventory**, the buy decision sits with the **broker-dealer**.

---

## 3. Accounts

- **8BO00001 — BD inventory / proprietary account** (“Stash Capital Proprietary Account”). Stash Capital-owned **inventory** account (not an average-price account). Whole-share purchases to cover that day’s rewards land here. Journals to clients come **from** here. Remainder and failed-journal shares are liquidated **from** here. Cash replacements for canceled rewards (corporate actions) have been sourced from this account.
- **8BC99990 — Rewards funding account**. Historically a Stash Financial, Inc.–owned Apex account. Cash that used to be credited to clients for agency reward buys is moved (lump sum, via API once the process was automated; originally a manual BrokOps money movement) to fund 8BO00001 so Capital can pay for whole-share inventory. Ops reviews house-account cash (including topping 8BO00001 if the balance approaches zero) as part of the Friday house-account control.

The inventory account may show positions across the settlement cycle. It is not supposed to carry **aged shorts**. A short would raise Reg SHO locate issues; the desk pads buys and, if needed, buys more before the close (or in after-hours) so the account is covered.

---

## 4. Daily flow (trading day T)

### Step A — Rewards become a buy list

Eligible, completed rewards (Stock-Back swipes, Stock Party, referrals, other stock-reward programs) are aggregated **once per trading day**, by ticker, into a **dollar** amount. Rewards that complete **outside** the Rewards Window wait for the **next** fulfillment day.

Historically the desk pulled this file around **3:00 p.m.** ET. Confirm current window times with the desk.

### Step B — Stash Capital sizes and buys inventory

A Stash Capital trader (using an ops macro / Active Admin tools) converts those dollar totals into **share quantities** using the **reported lowest execution price** of each security on the **fulfillment day**, with **padding**. Padding is larger when the stock is cheap and/or the aggregate reward dollars are large, so a last-hour print below the then-current low still leaves enough shares.

That trader **decides** the whole-share buy into **8BO00001** and sends it to the market (Apex / TraFix). This is **proprietary** buying. It is **not** mixed into the ordinary client-window bunch.

If the book is still short into the close, BrokOps buys additional inventory (including attempting after-hours if an order is underfilled). If the Rewards Window itself cannot run, fulfillment rolls to the next trading day and that day’s low is used.

### Step C — Customer price is locked after the close

After the close, lows of the day are final. The trader uploads a file that:

1. Queues **position journals** to each eligible client at the **fulfillment-day lowest execution price** (truncated to **two decimal places**, Apex’s journal API limit), and
2. Identifies **excess** inventory to be disposed of after journals complete.

Share quantity to the client ≈ reward dollars ÷ that low (subject to the two-decimal truncation used throughout the experience).

Stash’s **execution price** in 8BO00001 will usually differ from the **customer price**. The activity feed shows both, plus the dollar **difference**. Add-on commission is **$0**.

### Step D — Settlement, then journal

Purchases settle in 8BO00001 (U.S. equities are **T+1** today; the 2023 design assumed **T+2**). Only after the position is **settled / fully paid** does Stash Capital journal from 8BO00001 to the client Personal Portfolio via Apex’s **position journal** API.

Stash Capital owns the shares until that journal. The client is not entitled to those shares as customer property before the journal books.

Journals that fail because the account **closed** or became **restricted** between trade and journal are **not** retried into a closed book. Those shares are folded into the same day’s **remainder liquidation**. Failures are logged (Slack / BrokOps visibility).

### Step E — Flatten leftovers

After journals for that batch finish, leftover whole and fractional shares in 8BO00001 — including failed-journal quantity — are sold in a **single** liquidation per ticker/cycle via Apex’s **Orders API** (`internal equity order` / remainder-share sell-off). Additional sells in the same cycle can be rejected by Apex. Tickers that Apex will not fractionally trade are an ops exception (BrokOps is paged; engineering generally does not retry).

The goal is a **flat** residual in 8BO00001 for that cycle, aside from positions still waiting on settlement for later journals.

---

## 5. What the client sees

- **Activity feed:** type Stock Reward; created date; settled/journal date; Stash buy price; customer price (day’s low); difference; capacity **Principal**; journal ID; commission $0. Copy points users to portfolio activity rather than a confirm.
- **Monthly statement:** one stock-reward journal line per reward, **not** grouped with ordinary buys/sells.
- **No Apex trade confirmation** for the reward journal.
- Timing in program terms has varied (**up to 4 business days**, some later versions **up to 10**). Operationally the path is: Rewards Window → inventory trade → settlement → journal.

Some offers require a **claim** (often ~7 days) or pay **cash** instead. After delivery, some programs require the stock (or proceeds) to remain in the brokerage account for **90 days**. The reward is **not** a recommendation to buy that security.

---

## 6. How this differs from ordinary Stash Capital execution

| | Ordinary client order | Stock reward |
| --- | --- | --- |
| Whose order? | Client or managed strategy | Stash Capital proprietary buy, then gift/journal |
| Account first filled | Client (via avg-price / allocation; leftover fractionals to the RIA frac facilitation account) | 8BO00001 inventory |
| Capacity | Agency | Principal (journal) |
| Price to client | Execution / allocation price from the bunched window | Lowest reported execution of the fulfillment day |
| Confirm | Apex/Broadridge confirm | None; activity-feed detail instead |
| Window | Regular trading windows (~four in the current wrap brochure) | Separate Rewards Window |
| Reporting | TraFix / Apex as for customer flow | Inventory buys: TraFix tape/CAT. Remainder sells: Apex Orders API / CAT |

---

## 7. Exceptions BrokOps already runs

**Corporate actions (since ~April 2024).** Pending journals are canceled and replaced with **cash** of the same notional, sourced from **8BO00001**, when BrokOps records splits/reverse splits (traded-not-yet-journaled only; untraded can continue), M&A where the reward name is acquired, buy restrictions, or card retirement. Halts pause **trading**; already-traded journals can still book. Unrecognized Stockton tickers are canceled to cash and the rewards-list owner is notified. Remainder shares after a CA cancel are handled under the BrokOps CA playbook (not always the automated remainder sell).

**Closed / restricted accounts.** Pre-trade filters try to drop ineligible accounts. Closures/restrictions **after** the inventory buy fail the journal; quantity goes into remainder liquidation.

**ACATs (SOP TRAD005).** If a personal brokerage account is closed at Apex after ACAT but cannot be fully closed in Active Admin (open custodial under the same user), stray rewards can land in error account **8BC00101**. BrokOps rebills to **8BC05004**, covers, cancels the AA transaction, and opts the user out of Stock-Back.

**Underfills / window failure.** Buy more before the close or after-hours; or roll the Rewards Window to the next session.

---

## 8. Why the process exists (background, not exam talking points unless asked)

Until October 2023, rewards were filled like customer buys: cash from a house account into the client, then a fractional buy in the next window. Apex charged **per allocation** (on the order of **2.5–3.5¢**), roughly **$40k–$50k/month**. Journaling from inventory removed that allocation bill, let the client receive the **low of the day**, and is why Capital is in a **principal / inventory** posture rather than agency-for-the-client.

Net-capital treatment of inventory (including the haircut on the proprietary book) and the services-agreement fee are Finance / BD-ops items, not client-facing.

---

## 9. Short answers if asked

- **Who is the client’s broker?** Stash Capital introducing; Apex clearing/custody.
- **Who decides the inventory buy?** A Stash Capital trader. The RIA supplies the reward file (ticker, notional, eligible accounts). It does not place the proprietary order.
- **Who owns the shares before the journal?** Stash Capital, in 8BO00001. Not customer funds.
- **How is the client’s price set?** Lowest reported execution of that stock on the fulfillment day (next Rewards Window day if the reward missed today’s window). Truncated to two decimals.
- **Are reward trades mixed with customer market orders?** No. Separate Rewards Window and proprietary account, then a journal.
- **Why no confirm?** Apex journals a position; it is not a customer street-side execution in the client account.
- **Best execution?** Capital’s inventory trades are Capital’s executions (TraFix / Apex). Investments’ best-ex oversight of Capital is about **customer** order flow. Rewards are a disclosed principal/inventory-and-journal path under program terms plus a service fee for inventory.

---

## 10. Sources (internal)

Operational and program-term descriptions, not a substitute for current WSPs or posted T&Cs:

- [Stock Rewards Journaling Process (April 16, 2023)](https://docs.google.com/document/d/1h1UzwaQ4M6xNcfV3YyXhcNnXXQkbV_xN7h25yE2tkx0/edit)
- [Stock Reward Journaling process adjustment overview](https://stashinvest.atlassian.net/wiki/spaces/~5a8c9941d324b531c3d3d369/pages/3520266402/Stock+Reward+Journaling+process+adjustment+overview)
- [PRD: account closures and restrictions during journaling](https://stashinvest.atlassian.net/wiki/spaces/PRODUCTDELIVERY/pages/3751673988)
- [PRD: corporate actions for stock reward journaling](https://stashinvest.atlassian.net/wiki/spaces/PRODUCTDELIVERY/pages/3894378497)
- [Stock Reward on-call guide (position journals / remainder sells)](https://stashinvest.atlassian.net/wiki/spaces/EN/pages/3537469492)
- Brokerage Ops SOP TRAD005 (ACAT stock-reward / trade-through removal)
- Stock Party / stock-reward program terms (Rewards Window, proprietary account, journal on settlement, service fee)
- Companion briefing: [Stash Investments & Stash Capital — How Trading Works](https://docs.google.com/document/d/1VNasMEzemt851JtqprY9ta_6xk0nKpsvlM3BMuAiExM/edit) (Sept 22, 2026)

Use currently posted Stock-Back® / solicitation terms and the current wrap brochure if walking staff through **client-facing** language. This note describes **how Capital actually runs the book**.
