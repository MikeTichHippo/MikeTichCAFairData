-- Q6. What HHIP can write on the EXISTING CA admitted filing today: for CA Gator requests (2025+),
-- did Hippo return a quote, and why not, split by where the customer actually bound (FAIR / non-admitted / admitted / unbound).
-- Successful-HHIP-quote share among FAIR/non-admitted binds = Phase 1 eligibility. Decline reasons = what the expansion filing must change.
WITH req AS (
  SELECT
    gator_quote_request_id,
    DATE_TRUNC(DATE(timestamp_gator_quote_created), QUARTER) AS quarter,
    product,
    SUBSTR(zip_code, 1, 3) AS zip3,
    bound_carrier,
    is_policy_bound AND flag_exclude_policy IS NULL AS is_bound,
    COALESCE(hippo_quote_status, 'none') AS hippo_quote_status,
    COALESCE(hippo_quote_status_reason, 'none') AS hippo_quote_status_reason,
    hippo_quoted_premium
  FROM `datateam-248616.dw_prod.dim_gator_quote_requests`
  WHERE UPPER(state) = 'CA'
    AND DATE(timestamp_gator_quote_created) >= DATE '2025-01-01'
    AND COALESCE(quotes_flag, '') != 'first_connect'
)
SELECT
  quarter,
  product,
  CASE
    WHEN NOT is_bound THEN 'unbound'
    WHEN LOWER(bound_carrier) LIKE '%hippo%' THEN 'hippo'
    WHEN bound_carrier = 'CA Fair Plan' THEN 'fair_plan'
    -- Mike's non-admitted CASE (Home, CA) by Gator/CMC parent carrier name; refine with form/product if needed
    WHEN bound_carrier IN ('Aegis', 'Annex Coastal', 'Bamboo Insurance', 'Bigfoot', 'Delos', 'King', 'KW Specialty',
                           'LightSpeed', 'Orchid Insurance', 'Steadily', 'Obie Insurance', 'Qubie / SES',
                           'Specialty Pro Underwriters') THEN 'non_admitted_check_case'
    ELSE 'admitted'
  END AS bound_segment,
  bound_carrier,
  hippo_quote_status,
  hippo_quote_status_reason,
  COUNT(*) AS requests,
  COUNT(DISTINCT zip3) AS zip3s,
  AVG(hippo_quoted_premium) AS avg_hippo_quoted_premium
FROM req
GROUP BY 1, 2, 3, 4, 5, 6
ORDER BY quarter, requests DESC
