-- Delaware customers with bank or brokerage property escheated in the
-- rolling two-year period ending today.
--
-- Addresses are the customers' current home addresses. The Stride bank
-- account UUID is used as the account identifier because the source does not
-- expose a bank account number.

WITH apex_escheatments AS (
    SELECT
        activity.accountnumber::varchar AS account_number,
        COALESCE(profiles.home_street_address || ', ', '')
            || COALESCE(profiles.home_city || ', ', '')
            || UPPER(profiles.home_state)
            || COALESCE(' ' || profiles.home_postal_code, '') AS address,
        UPPER(profiles.home_state) AS state_of_address,
        CASE
            WHEN NULLIF(TRIM(activity.symbol), '') IS NOT NULL THEN
                'Security: '
                    || TRIM(activity.symbol)
                    || CASE
                        WHEN NULLIF(TRIM(activity.cusip), '') IS NOT NULL
                            THEN ' (CUSIP ' || TRIM(activity.cusip) || ')'
                        ELSE ''
                    END
                    || CASE
                        WHEN activity.quantity IS NOT NULL
                            THEN ', quantity ' || activity.quantity::varchar
                        ELSE ''
                    END
            ELSE 'Cash, amount ' || activity.netamount::varchar
        END AS what_was_escheated,
        activity.process_date::date AS when_escheated
    FROM source_apex.activity_list_eod AS activity
    INNER JOIN source_pg_main.users AS users
        ON users.apex_atlas_account_id = activity.accountnumber
    INNER JOIN source_pg_main.user_profiles AS profiles
        ON profiles.user_id = users.id
    WHERE activity.batchcode = 'ES'
        AND UPPER(TRIM(profiles.home_state)) = 'DE'
        AND activity.process_date >= DATEADD(year, -2, CURRENT_DATE)
        AND activity.process_date < DATEADD(day, 1, CURRENT_DATE)
),

stride_escheatments AS (
    SELECT
        transactions.bank_account_uuid::varchar AS account_number,
        COALESCE(profiles.home_street_address || ', ', '')
            || COALESCE(profiles.home_city || ', ', '')
            || UPPER(profiles.home_state)
            || COALESCE(' ' || profiles.home_postal_code, '') AS address,
        UPPER(profiles.home_state) AS state_of_address,
        'Bank account cash, amount '
            || transactions.amount::varchar
            || ' (transaction code '
            || transactions.raw_transaction_code
            || ')' AS what_was_escheated,
        transactions.posted_at::date AS when_escheated
    FROM mart_v2.silver__fct_bank_transactions AS transactions
    INNER JOIN source_pg_main.users AS users
        ON users.uuid = transactions.stash_user_uuid
    INNER JOIN source_pg_main.user_profiles AS profiles
        ON profiles.user_id = users.id
    WHERE transactions.raw_transaction_code IN ('CHK005', 'CHK002', 'CHK007')
        AND UPPER(TRIM(profiles.home_state)) = 'DE'
        AND transactions.posted_at >= DATEADD(year, -2, CURRENT_DATE)
        AND transactions.posted_at < DATEADD(day, 1, CURRENT_DATE)
)

SELECT
    account_number,
    address,
    state_of_address,
    what_was_escheated,
    when_escheated
FROM apex_escheatments

UNION ALL

SELECT
    account_number,
    address,
    state_of_address,
    what_was_escheated,
    when_escheated
FROM stride_escheatments

ORDER BY when_escheated DESC, account_number;
