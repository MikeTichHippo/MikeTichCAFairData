-- F1. CA FAIR Plan customers in the Hippo agency: one row per FAIR policy term (bound 2023+), with location,
-- home attributes, wildfire signals, DIC wrap / bundle, what they had before FAIR, what they did after, and quote history.
-- No names/phones/emails/street exported: location stops at ZIP5 / city / county.
-- Joins (all LEFT, so every FAIR term is kept):
--   ACS snapshot -> ext_third_party_policies_attribution (gator_sf_lead_id = salesforce_lead_id) -> AOS funnel (property service attrs)
--   ACS snapshot -> dim_quotes (HHIP quote at same street+zip: fireline score, year built, roof, coverage A, miles to fire dept)
--   ACS snapshot -> dim_gator_quote_requests (sf_lead_id) -> carrier quotes (how many carriers quoted, cheapest non-FAIR quote)
WITH snap AS (
  SELECT s.*, COALESCE(dc.name, s.underwriting_carrier) AS carrier_name,
    UPPER(REGEXP_REPLACE(TRIM(s.street), r'[^A-Za-z0-9]', '')) AS street_key,
    SUBSTR(s.zip_code, 1, 5) AS zip5
  FROM `datateam-248616.dw_prod_extracts.ext_acs_policy_snapshots` s
  LEFT JOIN `datateam-248616.dw_prod_carrier_management_center.dim_carriers` dc
    ON CAST(s.cmc_carrier_id AS STRING) = CAST(dc.cmc_carrier_id AS STRING)
  WHERE s.date_snapshot = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    AND UPPER(s.state) = 'CA'
),
fair AS (
  SELECT * FROM snap
  WHERE LOWER(carrier_name) LIKE '%fair plan%' AND date_bound >= DATE '2023-01-01'
),
-- other policies held by the same customer at the FAIR term's effective date
other_pols AS (
  SELECT f.acs_policy_id,
    LOGICAL_OR(o.form_type = 'DIC') AS has_dic,
    ANY_VALUE(IF(o.form_type = 'DIC', o.carrier_name, NULL)) AS dic_carrier,
    SUM(IF(o.form_type = 'DIC', o.carrier_reported_full_term_premium, 0)) AS dic_premium,
    LOGICAL_OR(o.line_of_business_group = 'AUTO') AS has_auto,
    LOGICAL_OR(o.form_type = 'Flood') AS has_flood,
    LOGICAL_OR(LOWER(o.line_of_business) LIKE '%earthquake%') AS has_earthquake,
    LOGICAL_OR(LOWER(o.line_of_business) LIKE '%umbrella%') AS has_umbrella,
    COUNT(DISTINCT o.acs_policy_id) AS other_policy_count
  FROM fair f
  JOIN snap o
    ON o.acs_customer_id = f.acs_customer_id AND o.acs_policy_id != f.acs_policy_id
   AND o.date_effective <= f.date_expires AND COALESCE(o.date_cancellation, o.date_expires) >= f.date_effective
  GROUP BY 1
),
-- the customer's HOME policy just before FAIR (who pushed them out) and just after (where they went)
prior_home AS (
  SELECT f.acs_policy_id, o.carrier_name AS prior_home_carrier, o.form_type AS prior_form, o.status AS prior_status,
    o.acs_cancellation_reason AS prior_cancel_reason, o.carrier_reported_full_term_premium AS prior_premium
  FROM fair f
  JOIN snap o ON o.acs_customer_id = f.acs_customer_id AND o.acs_policy_id != f.acs_policy_id
   AND o.line_of_business_group = 'HOME' AND o.form_type != 'DIC' AND LOWER(o.carrier_name) NOT LIKE '%fair plan%'
   AND o.date_effective < f.date_effective
  QUALIFY ROW_NUMBER() OVER (PARTITION BY f.acs_policy_id ORDER BY o.date_effective DESC) = 1
),
next_home AS (
  SELECT f.acs_policy_id, o.carrier_name AS next_home_carrier, o.form_type AS next_form, o.date_effective AS next_effective,
    o.carrier_reported_full_term_premium AS next_premium
  FROM fair f
  JOIN snap o ON o.acs_customer_id = f.acs_customer_id AND o.acs_policy_id != f.acs_policy_id
   AND o.line_of_business_group = 'HOME' AND o.form_type != 'DIC' AND LOWER(o.carrier_name) NOT LIKE '%fair plan%'
   AND o.date_effective > f.date_effective
  QUALIFY ROW_NUMBER() OVER (PARTITION BY f.acs_policy_id ORDER BY o.date_effective) = 1
),
attr AS (
  SELECT gator_sf_lead_id, ANY_VALUE(attributed_first_touch_aos_lead_id) AS aos_lead_id,
    ANY_VALUE(attributed_first_touch_aos_lead_utm_source) AS first_touch_source, MIN(earliest_customer_bind_date) AS earliest_customer_bind_date
  FROM `datateam-248616.dw_prod_extracts.ext_third_party_policies_attribution`
  WHERE gator_sf_lead_id IS NOT NULL
  GROUP BY 1
),
aos AS (
  SELECT aos_lead_id, property_type, occupancy_status, building_year_built, square_footage, roof_year_built, roof_material,
    roof_style, rce_verisk_medium, first_insured_date_of_birth, second_insured_date_of_birth IS NOT NULL AS has_second_insured,
    preferred_coverage_tier
  FROM `datateam-248616.dw_prod_extracts.ext_agency_online_sales_funnel`
  WHERE UPPER(state) = 'CA'
),
hq AS (  -- HHIP quote at the same address (property data + wildfire signals)
  SELECT UPPER(REGEXP_REPLACE(TRIM(street), r'[^A-Za-z0-9]', '')) AS street_key, SUBSTR(zip_code, 1, 5) AS zip5,
    fireline_score, year_built, square_footage, year_roof_built, roof_type, roof_shape, construction_type,
    property_data_miles_from_fire_department, property_data_number_of_stories, coverage_a, quote_premium_total, date_lead_created
  FROM `datateam-248616.dw_prod.dim_quotes`
  WHERE UPPER(state) = 'CA'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY street_key, zip5 ORDER BY date_lead_created DESC) = 1
),
gq AS (  -- latest Gator home request for the lead + carrier quote stats
  SELECT r.sf_lead_id,
    ANY_VALUE(r.hippo_quote_status) AS hippo_quote_status,
    ANY_VALUE(r.hippo_quote_status_reason) AS hippo_quote_status_reason,
    MAX(r.hippo_quoted_premium) AS hippo_quoted_premium,
    MAX(r.home_successful_quote_count) AS home_quotes_returned,
    MAX(r.home_failed_quote_count) AS home_quotes_failed,
    LOGICAL_OR(r.has_dic_quote) AS had_dic_quote
  FROM `datateam-248616.dw_prod.dim_gator_quote_requests` r
  WHERE UPPER(r.state) = 'CA' AND r.sf_lead_id IS NOT NULL AND COALESCE(r.quotes_flag, '') != 'first_connect'
  GROUP BY 1
),
cq AS (
  SELECT r.sf_lead_id,
    MIN(IF(LOWER(q.carrier_name) NOT LIKE '%fair plan%', q.premium, NULL)) AS cheapest_non_fair_quote,
    STRING_AGG(DISTINCT IF(LOWER(q.carrier_name) NOT LIKE '%fair plan%', q.carrier_name, NULL), ', ') AS non_fair_carriers_quoted,
    COUNT(DISTINCT IF(LOWER(q.carrier_name) NOT LIKE '%fair plan%', q.carrier_name, NULL)) AS non_fair_carriers_quoted_n
  FROM `datateam-248616.dw_prod.dim_gator_quote_requests` r
  JOIN `datateam-248616.dw_prod.dim_gator_carrier_quotes` q ON q.gator_quote_request_id = r.gator_quote_request_id
  WHERE UPPER(r.state) = 'CA' AND r.sf_lead_id IS NOT NULL AND q.premium > 0
  GROUP BY 1
)
SELECT
  f.acs_policy_id, f.acs_customer_id,
  f.status, f.status IN ('ACTIVE', 'PENDING_ACTIVE', 'BOUND') AS is_active,
  f.date_bound, f.date_effective, f.date_expires, f.date_cancellation, f.acs_cancellation_reason,
  f.is_new_business, f.form_type, f.term,
  f.carrier_reported_full_term_premium AS fair_premium, f.agent_reported_premium,
  f.county, f.city, f.zip5, SUBSTR(f.zip5, 1, 3) AS zip3,
  op.has_dic, op.dic_carrier, op.dic_premium, op.has_auto, op.has_flood, op.has_earthquake, op.has_umbrella, op.other_policy_count,
  ph.prior_home_carrier, ph.prior_form, ph.prior_status, ph.prior_cancel_reason, ph.prior_premium,
  nh.next_home_carrier, nh.next_form, nh.next_effective, nh.next_premium,
  a.first_touch_source, a.earliest_customer_bind_date,
  aos.property_type, aos.occupancy_status, aos.building_year_built, aos.square_footage, aos.roof_year_built, aos.roof_material,
  aos.roof_style, aos.rce_verisk_medium, DATE_DIFF(f.date_effective, aos.first_insured_date_of_birth, YEAR) AS insured_age,
  aos.has_second_insured, aos.preferred_coverage_tier,
  hq.fireline_score, hq.year_built AS hhip_year_built, hq.square_footage AS hhip_sqft, hq.year_roof_built AS hhip_roof_year,
  hq.roof_type AS hhip_roof_type, hq.construction_type, hq.property_data_miles_from_fire_department AS miles_to_fire_dept,
  hq.property_data_number_of_stories AS stories, hq.coverage_a AS hhip_coverage_a, hq.quote_premium_total AS hhip_quote_premium,
  gq.hippo_quote_status, gq.hippo_quote_status_reason, gq.hippo_quoted_premium, gq.home_quotes_returned, gq.home_quotes_failed, gq.had_dic_quote,
  cq.cheapest_non_fair_quote, cq.non_fair_carriers_quoted_n, cq.non_fair_carriers_quoted
FROM fair f
LEFT JOIN other_pols op USING (acs_policy_id)
LEFT JOIN prior_home ph USING (acs_policy_id)
LEFT JOIN next_home nh USING (acs_policy_id)
LEFT JOIN attr a ON a.gator_sf_lead_id = f.salesforce_lead_id
LEFT JOIN aos ON aos.aos_lead_id = a.aos_lead_id
LEFT JOIN hq ON hq.street_key = f.street_key AND hq.zip5 = f.zip5
LEFT JOIN gq ON gq.sf_lead_id = f.salesforce_lead_id
LEFT JOIN cq ON cq.sf_lead_id = f.salesforce_lead_id
ORDER BY f.date_bound
