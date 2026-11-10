-- F2. Fills the two gaps in F1: (1) location -- ACS snapshot address is empty for FAIR terms, so take ZIP/city/county from
-- the AOS lead (property service) or the Gator request; (2) Hippo quote + wildfire data -- join dim_quotes on property_id.
-- One row per FAIR acs_policy_id from F1; join back to the F1 CSV on acs_policy_id.
WITH fair AS (
  SELECT s.acs_policy_id, s.salesforce_lead_id, s.acs_customer_id
  FROM `datateam-248616.dw_prod_extracts.ext_acs_policy_snapshots` s
  LEFT JOIN `datateam-248616.dw_prod_carrier_management_center.dim_carriers` dc
    ON CAST(s.cmc_carrier_id AS STRING) = CAST(dc.cmc_carrier_id AS STRING)
  WHERE s.date_snapshot = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    AND UPPER(s.state) = 'CA'
    AND LOWER(COALESCE(dc.name, s.underwriting_carrier)) LIKE '%fair plan%'
    AND s.date_bound >= DATE '2023-01-01'
),
attr AS (
  SELECT gator_sf_lead_id, ANY_VALUE(attributed_first_touch_aos_lead_id) AS aos_lead_id,
    ANY_VALUE(customer_service_id) AS customer_service_id
  FROM `datateam-248616.dw_prod_extracts.ext_third_party_policies_attribution`
  WHERE gator_sf_lead_id IS NOT NULL
  GROUP BY 1
),
aos AS (
  SELECT aos_lead_id, property_id, county, city, SUBSTR(zip_code, 1, 5) AS zip5
  FROM `datateam-248616.dw_prod_extracts.ext_agency_online_sales_funnel`
),
gz AS (  -- Gator request address (works for agent-only customers with no web lead)
  SELECT sf_lead_id, ANY_VALUE(city) AS g_city, ANY_VALUE(SUBSTR(zip_code, 1, 5)) AS g_zip5
  FROM `datateam-248616.dw_prod.dim_gator_quote_requests`
  WHERE UPPER(state) = 'CA' AND sf_lead_id IS NOT NULL AND zip_code IS NOT NULL
  GROUP BY 1
),
hq AS (  -- latest HHIP quote on the same property
  SELECT property_id, county AS q_county, SUBSTR(zip_code, 1, 5) AS q_zip5, fireline_score, year_built, square_footage,
    year_roof_built, roof_type, construction_type, property_data_miles_from_fire_department, property_data_number_of_stories,
    coverage_a, quote_premium_total, date_lead_created, date_bound IS NOT NULL AS hhip_bound
  FROM `datateam-248616.dw_prod.dim_quotes`
  WHERE UPPER(state) = 'CA' AND property_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY property_id ORDER BY date_lead_created DESC) = 1
)
SELECT
  f.acs_policy_id,
  COALESCE(aos.zip5, gz.g_zip5, hq.q_zip5) AS zip5,
  COALESCE(aos.city, gz.g_city) AS city,
  COALESCE(aos.county, hq.q_county) AS county,
  CASE WHEN aos.zip5 IS NOT NULL THEN 'aos' WHEN gz.g_zip5 IS NOT NULL THEN 'gator' WHEN hq.q_zip5 IS NOT NULL THEN 'hhip_quote' END AS location_source,
  hq.fireline_score, hq.year_built AS hhip_year_built, hq.square_footage AS hhip_sqft, hq.year_roof_built AS hhip_roof_year,
  hq.roof_type AS hhip_roof_type, hq.construction_type, hq.property_data_miles_from_fire_department AS miles_to_fire_dept,
  hq.property_data_number_of_stories AS stories, hq.coverage_a AS hhip_coverage_a, hq.quote_premium_total AS hhip_quote_premium,
  hq.date_lead_created AS hhip_quote_date, hq.hhip_bound
FROM fair f
LEFT JOIN attr a ON a.gator_sf_lead_id = f.salesforce_lead_id
LEFT JOIN aos ON aos.aos_lead_id = a.aos_lead_id
LEFT JOIN gz ON gz.sf_lead_id = f.salesforce_lead_id
LEFT JOIN hq ON hq.property_id = aos.property_id
