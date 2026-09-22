# How Stash Capital completes a normal trading window

Prepared: September 22, 2026  
Scope: operational process at **Stash Capital LLC** for an ordinary (non-rewards) trading window. This is not a description of the Rewards Window / 8BO00001 inventory-and-journal path. Confirm window times with the desk before using this in an exam.

Google Doc: https://docs.google.com/document/d/1ZvUxiEIcHniqZdkM8eDxWzA8-pHm3lbmBi6cv_3U2os/edit

---

## 1. What a “normal window” is

Stash Capital **does not accept retail customer orders**. Clients enter dollar (or sell-all) **indications** with **Stash Investments LLC**. The RIA bunches those indications into four windows on a regular market day, converts them to **whole-share institutional orders**, and hands those orders to Capital as **agency, market not-held**.

Capital’s job in the window is to:

1. **Accept** the RIA’s whole-share order list (Slack audit trail, then TraFix),
2. **Route** it to Apex on the **APEX MNGD** destination,
3. **Receive** fills in the **average-price account 8BC00001**,
4. **Return** average prices so the RIA can allocate fractionals to clients and leftover fractionals to the RIA facilitation book,
5. **Book** those allocations at Apex (Braggart), then
6. **Flatten** leftover whole shares in the house inventory account (**8BC05001** sell-down).

Street-side executions print under **Apex’s MPID**. Apex chooses the venues. Capital is the introducing broker using TraFix; it is not a market maker and does not fill client orders out of proprietary inventory in this path.

That is the opposite of stock rewards, where Capital **buys for its own inventory (8BO00001)** and later journals as **principal**.

---

## 2. Who does what

| Party | Role in a normal window |
| --- | --- |
| **Client** | Enters buy/sell indications in the app (Purchase from Balance, Purchase with Deposit, AutoStash, dollar sell, or sell-all). Not a live order ticket to Capital. |
| **Stash Investments (RIA)** | Locks the window, aggregates dollar/share intent by ticker and side, sizes whole-share buys and sells (with padding), and **instructs** Capital. Allocates fills, including fractionals, after average prices come back. |
| **Stash Capital (BD)** | Licensed trader (Series 7/63/57) **acknowledges** the RIA file, imports it to TraFix, sends not-held market orders, exports fills, and runs sell-down / SoD recon. Dual-hatted BrokOps sit on both sides of the Slack handoff. |
| **Apex** | Clearing/custody. Routes via MNGD, executes under Apex MPID, books Braggart allocations, produces confirms (Broadridge) and T+1 start-of-day files. |
| **TraFix** | Capital’s OMS. Order tickets, CAT, booking. Route for the window is **APEXMNGD** (fallback discussed with Apex: MNGD2 / QUIKFLEX for after-hours excess). |

The RIA **does** decide *what* aggregated whole-share orders to send for the window. Capital **does** decide *how* those agency orders go to market (import, send, monitor fills, underfills, rejects). That is different from rewards inventory, where a Capital trader decides the proprietary buy.

---

## 3. Accounts

- **8BC00001** — Stash Capital **average-price execution account**. Whole-share window orders execute here, then allocate out to clients.
- **RIA fractional facilitation** (historically **8BC00002**) — leftover **fraction** after client allocations. Managed in whole shares over time; not mixed with reward inventory.
- **8BC05001** — house **inventory / excess** used for the **5001 sell-down** of leftover whole shares after a window. Last-window material excess can be limited after-hours via TraFix **APEX QUIKFLEX** into 8BC05001.
- Client Apex accounts — receive Braggart allocations; cash/positions from Apex SoD files reset buying power each morning.

Buys and sells are **not netted against each other** and are **not filled from inventory**. Agency: one aggregate **buy** and/or one aggregate **sell** per security (large orders may be split for Apex risk limits).

---

## 4. When windows run

Regular session (Eastern; `Holidays` table in the monolith):

