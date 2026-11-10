-- Q9. Market reach map: CA Gator home requests by ZIP3 x quarter -- how many carriers quote, FAIR/DIC reliance, avg winning premium.
-- Shows where the private market has gone dark (0-1 carriers quoting) = where a Hippo admitted option has least competition.
SELECT
  SUBSTR(r.zip_code, 1, 3) AS zip3,
  DATE_TRUNC(DATE(r.timestamp_gator_quote_created), QUARTER) AS quarter,
  COUNT(*) AS requests,
  COUNTIF(COALESCE(r.home_successful_quote_count, 0) = 0) AS zero_quotes,
  COUNTIF(r.home_successful_quote_count = 1) AS one_quote,
  COUNTIF(r.home_successful_quote_count >= 3) AS three_plus_quotes,
  COUNTIF(r.has_dic_quote) AS with_dic_quote,
  COUNTIF(r.hippo_quote_status IS NOT NULL AND r.hippo_quoted_premium > 0) AS hippo_quoted,
  COUNTIF(r.is_policy_bound AND r.flag_exclude_policy IS NULL) AS binds,
  COUNTIF(r.is_policy_bound AND r.flag_exclude_policy IS NULL AND r.bound_carrier = 'CA Fair Plan') AS fair_binds,
  AVG(IF(r.is_policy_bound AND r.flag_exclude_policy IS NULL, r.gator_policy_premium, NULL)) AS avg_bound_premium
FROM `datateam-248616.dw_prod.dim_gator_quote_requests` r
WHERE UPPER(r.state) = 'CA'
  AND DATE(r.timestamp_gator_quote_created) >= DATE '2025-01-01'
  AND COALESCE(r.quotes_flag, '') != 'first_connect'
GROUP BY 1, 2
