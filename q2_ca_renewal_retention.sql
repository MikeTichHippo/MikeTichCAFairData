-- Q2. How CA 3P HOME policies behave at renewal, by segment / carrier (terms expiring Jan 2025 - Sep 2026, matured).
-- Outcomes per expiring term: renewed (next term with prior_ams_policy_id = this ams_policy_id),
-- re-shopped to another carrier inside the Hippo agency (customer has a new HOME policy effective within +/-45 days of expiry),
-- cancelled before expiry, or lost. Also renewal premium change for renewed terms (price pressure signal).
WITH pol AS (
  SELECT p.*, COALESCE(dc.name, p.underwriting_carrier) AS carrier_name
  FROM `datateam-248616.dw_prod_agency_customer_service.dim_agency_customer_policies` p
  LEFT JOIN `datateam-248616.dw_prod_carrier_management_center.dim_carriers` dc
    ON CAST(p.cmc_carrier_id AS STRING) = CAST(dc.cmc_carrier_id AS STRING)
  WHERE UPPER(p.state) = 'CA' AND p.line_of_business_group = 'HOME'
),
seg AS (
  SELECT *,
    CASE
      WHEN LOWER(carrier_name) LIKE '%fair plan%' THEN 'FAIR Plan'
      WHEN form_type = 'DIC' THEN 'DIC (FAIR wrap)'
      WHEN underwriting_carrier IN ('Aegis', 'Annex Coastal', 'Bamboo Insurance', 'Bigfoot', 'Delos', 'King', 'KW Specialty', 'LightSpeed', 'Orchid Insurance')
           AND form_type IN ('HO-3', 'HO-5', 'HO-1', 'HO-6', 'DP-3', 'HO-4', 'HO-7') THEN 'Non-Admitted'
      WHEN underwriting_carrier IN ('Obie Insurance', 'Qubie / SES', 'Specialty Pro Underwriters', 'Steadily') AND form_type = 'DP-3' THEN 'Non-Admitted'
      ELSE 'Admitted'
    END AS segment
  FROM pol
),
expiring AS (
  SELECT * FROM seg
  WHERE date_expires BETWEEN DATE '2025-01-01' AND DATE '2026-09-30'
),
outcome AS (
  SELECT
    e.acs_policy_id, e.segment, e.carrier_name, DATE_TRUNC(e.date_expires, QUARTER) AS expiry_quarter,
    e.agent_reported_premium AS expiring_premium,
    (e.status = 'cancelled' AND COALESCE(e.cancellation_effective_date, e.date_expires) < e.date_expires) AS cancelled_midterm,
    r.acs_policy_id IS NOT NULL AS renewed_same_carrier,
    r.agent_reported_premium AS renewal_premium,
    rs.acs_policy_id IS NOT NULL AS reshopped_in_agency
  FROM expiring e
  LEFT JOIN seg r ON r.prior_ams_policy_id = e.ams_policy_id AND r.acs_policy_id != e.acs_policy_id
  LEFT JOIN seg rs
    ON rs.acs_customer_id = e.acs_customer_id AND rs.acs_policy_id != e.acs_policy_id
   AND COALESCE(rs.prior_ams_policy_id, '') != COALESCE(e.ams_policy_id, '#')
   AND rs.date_effective BETWEEN DATE_SUB(e.date_expires, INTERVAL 45 DAY) AND DATE_ADD(e.date_expires, INTERVAL 45 DAY)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY e.acs_policy_id ORDER BY r.date_effective, rs.date_effective) = 1
)
SELECT
  expiry_quarter, segment, carrier_name,
  COUNT(*) AS expiring_terms,
  SUM(expiring_premium) AS expiring_premium,
  COUNTIF(cancelled_midterm) AS cancelled_before_expiry,
  COUNTIF(NOT cancelled_midterm AND renewed_same_carrier) AS renewed_same_carrier,
  COUNTIF(NOT cancelled_midterm AND NOT renewed_same_carrier AND reshopped_in_agency) AS reshopped_in_agency,
  COUNTIF(NOT cancelled_midterm AND NOT renewed_same_carrier AND NOT reshopped_in_agency) AS lost_at_expiry,
  SUM(IF(renewed_same_carrier, renewal_premium, NULL)) AS renewal_premium_renewed,
  SUM(IF(renewed_same_carrier, expiring_premium, NULL)) AS expiring_premium_renewed
FROM outcome
GROUP BY 1, 2, 3
ORDER BY 1, 2, expiring_terms DESC
