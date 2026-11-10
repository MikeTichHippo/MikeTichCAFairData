-- Q3. HHIP (Hippo-owned, dim_policies) accident-year loss ratio by state x product x carrier x CAT, plus CA wildfire-score quintile.
-- Stacked output: row_type = 'earned' (calendar-year earned premium) or 'loss' (accident-year incurred, latest knowledge date).
-- LR = SUM(loss total_incurred) / SUM(earned in_month_earned) for the same year/state/etc.
-- premium_type is kept as a column so we can confirm which types to include before computing LR.
WITH pol AS (
  SELECT policy_id, UPPER(state) AS state, product, region_code, wildfire_risk_score, cat_risk
  FROM `datateam-248616.dw_prod.dim_policies`
),
ca_cuts AS (
  SELECT APPROX_QUANTILES(wildfire_risk_score, 5) AS q
  FROM pol WHERE state = 'CA' AND wildfire_risk_score IS NOT NULL
),
pol_band AS (
  SELECT p.*,
    CASE
      WHEN p.state != 'CA' THEN NULL
      WHEN p.wildfire_risk_score IS NULL THEN 'No score'
      WHEN p.wildfire_risk_score <= c.q[OFFSET(1)] THEN 'Q1 (lowest)'
      WHEN p.wildfire_risk_score <= c.q[OFFSET(2)] THEN 'Q2'
      WHEN p.wildfire_risk_score <= c.q[OFFSET(3)] THEN 'Q3'
      WHEN p.wildfire_risk_score <= c.q[OFFSET(4)] THEN 'Q4'
      ELSE 'Q5 (highest)'
    END AS ca_wildfire_band
  FROM pol p CROSS JOIN ca_cuts c
),
earned AS (
  SELECT
    'earned' AS row_type,
    EXTRACT(YEAR FROM e.date_accounting) AS year,
    UPPER(e.state) AS state, e.product, e.carrier, pb.region_code, pb.ca_wildfire_band, e.premium_type,
    CAST(NULL AS BOOL) AS is_cat, CAST(NULL AS STRING) AS peril_group,
    SUM(e.in_month_earned) AS earned_premium,
    SUM(e.written_in_month) AS written_premium,
    CAST(NULL AS BIGNUMERIC) AS loss_incurred, CAST(NULL AS BIGNUMERIC) AS expense_incurred,
    CAST(NULL AS BIGNUMERIC) AS total_incurred, CAST(NULL AS INT64) AS claims
  FROM `datateam-248616.dw_prod_extracts.ext_written_earned_unearned_monthly_premium` e
  LEFT JOIN pol_band pb ON pb.policy_id = e.policy_id
  WHERE e.date_accounting >= DATE '2021-01-01'
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
),
claims AS (
  SELECT c.*
  FROM `datateam-248616.dw_prod_extracts.ext_claims_inception_to_date` c
  WHERE c.date_knowledge = (SELECT MAX(date_knowledge) FROM `datateam-248616.dw_prod_extracts.ext_claims_inception_to_date`)
),
loss AS (
  SELECT
    'loss' AS row_type,
    EXTRACT(YEAR FROM c.date_of_loss) AS year,
    UPPER(c.state) AS state, c.product, c.carrier, pb.region_code, pb.ca_wildfire_band, CAST(NULL AS STRING) AS premium_type,
    c.is_cat, c.peril_group,
    CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC),
    SUM(c.loss_calculated_incurred), SUM(c.expense_calculated_incurred), SUM(c.total_incurred), SUM(c.claim_count)
  FROM claims c
  LEFT JOIN pol_band pb ON pb.policy_id = c.policy_id
  WHERE c.date_of_loss >= DATE '2021-01-01'
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
)
SELECT * FROM earned
UNION ALL
SELECT * FROM loss
ORDER BY state, year, row_type
