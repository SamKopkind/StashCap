-- Stockpile accounts on Apex branch 6PZ that:
--   1. still hold assets (latest start-of-day total equity > 0)
--   2. are not Stash subscribers (subscription was never activated)
--   3. the minor has not reached age of majority by the end of November 2026
--
-- Warehouse: Redshift. Monolith tables live in source_pg_main.
-- Subscription state lives in source_subscriptions (not the monolith).
--
-- Age of majority is the Stash custodial chart (custodian state on the
-- account; minors.state, falling back to the custodian home state):
--   18: CA, DC, KY, LA, ME, MI, NV, OK, SC, SD, VA
--   21: every other state / territory
-- Source: https://ask.stash.com/ask/age-of-majority/ (updated Aug 11, 2026)
-- Admin source of truth, if you would rather join it: source_pg_main.jurisdictions
--
-- "Won't reach AOM" means still a minor on 2026-11-30: the majority date
-- is 2026-12-01 or later. To also include minors who turn of age during
-- November, change the cutoff in the final WHERE to DATE '2026-11-01'.

WITH age_of_majority AS (
    SELECT 'CA' AS state_code, 18 AS aom_years UNION ALL
    SELECT 'DC', 18 UNION ALL
    SELECT 'KY', 18 UNION ALL
    SELECT 'LA', 18 UNION ALL
    SELECT 'ME', 18 UNION ALL
    SELECT 'MI', 18 UNION ALL
    SELECT 'NV', 18 UNION ALL
    SELECT 'OK', 18 UNION ALL
    SELECT 'SC', 18 UNION ALL
    SELECT 'SD', 18 UNION ALL
    SELECT 'VA', 18
),

branch_accounts AS (
    SELECT
        a.id AS account_id,
        a.atlas_id,
        a.user_id,
        a.account_type,
        a.aasm_state,
        ucs.conversion_source
    FROM source_pg_main.accounts a
    INNER JOIN source_pg_main.user_conversion_sources ucs
        ON ucs.user_id = a.user_id
       AND ucs.conversion_source IN ('Stockpile', 'StockpileExisting')
    WHERE LEFT(a.atlas_id, 3) = '6PZ'
      AND a.account_type = 'CUSTODIAN'
),

latest_sod AS (
    SELECT
        sod.account_id,
        sod.file_date,
        sod.total_equity::decimal(18, 2) AS total_equity,
        sod.cash_equity::decimal(18, 2) AS cash_equity
    FROM (
        SELECT
            sod.account_id,
            sod.file_date,
            sod.total_equity,
            sod.cash_equity,
            ROW_NUMBER() OVER (
                PARTITION BY sod.account_id
                ORDER BY sod.file_date DESC
            ) AS rn
        FROM source_pg_main.start_of_days sod
        INNER JOIN branch_accounts ba
            ON ba.account_id = sod.account_id
        -- Bound the scan to recent files. 6PZ accounts are already filtered.
        WHERE sod.file_date >= DATEADD(day, -14, CURRENT_DATE)
    ) sod
    WHERE sod.rn = 1
      AND sod.total_equity::decimal(18, 2) > 0
),

activated_subscribers AS (
    -- A Stash subscriber is anyone whose subscription was activated.
    -- CREATED with no started_on is onboarding that never finished.
    SELECT DISTINCT s.user_uuid::varchar AS user_uuid
    FROM source_subscriptions.subscriptions s
    WHERE s.active = TRUE
       OR s.state IN ('ACTIVE', 'OFFBOARDING')
       OR s.started_on IS NOT NULL
),

custodial_minors AS (
    SELECT
        ba.atlas_id,
        ba.account_id,
        ba.user_id,
        u.uuid::varchar AS user_uuid,
        ba.aasm_state,
        ba.conversion_source,
        m.first_name AS minor_first_name,
        m.last_name AS minor_last_name,
        m.date_of_birth::date AS minor_date_of_birth,
        CASE UPPER(TRIM(COALESCE(m.state, up.home_state)))
            WHEN 'CA' THEN 'CA'
            WHEN 'CALIFORNIA' THEN 'CA'
            WHEN 'DC' THEN 'DC'
            WHEN 'D.C.' THEN 'DC'
            WHEN 'DISTRICT OF COLUMBIA' THEN 'DC'
            WHEN 'KY' THEN 'KY'
            WHEN 'KENTUCKY' THEN 'KY'
            WHEN 'LA' THEN 'LA'
            WHEN 'LOUISIANA' THEN 'LA'
            WHEN 'ME' THEN 'ME'
            WHEN 'MAINE' THEN 'ME'
            WHEN 'MI' THEN 'MI'
            WHEN 'MICHIGAN' THEN 'MI'
            WHEN 'NV' THEN 'NV'
            WHEN 'NEVADA' THEN 'NV'
            WHEN 'OK' THEN 'OK'
            WHEN 'OKLAHOMA' THEN 'OK'
            WHEN 'SC' THEN 'SC'
            WHEN 'SOUTH CAROLINA' THEN 'SC'
            WHEN 'SD' THEN 'SD'
            WHEN 'SOUTH DAKOTA' THEN 'SD'
            WHEN 'VA' THEN 'VA'
            WHEN 'VIRGINIA' THEN 'VA'
            ELSE UPPER(TRIM(COALESCE(m.state, up.home_state)))
        END AS account_state
    FROM branch_accounts ba
    INNER JOIN source_pg_main.users u
        ON u.id = ba.user_id
    INNER JOIN source_pg_main.minors m
        ON m.account_id = ba.account_id
    LEFT JOIN source_pg_main.user_profiles up
        ON up.user_id = ba.user_id
    WHERE m.date_of_birth IS NOT NULL
)

SELECT
    cm.atlas_id,
    cm.account_id,
    cm.user_id,
    cm.user_uuid,
    cm.aasm_state,
    cm.conversion_source,
    cm.minor_first_name,
    cm.minor_last_name,
    cm.minor_date_of_birth,
    cm.account_state,
    COALESCE(aom.aom_years, 21) AS age_of_majority_years,
    DATEADD(year, COALESCE(aom.aom_years, 21), cm.minor_date_of_birth) AS age_of_majority_date,
    ls.file_date AS equity_file_date,
    ls.total_equity,
    ls.cash_equity,
    (ls.total_equity - COALESCE(ls.cash_equity, 0)) AS securities_equity
FROM custodial_minors cm
INNER JOIN latest_sod ls
    ON ls.account_id = cm.account_id
LEFT JOIN activated_subscribers sub
    ON sub.user_uuid = cm.user_uuid
LEFT JOIN age_of_majority aom
    ON aom.state_code = cm.account_state
WHERE sub.user_uuid IS NULL
  AND DATEADD(year, COALESCE(aom.aom_years, 21), cm.minor_date_of_birth) >= DATE '2026-12-01'
ORDER BY age_of_majority_date, cm.atlas_id;
