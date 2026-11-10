-- Q7. Who is in our CA book today: profile of active CA HOME ACS policies by segment (FAIR / DIC / Non-Admitted / Admitted).
-- County, premium band, tenure, form, and whether the customer also holds auto/other policies with us.
WITH snap AS (
  SELECT s.*, COALESCE(dc.name, s.underwriting_carrier) AS carrier_name
  FROM `datateam-248616.dw_prod_extracts.ext_acs_policy_snapshots` s
  LEFT JOIN `datateam-248616.dw_prod_carrier_management_center.dim_carriers` dc
    ON CAST(s.cmc_carrier_id AS STRING) = CAST(dc.cmc_carrier_id AS STRING)
  WHERE s.date_snapshot = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    AND UPPER(s.state) = 'CA'
    AND s.line_of_business_group = 'HOME'
    AND s.status IN ('ACTIVE', 'PENDING_ACTIVE', 'BOUND')
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
),
cust AS (
  SELECT acs_customer_id,
    COUNTIF(line_of_business_group = 'AUTO') AS auto_pols,
    COUNT(*) AS all_pols
  FROM `datateam-248616.dw_prod_extracts.ext_acs_policy_snapshots`
  WHERE date_snapshot = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    AND status IN ('ACTIVE', 'PENDING_ACTIVE', 'BOUND')
  GROUP BY 1
)
SELECT
  seg.segment,
  seg.carrier_name,
  seg.form_type,
  seg.county,
  SUBSTR(seg.zip_code, 1, 3) AS zip3,
  CASE WHEN seg.carrier_reported_full_term_premium < 1000 THEN 'a <1K'
       WHEN seg.carrier_reported_full_term_premium < 2000 THEN 'b 1-2K'
       WHEN seg.carrier_reported_full_term_premium < 3000 THEN 'c 2-3K'
       WHEN seg.carrier_reported_full_term_premium < 5000 THEN 'd 3-5K'
       WHEN seg.carrier_reported_full_term_premium >= 5000 THEN 'e 5K+' ELSE 'unknown' END AS premium_band,
  CASE WHEN seg.is_new_business THEN 'first term' ELSE 'renewal term' END AS term_type,
  DATE_DIFF(CURRENT_DATE(), seg.date_bound, YEAR) AS years_since_bound,
  c.auto_pols > 0 AS has_auto_with_us,
  COUNT(*) AS policies,
  COUNT(DISTINCT seg.acs_customer_id) AS customers,
  SUM(seg.carrier_reported_full_term_premium) AS premium
FROM seg
LEFT JOIN cust c USING (acs_customer_id)
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
