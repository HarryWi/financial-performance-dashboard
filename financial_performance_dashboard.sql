/* ============================================================================
  Coffee Shop - Financial Performance Dashboard (Postgres + Power BI)
  Author: Hampus Willfors
  Purpose: Minimal, reproducible pipeline for SME financials
  Schemas: staging (raw), analytics (typed/clean), views for Power BI
============================================================================ */

-- ======================================
-- 1) Schemas
-- ======================================
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS analytics;

-- ======================================
-- 2) Staging tables (raw CSV import)
--    Keep everything as TEXT to avoid import issues.
-- ======================================

-- 2.1 Checking account (main)
DROP TABLE IF EXISTS staging.checking_account_main_raw;
CREATE TABLE staging.checking_account_main_raw (
  date            TEXT,
  transaction_id  TEXT,
  description     TEXT,
  category        TEXT,
  type            TEXT,
  amount          TEXT,
  balance         TEXT
);

-- 2.2 Checking account (secondary)
DROP TABLE IF EXISTS staging.checking_account_secondary_raw;
CREATE TABLE staging.checking_account_secondary_raw (
  date            TEXT,
  transaction_id  TEXT,
  description     TEXT,
  category        TEXT,
  type            TEXT,
  amount          TEXT,
  balance         TEXT
);

-- 2.3 Credit card account
DROP TABLE IF EXISTS staging.credit_card_account_raw;
CREATE TABLE staging.credit_card_account_raw (
  date            TEXT,
  transaction_id  TEXT,
  description     TEXT,
  category        TEXT,
  type            TEXT,
  amount          TEXT,
  balance         TEXT
);

-- 2.4 Payroll (transactions)
DROP TABLE IF EXISTS staging.gusto_payroll_raw;
CREATE TABLE staging.gusto_payroll_raw (
  pay_date       TEXT,
  employee_id    TEXT,
  employee_name  TEXT,
  role           TEXT,
  type           TEXT,
  amount         TEXT,
  account        TEXT
);

-- 2.5 Payroll benefits / contributions (detailed)
DROP TABLE IF EXISTS staging.gusto_payroll_bc_raw;
CREATE TABLE staging.gusto_payroll_bc_raw (
  Employee_ID             TEXT,
  Employee_Name           TEXT,
  Role                    TEXT,
  Pay_Date                TEXT,
  Gross_Pay               TEXT,
  Federal_Tax             TEXT,
  Provincial_Tax          TEXT,
  CPP                     TEXT,
  EI                      TEXT,
  Other_Deductions        TEXT,
  Net_Pay                 TEXT,
  Employer_CPP            TEXT,
  Employer_EI             TEXT,
  Tips                    TEXT,
  Travel_Reimbursement    TEXT
);

-- ======================================
-- 3) Load data (outside SQL)
--    Use pgAdmin Import/Export (CSV, HEADER) into staging tables,
--    or psql: \copy staging.table FROM '/path/file.csv' CSV HEADER
-- ======================================


-- ======================================
-- 4) Transform RAW -> ANALYTICS (typed)
--    Simple casts:
--      - Dates: supports DD.MM.YYYY and YYYY-MM-DD
--      - Numbers: replace comma-decimals and strip apostrophes
-- ======================================