| Window | Lock (approx.) | Typical extra content |
| --- | --- | --- |
| W1 Early morning | **9:40 a.m.** (SOP also cites 9:45) | First lock of the day; oversell pricing list refreshed |
| W2 Late morning | **11:40 a.m.** | Robo / AutoStash into managed accounts |
| W3 Mid-afternoon | **1:40 p.m.** | AutoStash executions |
| W4 Last | **3:40 p.m.** | Last regular window; excess check if 5001 sell-down cannot finish |

Early-close days run **three** windows. Fewer windows in stressed or short sessions. There is **no promise** a given indication hits a particular clock time. Indications can be entered between windows; they join the **next** lock. Purchase-with-deposit / AutoStash wait until funding is acknowledged (ACH queued, or Stride journal **COMPLETE**) before they are eligible.

A `TransactionLockJob` locks eligible transactions to the window. After lock they cannot be client-canceled without ops. Slack **#trading** pings BrokOps to start.

---

## 5. Window lifecycle (Capital’s cut)

### Before the lock (RIA / funding)

Clients submit indications 24/7. Purchase from Balance is capped by Apex-sourced buying power (SoD, then decremented intraday). PWD/AutoStash: Capital’s cash API path to Apex (ACH or Stride journal) must post before the RIA will put the trade in a window. Oversell tool: dollar sells that would dump **>90%** of a position are swapped to **sell-all** using a pricing file (Looker cards list on W1).

### Step A — Lock and size (RIA BrokOps)

1. Window locks; **#trading** notification.
2. Current Trades → **Download User Orders**: locked transactions aggregated by **ticker and side** (buy vs sell; dollars and sell-all shares).
3. Order-entry macro (or order-creation service) converts dollars to whole shares at a live price, **pads**, **rounds up**. Halted/unpriced names go to exceptions / cancel-by-ticker and a re-download.
4. Output: **RIA Orders** CSV — whole-share BUY/SELL, account **8BC00001**.

### Step B — Handoff to Capital (the BD moment)

1. File posted to **#stash_capital_trading** as `RIA Orders MM.DD.YYYY – AM/PM 1/2` with the instruction **“orders for execution.”**
2. Auto **“Acknowledged”** in that channel is the RIA→BD instruction. **Only then** does Capital stage and send.
3. Same dual-hatted trader often prepares *and* executes; Slack is the compliance audit trail for the handoff (TraFix/CAT still report the street orders).

### Step C — TraFix send (Capital)

1. Sign in to TraFix. Import the CSV (`Text1` = window id, e.g. AM1 / PM2). **Select All → Send.**
2. Orders are **market not-held** on **APEXMNGD**. Apex independently routes; prints are **Apex MPID**.
3. Blotter: **Exec Qty = Qty**. Partial fills (**P-Filled**), rejects, or unroutable names are worked (reprice, cancel tool, Apex risk-limit call if needed).
4. **Export All** fills to `BrokerDealer Trades` / `BD Fills MM.DD.YYYY AM/PM`.

Capital does **not** stop an eligible window order on a business whim. Stops are for halt, corp action, sanction, or Apex ineligibility.

### Step D — Average price back to the RIA

1. Upload BD fills on Current Trades → **Fill in Fields**.
2. System checks that executed shares cover locked intent. **Unsuccessful → Download Under Fills**, new RIA Orders file, same Slack “orders for execution,” more TraFix, then **recompute average price** across original + extra fills and re-upload.
3. When unsuccessful = 0 → **Create Trades**. Each fill row becomes a `Trade` (side, shares, price). Workers assign share quantities to each locked `Transaction` at the window average and mark them **traded**.
4. Remainder = traded whole shares minus client allocations. That residual is **not** carried as a customer order; it is house leftover (frac book / 5001). **Each window is a fresh run** — it does not consume leftovers from the prior window.

Allocation policy (wrap / order instructions): complete fills as specified on the order before send; **partials pro rata**; exceptions noted on the order.

