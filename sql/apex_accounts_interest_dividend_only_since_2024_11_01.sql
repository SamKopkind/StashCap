-- Apex accounts with a non-zero start-of-day (SOD) balance on 2026-10-19
-- whose only Apex activity since 2024-11-01 is interest or dividends earned.
--
-- Today is 2026-10-20. The latest completed Apex SOD snapshot is file_date
-- 2026-10-19 (Monday). That is the balance column below.
--
-- Population
--   source_pg_main.accounts.atlas_id is the Apex account number. Accounts
--   without an Atlas ID are not Apex accounts.
--   source_pg_main.start_of_days is one row per (account_id, file_date).
--   total_equity is the SOD equity from EXT981. A balance means total_equity
--   is not zero.
--
-- Activity
--   source_apex.activity_list_eod is Apex EXT1008 (trades, position
--   adjustments, and money movements, including ACH, fees, and corporate
--   actions). accountnumber joins to accounts.atlas_id.
--   Interest and cash dividends are MONEY_MOVEMENTS whose 2-character batch
--   code plus 3-character entry code is one of the codes CashActivityWorker
--   posts as interest or a dividend:
--     OTINT, XCINT  cash-sweep interest
--     FFINT         fully paid securities-lending interest
--     $+DIV         cash dividend
--     DJDIV, DGDIV  dividend J/G variants (cash dividend or capital gain)
--     SPDIV         payment in lieu of a dividend
--   Everything else since 2024-11-01 removes the account: trades, deposits,
--   withdrawals, ACATS, fees, journals, position adjustments, and dividend
--   reinvestment (DVREI), which is a buy rather than a dividend earned.
--
-- Last login is users.current_sign_in_at (Devise trackable), falling back to
-- last_sign_in_at. Last trade is the latest EXT1008 TRADES trade date for
-- that Atlas ID, any time, not only since 2024-11-01.
--
-- Run in Redshift. activity_list_eod is large; the process_date predicate
-- has to stay on that scan.

WITH sod AS (
    SELECT
        account_id,
        CAST(total_equity AS DECIMAL(18, 2)) AS sod_as_of_2026_10_19
    FROM source_pg_main.start_of_days
    WHERE CAST(file_date AS DATE) = DATE '2026-10-19'
      AND CAST(total_equity AS DECIMAL(18, 2)) <> 0
),

apex_accounts AS (
    SELECT
        a.id AS account_id,
        a.atlas_id,
        a.user_id,
        a.account_type,
        a.aasm_state AS account_state
    FROM source_pg_main.accounts AS a
    WHERE a.atlas_id IS NOT NULL
      AND TRIM(a.atlas_id) <> ''
),

-- Any EXT1008 row in the window that is not interest or a dividend earned.
other_activity AS (
    SELECT DISTINCT
        TRIM(act.accountnumber) AS atlas_id
    FROM source_apex.activity_list_eod AS act
    WHERE act.process_date >= DATE '2024-11-01'
      AND act.process_date <= DATE '2026-10-19'
      AND TRIM(act.accountnumber) <> ''
      AND NOT (
          UPPER(TRIM(act.activitytype)) = 'MONEY_MOVEMENTS'
          AND UPPER(TRIM(act.batchcode) || TRIM(act.entrycode)) IN (
              'OTINT',
              'XCINT',
              'FFINT',
              '$+DIV',
              'DJDIV',
              'DGDIV',
              'SPDIV'
          )
      )
),

last_trade AS (
    SELECT
        TRIM(act.accountnumber) AS atlas_id,
        MAX(
            CASE
                WHEN REGEXP_INSTR(TRIM(act.tradedate), '^[0-9]{4}-') > 0
                    THEN CAST(TRIM(act.tradedate) AS DATE)
                WHEN REGEXP_INSTR(TRIM(act.tradedate), '^[0-9]{1,2}/') > 0
                    THEN TO_DATE(TRIM(act.tradedate), 'MM/DD/YYYY')
            END
        ) AS date_of_last_trade
    FROM source_apex.activity_list_eod AS act
    WHERE UPPER(TRIM(act.activitytype)) = 'TRADES'
      AND NULLIF(TRIM(act.tradedate), '') IS NOT NULL
    GROUP BY 1
)

SELECT
    u.uuid,
    aa.atlas_id,
    sod.sod_as_of_2026_10_19,
    CAST(
        COALESCE(u.current_sign_in_at, u.last_sign_in_at) AS DATE
    ) AS date_of_last_login,
    lt.date_of_last_trade,
    aa.account_type,
    aa.account_state
FROM sod
INNER JOIN apex_accounts AS aa
    ON aa.account_id = sod.account_id
INNER JOIN source_pg_main.users AS u
    ON u.id = aa.user_id
LEFT JOIN last_trade AS lt
    ON lt.atlas_id = aa.atlas_id
WHERE NOT EXISTS (
    SELECT 1
    FROM other_activity AS oa
    WHERE oa.atlas_id = aa.atlas_id
)
ORDER BY aa.atlas_id;
