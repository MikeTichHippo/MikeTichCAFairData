-- Q1. CA 3P HOME book up for renewal Dec 2026 - Dec 2027 (the "renewing non-admitted" pool + FAIR Plan / DIC + admitted).
-- Source: latest ACS policy snapshot. One row per expiry month x segment x carrier x form_type x county.
-- Segment uses your non-admitted CASE (same as the weekly deck), with CA FAIR Plan and DIC split out.
WITH snap AS (
  SELECT s.*, COALESCE(dc.name, s.underwriting_carrier) AS carrier_name
  FROM `datateam-248616.dw_prod_extracts.ext_acs_policy_snapshots` s
  LEFT JOIN `datateam-248616.dw_prod_carrier_management_center.dim_carriers` dc
    ON CAST(s.cmc_carrier_id AS STRING) = CAST(dc.cmc_carrier_id AS STRING)
  WHERE s.date_snapshot = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    AND UPPER(s.state) = 'CA'
    AND s.line_of_business_group = 'HOME'
    AND s.status IN ('ACTIVE', 'PENDING_ACTIVE', 'BOUND')
    AND s.date_expires BETWEEN DATE '2026-12-01' AND DATE '2027-12-31'
),
p AS (
  SELECT *,
    CASE
      WHEN form_type IN ('DIC', 'HO-3', 'HO-5', 'HO-1') THEN 'Home'
      WHEN form_type = 'DP-3' THEN 'Landlord'
      WHEN form_type = 'HO-6' THEN 'Condo'
      WHEN form_type = 'HO-4' THEN 'Renters'
      WHEN form_type = 'HO-7' THEN 'Mobile Home'
      WHEN form_type = 'Flood' THEN 'Flood'
      ELSE 'Other'
    END AS product_category
  FROM snap
),
seg AS (
  SELECT *,
    CASE
      WHEN LOWER(carrier_name) LIKE '%fair plan%' THEN 'FAIR Plan'
      WHEN form_type = 'DIC' THEN 'DIC (FAIR wrap)'
      WHEN underwriting_carrier = 'Aegis' AND product_category = 'Home' THEN 'Non-Admitted'
      WHEN underwriting_carrier = 'Annex Coastal' AND product_category IN ('Home', 'Condo', 'Flood') THEN 'Non-Admitted'
      WHEN underwriting_carrier = 'Bamboo Insurance' AND product_category IN ('Condo', 'Landlord', 'Home', 'Renters') THEN 'Non-Admitted'
      WHEN underwriting_carrier = 'Bigfoot' AND product_category IN ('Condo', 'Home', 'Landlord') THEN 'Non-Admitted'
      WHEN underwriting_carrier = 'Delos' AND product_category IN ('Home', 'Landlord') THEN 'Non-Admitted'
      WHEN underwriting_carrier = 'King' AND product_category IN ('Condo', 'Home', 'Mobile Home') THEN 'Non-Admitted'
      WHEN underwriting_carrier = 'KW Specialty' AND product_category IN ('Condo', 'Home', 'Mobile Home') THEN 'Non-Admitted'
      WHEN underwriting_carrier = 'LightSpeed' AND product_category IN ('Condo', 'Landlord', 'Home') THEN 'Non-Admitted'
      WHEN underwriting_carrier = 'Obie Insurance' AND product_category = 'Landlord' THEN 'Non-Admitted'
      WHEN underwriting_carrier = 'Orchid Insurance' AND product_category IN ('Condo', 'Landlord', 'Home') THEN 'Non-Admitted'
      WHEN underwriting_carrier = 'Qubie / SES' AND product_category = 'Landlord' THEN 'Non-Admitted'
      WHEN underwriting_carrier = 'Specialty Pro Underwriters' AND product_category = 'Landlord' THEN 'Non-Admitted'
      WHEN underwriting_carrier = 'Steadily' AND product_category = 'Landlord' THEN 'Non-Admitted'
      WHEN underwriting_carrier IN ('Aon Edge', 'Neptune', 'Sterling Flood', 'Titan Flood') AND product_category = 'Flood' THEN 'Non-Admitted'
      ELSE 'Admitted'
    END AS segment
  FROM p
)
SELECT
  DATE_TRUNC(date_expires, MONTH) AS expiry_month,
  segment,
  carrier_name,
  underwriting_carrier,
  form_type,
  product_category,
  county,
  COUNT(DISTINCT acs_policy_id) AS policies,
  COUNT(DISTINCT acs_customer_id) AS customers,
  SUM(agent_reported_premium) AS premium,
  SUM(IF(is_new_business, 1, 0)) AS first_term_policies,
  -- customers with another active Hippo-agency HOME policy (e.g. FAIR + DIC pair)
  COUNT(DISTINCT IF(cust_home_policies > 1, acs_customer_id, NULL)) AS customers_multi_home_policy
FROM (
  SELECT *, COUNT(*) OVER (PARTITION BY acs_customer_id) AS cust_home_policies FROM seg
)
GROUP BY 1, 2, 3, 4, 5, 6, 7
ORDER BY 1, 2, policies DESC