### Step E — Complete books and Braggart

1. **#trading**: allocations done → Trades screen → **Complete Intraday Transactions** (portfolio/unrealized).
2. **#tradersonly**: ping the **5001 sell-down** owner for that window.
3. Braggart allocations to Apex are **automatic** once transactions complete (ops no longer clicks Kickoff Braggart). Apex acks; Broadridge confirms. Client sees allocation in-app and an email to the Apex confirm.
4. **#traders_only** when Braggart has posted. That **closes the window**.

### Step F — Flatten 5001 and T+1

- Inventory sell-down trades leftover whole shares out of **8BC05001**. If the last window has no time, **Excess Check**: material leftovers sold after-hours, **limit within ~5% of last print**, account **8BC05001**, route **APEX QUIKFLEX**.
- **T+1 ~4–5 a.m.**: Apex SoD files. Capital/BrokOps reconcile Apex vs monolith. Breaks → allocation rebook to Apex. Buying power for the next day is **reset from Apex**, not inventively leftover from Stash.

---

## 6. What the client sees

- Indication pending until the window that locked it is filled and Braggart-posted.
- **Apex/Broadridge trade confirmation** (unlike stock-reward journals).
- Fill at the **window average price** for that security/side, including their fractional piece.
- Cash from sells is not withdrawable until Apex includes it in **available balance** (settlement).

---

## 7. How this differs from the Rewards Window

| | Normal window | Rewards |
| --- | --- | --- |
| Capital’s customer | RIA (institutional whole shares) | None — proprietary inventory |
| First account | **8BC00001** average price | **8BO00001** inventory |
| Capacity | **Agency** | **Principal** journal |
| Client price | Window **average** | Fulfillment-day **low** |
| Confirm | Apex/Broadridge | None |
| Leftovers | Frac facilitation + **5001** sell-down | Orders API remainder sell |
| Handoff | Slack “orders for execution” | Rewards file / 3 p.m. inventory list |

---

## 8. Short answers if asked

- **Does Capital take the customer’s order?** No. It takes the RIA’s aggregated whole-share, not-held market order.
- **Who sends it to the street?** Capital via TraFix → APEX MNGD; Apex executes and prints.
- **Whose MPID?** Apex.
- **Average price account?** 8BC00001.
- **Can Capital fill a client from inventory?** Not on this path. Buys and sells stay separate; leftover is allocated/sold as house, not crossed into the next client.
- **Partials?** Pro rata to the pre-specified allocation; then underfill file and another send if the book is still short of client dollars.
- **When is the window done?** Braggart posted for that window’s trades, plus 5001 working leftover, not when TraFix first shows filled.
- **Best execution?** Capital’s not-held market orders to Apex; Investments reviews Capital’s execution quality and adopts Capital’s procedures.

---

## 9. Sources (internal)

- Brokerage Ops SOP **TRAD006 Allocation Trading** (reviewed 3/10/2026)
- [Stash Capital — Trading](https://docs.google.com/document/d/1pvKcNjaS3vwROGY0DH4eTdRit5YoXp-OXgtP8nBNnKg/edit) (March 2026 order-lifecycle memo)
- [Stash Trading baseline facts](https://docs.google.com/document/d/1gkrbbiIoHxaQmJiCy5yUUQWHbVUbzF2K1dTAhOyhriw/edit)
- [Trading Overview](https://stashinvest.atlassian.net/wiki/spaces/PRODUCTDELIVERY/pages/3663265926/Trading+Overview)
- [Regular Trading Schedule](https://stashinvest.atlassian.net/wiki/spaces/PRODUCTDELIVERY/pages/3663167690/Regular+Trading+Schedule)
- [Brokerage Automation PRD: Order Creation](https://stashinvest.atlassian.net/wiki/spaces/PRODUCTDELIVERY/pages/3877699672)
- Companion: [How Stash Capital processes stock rewards](docs/stash-capital-stock-rewards-processing.md)
