-- Q8. What CA homes/shoppers look like (website AOS leads, 2025+), by outcome:
-- bound FAIR / bound non-admitted / bound admitted / Hippo quoted / no home quote at all.
-- Property + shopper attributes come from property service on ext_agency_online_sales_funnel.
WITH l AS (
  SELECT f.*, cq.carrier_name AS bound_carrier
  FROM `datateam-248616.dw_prod_extracts.ext_agency_online_sales_funnel` f
  LEFT JOIN `datateam-248616.dw_prod.dim_gator_carrier_quotes` cq
    ON f.bound_gator_carrier_quote_id = CAST(cq.gator_carrier_quote_id AS STRING)
  WHERE UPPER(f.state) = 'CA' AND f.date_lead_created >= DATE '2025-01-01'
)
SELECT
  CASE
    WHEN lead_with_gator_home_policies_bound = 1 AND bound_carrier = 'CA Fair Plan' THEN 'bound FAIR'
    WHEN lead_with_gator_home_policies_bound = 1 AND bound_carrier IN ('Aegis','Annex Coastal','Bamboo Insurance','Bigfoot','Delos',
         'King','KW Specialty','LightSpeed','Orchid Insurance','Steadily') THEN 'bound non-admitted (check CASE)'
    WHEN lead_with_gator_home_policies_bound = 1 THEN 'bound admitted'
    WHEN hippo_offer_shown OR hcr_hippo_quote_seen = 1 THEN 'Hippo quote seen, not bound'
    WHEN COALESCE(home_successful_quote_count, 0) = 0 THEN 'no home quote'
    ELSE 'quoted 3P, not bound'
  END AS outcome,
  county,
  property_type,
  occupancy_status,
  CASE WHEN building_year_built < 1950 THEN 'a pre-1950' WHEN building_year_built < 1980 THEN 'b 1950-79'
       WHEN building_year_built < 2000 THEN 'c 1980-99' WHEN building_year_built < 2010 THEN 'd 2000-09'
       WHEN building_year_built >= 2010 THEN 'e 2010+' ELSE 'unknown' END AS year_built_band,
  CASE WHEN square_footage < 1200 THEN 'a <1200' WHEN square_footage < 1800 THEN 'b 1200-1799'
       WHEN square_footage < 2500 THEN 'c 1800-2499' WHEN square_footage < 3500 THEN 'd 2500-3499'
       WHEN square_footage >= 3500 THEN 'e 3500+' ELSE 'unknown' END AS sqft_band,
  CASE WHEN roof_year_built IS NULL THEN 'unknown' WHEN EXTRACT(YEAR FROM CURRENT_DATE()) - roof_year_built <= 10 THEN 'a <=10y'
       WHEN EXTRACT(YEAR FROM CURRENT_DATE()) - roof_year_built <= 20 THEN 'b 11-20y' ELSE 'c 20y+' END AS roof_age_band,
  roof_material,
  CASE WHEN SAFE_CAST(rce_verisk_medium AS FLOAT64) < 300000 THEN 'a <300K' WHEN SAFE_CAST(rce_verisk_medium AS FLOAT64) < 500000 THEN 'b 300-500K'
       WHEN SAFE_CAST(rce_verisk_medium AS FLOAT64) < 800000 THEN 'c 500-800K' WHEN SAFE_CAST(rce_verisk_medium AS FLOAT64) < 1200000 THEN 'd 800K-1.2M'
       WHEN SAFE_CAST(rce_verisk_medium AS FLOAT64) >= 1200000 THEN 'e 1.2M+' ELSE 'unknown' END AS rebuild_cost_band,
  CASE WHEN first_insured_date_of_birth IS NULL THEN 'unknown'
       WHEN DATE_DIFF(CURRENT_DATE(), first_insured_date_of_birth, YEAR) < 35 THEN 'a <35'
       WHEN DATE_DIFF(CURRENT_DATE(), first_insured_date_of_birth, YEAR) < 50 THEN 'b 35-49'
       WHEN DATE_DIFF(CURRENT_DATE(), first_insured_date_of_birth, YEAR) < 65 THEN 'c 50-64' ELSE 'd 65+' END AS age_band,
  COUNT(*) AS leads,
  COUNTIF(lead_with_gator_cross_sell_policies_bound = 1) AS leads_with_cross_sell,
  AVG(NULLIF(gator_home_policy_premium, 0)) AS avg_bound_home_premium
FROM l
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