-- 4.1 Checking: MAIN
DROP TABLE IF EXISTS analytics.checking_account_main;
CREATE TABLE analytics.checking_account_main AS
SELECT
  CASE
    WHEN date ~ '^\d{2}\.\d{2}\.\d{4}$' THEN to_date(date, 'DD.MM.YYYY')
    WHEN date ~ '^\d{4}-\d{2}-\d{2}$'   THEN to_date(date, 'YYYY-MM-DD')
    ELSE NULL
  END                                                       AS txn_date,
  transaction_id,
  description,
  category,
  type,
  NULLIF(REPLACE(REPLACE(amount,  '''',''), ',', '.'), '')::numeric AS amount,
  NULLIF(REPLACE(REPLACE(balance, '''',''), ',', '.'), '')::numeric AS balance
FROM staging.checking_account_main_raw;

-- 4.2 Checking: SECONDARY
DROP TABLE IF EXISTS analytics.checking_account_secondary;
CREATE TABLE analytics.checking_account_secondary AS
SELECT
  CASE
    WHEN date ~ '^\d{2}\.\d{2}\.\d{4}$' THEN to_date(date, 'DD.MM.YYYY')
    WHEN date ~ '^\d{4}-\d{2}-\d{2}$'   THEN to_date(date, 'YYYY-MM-DD')
    ELSE NULL
  END                                                       AS txn_date,
  transaction_id,
  description,
  category,
  type,
  NULLIF(REPLACE(REPLACE(amount,  '''',''), ',', '.'), '')::numeric AS amount,
  NULLIF(REPLACE(REPLACE(balance, '''',''), ',', '.'), '')::numeric AS balance
FROM staging.checking_account_secondary_raw;

-- 4.3 Checking: union (all bank transactions)
DROP TABLE IF EXISTS analytics.checking_account_all;
CREATE TABLE analytics.checking_account_all AS
SELECT *, 'Main'::text AS account_source FROM analytics.checking_account_main
UNION ALL
SELECT *, 'Secondary'::text AS account_source FROM analytics.checking_account_secondary;

-- 4.4 Credit card
DROP TABLE IF EXISTS analytics.credit_card_account;
CREATE TABLE analytics.credit_card_account AS
SELECT
  CASE
    WHEN date ~ '^\d{2}\.\d{2}\.\d{4}$' THEN to_date(date, 'DD.MM.YYYY')
    WHEN date ~ '^\d{4}-\d{2}-\d{2}$'   THEN to_date(date, 'YYYY-MM-DD')
    ELSE NULL
  END                                                       AS txn_date,
  transaction_id,
  description,
  category,
  type,
  NULLIF(REPLACE(REPLACE(amount,  '''',''), ',', '.'), '')::numeric AS amount,
  NULLIF(REPLACE(REPLACE(balance, '''',''), ',', '.'), '')::numeric AS balance
FROM staging.credit_card_account_raw;

-- 4.5 Payroll (transactions)
DROP TABLE IF EXISTS analytics.gusto_payroll;
CREATE TABLE analytics.gusto_payroll AS
SELECT
  CASE
    WHEN pay_date ~ '^\d{2}\.\d{2}\.\d{4}$' THEN to_date(pay_date, 'DD.MM.YYYY')
    WHEN pay_date ~ '^\d{4}-\d{2}-\d{2}$'   THEN to_date(pay_date, 'YYYY-MM-DD')
    ELSE NULL
  END                                                       AS pay_date,
  employee_id,
  employee_name,
  role,
  type,
  NULLIF(REPLACE(REPLACE(amount,  '''',''), ',', '.'), '')::numeric AS amount,
  account
FROM staging.gusto_payroll_raw;

-- 4.6 Payroll benefits / contributions (typed)
DROP TABLE IF EXISTS analytics.gusto_payroll_bc;
CREATE TABLE analytics.gusto_payroll_bc AS
SELECT
  employee_id,
  employee_name,
  role,
  CASE
    WHEN pay_date ~ '^\d{2}\.\d{2}\.\d{4}$' THEN to_date(pay_date, 'DD.MM.YYYY')
    WHEN pay_date ~ '^\d{4}-\d{2}-\d{2}$'   THEN to_date(pay_date, 'YYYY-MM-DD')
    ELSE NULL
  END                                                       AS pay_date,
  NULLIF(REPLACE(REPLACE(gross_pay,            '''',''), ',', '.'), '')::numeric AS gross_pay,
  NULLIF(REPLACE(REPLACE(federal_tax,          '''',''), ',', '.'), '')::numeric AS federal_tax,
  NULLIF(REPLACE(REPLACE(provincial_tax,       '''',''), ',', '.'), '')::numeric AS provincial_tax,
  NULLIF(REPLACE(REPLACE(cpp,                  '''',''), ',', '.'), '')::numeric AS cpp,
  NULLIF(REPLACE(REPLACE(ei,                   '''',''), ',', '.'), '')::numeric AS ei,
  NULLIF(REPLACE(REPLACE(other_deductions,     '''',''), ',', '.'), '')::numeric AS other_deductions,
  NULLIF(REPLACE(REPLACE(net_pay,              '''',''), ',', '.'), '')::numeric AS net_pay,
  NULLIF(REPLACE(REPLACE(employer_cpp,         '''',''), ',', '.'), '')::numeric AS employer_cpp,
  NULLIF(REPLACE(REPLACE(employer_ei,          '''',''), ',', '.'), '')::numeric AS employer_ei,
  NULLIF(REPLACE(REPLACE(tips,                 '''',''), ',', '.'), '')::numeric AS tips,
  NULLIF(REPLACE(REPLACE(travel_reimbursement, '''',''), ',', '.'), '')::numeric AS travel_reimbursement
FROM staging.gusto_payroll_bc_raw;

-- 4.7 Indexes (speed up date filters/joins)
CREATE INDEX IF NOT EXISTS ix_checking_main_date       ON analytics.checking_account_main (txn_date);
CREATE INDEX IF NOT EXISTS ix_checking_secondary_date  ON analytics.checking_account_secondary (txn_date);
CREATE INDEX IF NOT EXISTS ix_checking_all_date        ON analytics.checking_account_all (txn_date);
CREATE INDEX IF NOT EXISTS ix_cc_date                  ON analytics.credit_card_account (txn_date);
CREATE INDEX IF NOT EXISTS ix_payroll_date             ON analytics.gusto_payroll (pay_date);
CREATE INDEX IF NOT EXISTS ix_payroll_bc_date          ON analytics.gusto_payroll_bc (pay_date);

-- ======================================
-- 5) Views / Tables for Power BI
-- ======================================

-- 5.1 Calendar (safe build; handles empty source tables)
DROP TABLE IF EXISTS analytics.dim_calendar;
CREATE TABLE analytics.dim_calendar AS
WITH mins AS (
  SELECT MIN(txn_date) AS dt FROM analytics.checking_account_all
  UNION ALL SELECT MIN(txn_date) FROM analytics.credit_card_account
  UNION ALL SELECT MIN(pay_date) FROM analytics.gusto_payroll
),
maxs AS (
  SELECT MAX(txn_date) AS dt FROM analytics.checking_account_all
  UNION ALL SELECT MAX(txn_date) FROM analytics.credit_card_account
  UNION ALL SELECT MAX(pay_date) FROM analytics.gusto_payroll
),
bounds AS (
  SELECT MIN(dt) AS dmin, MAX(dt) AS dmax FROM mins
),
bounds2 AS (
  SELECT
    COALESCE((SELECT dmin FROM bounds), CURRENT_DATE) AS dmin,
    COALESCE((SELECT MAX(dt) FROM maxs), CURRENT_DATE) AS dmax
),
series AS (
  SELECT generate_series((SELECT dmin FROM bounds2),
                         (SELECT dmax FROM bounds2),
                         interval '1 day')::date AS d
)
SELECT
  s.d                                AS date,
  date_trunc('month', s.d)::date     AS month_start,
  EXTRACT(YEAR    FROM s.d)::int     AS year,
  EXTRACT(QUARTER FROM s.d)::int     AS quarter,
  EXTRACT(MONTH   FROM s.d)::int     AS month,
  TO_CHAR(s.d, 'YYYY-MM')            AS year_month
FROM series s
ORDER BY s.d;

CREATE INDEX IF NOT EXISTS ix_dim_calendar_date ON analytics.dim_calendar(date);

-- 5.2 Unified transactions (bank + credit card + payroll)
--     Normalized signs:
--       + inflow, - outflow
CREATE OR REPLACE VIEW analytics.v_fact_cash_txn AS
-- Bank: flip common outflow types to negative
SELECT
  txn_date,
  transaction_id,
  description,
  category,
  type,
  CASE
    WHEN lower(type) IN ('debit','withdrawal','payment','expense') THEN -amount
    ELSE amount
  END AS amount,
  balance,
  account_source AS source
FROM analytics.checking_account_all

UNION ALL

-- Credit card: treat positive charges as outflows
SELECT
  txn_date,
  transaction_id,
  description,
  category,
  type,
  CASE WHEN amount > 0 THEN -amount ELSE amount END AS amount,
  balance,
  'CreditCard' AS source
FROM analytics.credit_card_account

UNION ALL

-- Payroll: always outflow (make negative if positive)
SELECT
  pay_date AS txn_date,
  employee_id AS transaction_id,
  employee_name || ' | ' || role AS description,
  'Payroll' AS category,
  type,
  CASE WHEN amount > 0 THEN -amount ELSE amount END AS amount,
  NULL::numeric AS balance,
  'Payroll' AS source
FROM analytics.gusto_payroll;

-- 5.3 Monthly P&L (Revenue, Expenses, Net Income) from transactions
CREATE OR REPLACE VIEW analytics.v_monthly_pnl AS
SELECT
  c.month_start AS month,
  SUM(CASE WHEN f.amount > 0 THEN f.amount ELSE 0 END)        AS revenue,
  SUM(CASE WHEN f.amount < 0 THEN -f.amount ELSE 0 END)       AS expenses,
  SUM(f.amount)                                               AS net_income
FROM analytics.dim_calendar c
LEFT JOIN analytics.v_fact_cash_txn f
  ON f.txn_date = c.date
GROUP BY c.month_start
ORDER BY c.month_start;

-- 5.4 Monthly cash flow (net in/out)
CREATE OR REPLACE VIEW analytics.v_monthly_cashflow AS
SELECT
  date_trunc('month', txn_date)::date AS month,
  SUM(amount) AS net_cash_flow
FROM analytics.v_fact_cash_txn
GROUP BY 1
ORDER BY 1;

-- 5.5 Monthly payroll breakdown (from detailed file)
CREATE OR REPLACE VIEW analytics.v_monthly_payroll AS
SELECT
  date_trunc('month', pay_date)::date AS month,
  SUM(gross_pay)            AS gross_pay,
  SUM(federal_tax)          AS federal_tax,
  SUM(provincial_tax)       AS provincial_tax,
  SUM(cpp)                  AS cpp,
  SUM(ei)                   AS ei,
  SUM(other_deductions)     AS other_deductions,
  SUM(net_pay)              AS net_pay,
  SUM(employer_cpp)         AS employer_cpp,
  SUM(employer_ei)          AS employer_ei,
  SUM(tips)                 AS tips,
  SUM(travel_reimbursement) AS travel_reimbursement
FROM analytics.gusto_payroll_bc
GROUP BY 1
ORDER BY 1;

-- 5.6 Daily running cash balance (bank-only to avoid CC/payroll double-counting)
CREATE OR REPLACE VIEW analytics.v_daily_cash_balance AS
WITH bank_only AS (
  SELECT txn_date, amount
  FROM analytics.v_fact_cash_txn
  WHERE source IN ('Main','Secondary')      -- only bank cash movements
),
daily AS (
  SELECT c.date, COALESCE(SUM(b.amount), 0) AS daily_net
  FROM analytics.dim_calendar c
  LEFT JOIN bank_only b ON b.txn_date = c.date
  GROUP BY c.date
)
SELECT
  date,
  SUM(daily_net) OVER (ORDER BY date ROWS UNBOUNDED PRECEDING) AS cash_balance
FROM daily
ORDER BY date;

-- 5.7 Expense by category per month
CREATE OR REPLACE VIEW analytics.v_expense_by_category_month AS
SELECT
  date_trunc('month', txn_date)::date AS month,
  COALESCE(NULLIF(category,''), '(Uncategorized)') AS category,
  SUM(CASE WHEN amount < 0 THEN -amount ELSE 0 END) AS expenses
FROM analytics.v_fact_cash_txn
GROUP BY 1,2
ORDER BY 1,3 DESC;
