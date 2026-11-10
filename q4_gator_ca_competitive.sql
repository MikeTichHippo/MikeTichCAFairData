-- Q4. CA competitive baseline from Gator quotes (carriers we already quote), Jan 2025 onward.
-- One row per quarter x carrier x line_of_business: quote attempts, success rate, annualized premium,
-- how often the carrier was the cheapest successful quote on the request, binds, and top decline reason.
WITH req AS (
  SELECT gator_quote_request_id, DATE_TRUNC(DATE(timestamp_gator_quote_created), QUARTER) AS quarter,
    is_policy_bound, bound_carrier_id, flag_exclude_policy, zip_code
  FROM `datateam-248616.dw_prod.dim_gator_quote_requests`
  WHERE UPPER(state) = 'CA'
    AND DATE(timestamp_gator_quote_created) >= DATE '2025-01-01'
    AND COALESCE(quotes_flag, '') != 'first_connect'
),
cq AS (
  SELECT r.quarter, r.gator_quote_request_id, q.carrier_id, q.carrier_name, LOWER(q.line_of_business) AS line_of_business,
    q.status, q.status_text,
    IF(q.status = 'succeeded' AND q.premium > 0,
       q.premium * 12 / NULLIF(SAFE_CAST(REGEXP_EXTRACT(q.term, r'\d+') AS FLOAT64), 0), NULL) AS annual_premium,
    SAFE_CAST(REGEXP_REPLACE(q.cov_a, r'[^0-9.]', '') AS FLOAT64) AS cov_a,
    (r.is_policy_bound AND r.flag_exclude_policy IS NULL AND r.bound_carrier_id = q.carrier_id) AS bound_here
  FROM req r
  JOIN `datateam-248616.dw_prod.dim_gator_carrier_quotes` q ON q.gator_quote_request_id = r.gator_quote_request_id
),
ranked AS (
  SELECT *,
    IF(annual_premium IS NULL, NULL,
       RANK() OVER (PARTITION BY gator_quote_request_id, line_of_business ORDER BY annual_premium)) AS price_rank,
    COUNTIF(annual_premium IS NOT NULL) OVER (PARTITION BY gator_quote_request_id, line_of_business) AS n_success_on_request
  FROM cq
),
reasons AS (
  SELECT quarter, carrier_name, line_of_business, status_text, COUNT(*) AS n
  FROM cq WHERE status != 'succeeded'
  GROUP BY 1, 2, 3, 4
  QUALIFY ROW_NUMBER() OVER (PARTITION BY quarter, carrier_name, line_of_business ORDER BY n DESC) = 1
)
SELECT
  r.quarter, r.carrier_name, r.line_of_business,
  COUNT(DISTINCT r.gator_quote_request_id) AS requests_attempted,
  COUNT(DISTINCT IF(r.annual_premium IS NOT NULL, r.gator_quote_request_id, NULL)) AS requests_quoted,
  AVG(r.annual_premium) AS avg_annual_premium,
  APPROX_QUANTILES(r.annual_premium, 2)[OFFSET(1)] AS median_annual_premium,
  SUM(r.annual_premium) / NULLIF(SUM(IF(r.annual_premium IS NOT NULL, r.cov_a, NULL)), 0) * 1000 AS premium_per_1k_cov_a,
  AVG(IF(r.annual_premium IS NOT NULL, r.cov_a, NULL)) AS avg_cov_a,
  COUNTIF(r.price_rank = 1 AND r.n_success_on_request > 1) AS times_cheapest_of_2plus,
  COUNTIF(r.annual_premium IS NOT NULL AND r.n_success_on_request > 1) AS quotes_with_competition,
  COUNT(DISTINCT IF(r.bound_here, r.gator_quote_request_id, NULL)) AS binds,
  ANY_VALUE(rs.status_text) AS top_decline_reason,
  ANY_VALUE(rs.n) AS top_decline_reason_count
FROM ranked r
LEFT JOIN reasons rs USING (quarter, carrier_name, line_of_business)
GROUP BY 1, 2, 3
HAVING requests_attempted >= 20
ORDER BY 1, requests_attempted DESC
