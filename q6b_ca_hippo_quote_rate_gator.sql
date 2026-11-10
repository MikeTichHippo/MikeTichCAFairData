-- Q6b. Replaces Q6: dim_gator_quote_requests.hippo_quote_status came back NULL on every CA request,
-- so measure Hippo's quote rate from the carrier-level Gator quotes instead (carrier_name = 'Hippo').
-- For CA home requests (2025+), split by where the customer actually bound: did Hippo attempt, quote, and why not.
-- Successful Hippo quote share among FAIR / non-admitted binds = Phase 1 (current-paper) eligibility.
WITH req AS (
  SELECT gator_quote_request_id,
    DATE_TRUNC(DATE(timestamp_gator_quote_created), QUARTER) AS quarter,
    product, SUBSTR(zip_code, 1, 3) AS zip3, bound_carrier,
    is_policy_bound AND flag_exclude_policy IS NULL AS is_bound
  FROM `datateam-248616.dw_prod.dim_gator_quote_requests`
  WHERE UPPER(state) = 'CA'
    AND DATE(timestamp_gator_quote_created) >= DATE '2025-01-01'
    AND COALESCE(quotes_flag, '') != 'first_connect'
),
hip AS (
  SELECT gator_quote_request_id,
    LOGICAL_OR(TRUE) AS hippo_attempted,
    LOGICAL_OR(status = 'succeeded' AND premium > 0) AS hippo_quoted,
    ANY_VALUE(IF(status != 'succeeded', status_text, NULL)) AS hippo_decline_reason,
    AVG(IF(status = 'succeeded' AND premium > 0, premium * 12 / NULLIF(SAFE_CAST(REGEXP_EXTRACT(term, r'\d+') AS FLOAT64), 0), NULL)) AS hippo_annual_premium
  FROM `datateam-248616.dw_prod.dim_gator_carrier_quotes`
  WHERE LOWER(carrier_name) LIKE '%hippo%' AND LOWER(line_of_business) = 'home'
  GROUP BY 1
)
SELECT
  r.quarter, r.product,
  CASE
    WHEN NOT r.is_bound THEN 'unbound'
    WHEN LOWER(r.bound_carrier) LIKE '%hippo%' THEN 'hippo'
    WHEN LOWER(r.bound_carrier) LIKE '%fair plan%' THEN 'fair_plan'
    WHEN r.bound_carrier IN ('Aegis', 'Annex Coastal', 'Bamboo Insurance', 'Bigfoot', 'Delos', 'King', 'KW Specialty',
                             'LightSpeed', 'Orchid Insurance', 'Steadily', 'Obie Insurance', 'Qubie / SES',
                             'Specialty Pro Underwriters') THEN 'non_admitted_check_case'
    ELSE 'admitted'
  END AS bound_segment,
  COUNT(*) AS requests,
  COUNTIF(h.hippo_attempted) AS hippo_attempted,
  COUNTIF(h.hippo_quoted) AS hippo_quoted,
  AVG(h.hippo_annual_premium) AS avg_hippo_annual_premium,
  ARRAY_AGG(h.hippo_decline_reason IGNORE NULLS LIMIT 3) AS sample_decline_reasons
FROM req r
LEFT JOIN hip h USING (gator_quote_request_id)
GROUP BY 1, 2, 3
ORDER BY 1, 3, 2;

-- Discovery check (run first if counts look off): which carrier_name values look like Hippo, and through when?
-- SELECT carrier_name, MIN(DATE(created_at)) first_seen, MAX(DATE(created_at)) last_seen, COUNT(*) n
-- FROM `datateam-248616.dw_prod.dim_gator_carrier_quotes` WHERE LOWER(carrier_name) LIKE '%hippo%' GROUP BY 1;
