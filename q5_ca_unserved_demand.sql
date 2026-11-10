-- Q5. CA unserved demand + why the Hippo (HHIP) quote declines today, by month and ZIP3 (Gator website/API requests, Jan 2025 onward).
-- requests with 0 successful home quotes = demand no carrier we have would write; hippo_quote_status_reason = HHIP UW declines.
SELECT
  DATE_TRUNC(DATE(timestamp_gator_quote_created), MONTH) AS month,
  SUBSTR(zip_code, 1, 3) AS zip3,
  COALESCE(hippo_quote_status, 'none') AS hippo_quote_status,
  COALESCE(hippo_quote_status_reason, 'none') AS hippo_quote_status_reason,
  COUNT(*) AS requests,
  COUNTIF(COALESCE(home_successful_quote_count, 0) = 0) AS requests_no_home_quote,
  COUNTIF(has_dic_quote) AS requests_with_dic_quote,
  COUNTIF(is_policy_bound AND flag_exclude_policy IS NULL) AS binds,
  AVG(hippo_quoted_premium) AS avg_hippo_quoted_premium
FROM `datateam-248616.dw_prod.dim_gator_quote_requests`
WHERE UPPER(state) = 'CA'
  AND DATE(timestamp_gator_quote_created) >= DATE '2025-01-01'
  AND COALESCE(quotes_flag, '') != 'first_connect'
GROUP BY 1, 2, 3, 4
ORDER BY 1, requests DESC
