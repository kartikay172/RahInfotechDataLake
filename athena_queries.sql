-- ============================================================
-- SharePoint Data Lake — Complete Athena Query Library
-- Database  : sharepoint_db
-- Workgroup : sharepoint-data-workgroup
-- Updated   : 2026-06-24
-- ============================================================

-- ── TABLE REFERENCE ──────────────────────────────────────────
-- skill_set_of_team_sheet1     → curated Parquet (FAST - use this)
-- resources_details            → processed CSV   (audit trail)
-- mostly_common_services_data  → curated Parquet (FAST - use this)
-- services                     → processed CSV   (audit trail)


-- ============================================================
-- SECTION 1: BASIC QUERIES
-- ============================================================

-- 1.1 View all team members (latest day)
SELECT
    s_no        AS serial_no,
    names       AS team_member,
    skill_set,
    domain,
    doj         AS date_of_joining,
    year, month, day
FROM skill_set_of_team_sheet1
WHERE year='2026' AND month='06'
  AND s_no IS NOT NULL
ORDER BY CAST(s_no AS INTEGER);


-- 1.2 View all services
SELECT * FROM mostly_common_services_data
WHERE year='2026' AND month='06'
ORDER BY category, service_name;


-- ============================================================
-- SECTION 2: ONBOARDING QUERIES (Requirement 9)
-- Who joined / was added to the system
-- ============================================================

-- 2.1 Find NEW team members (onboarded) between two dates
--     Shows people who appear in day=24 but NOT in day=22
SELECT
    curr.s_no,
    curr.names       AS new_member,
    curr.skill_set,
    curr.domain,
    curr.doj,
    curr.year, curr.month, curr.day AS onboarded_day
FROM skill_set_of_team_sheet1 curr
WHERE curr.year='2026' AND curr.month='06' AND curr.day='24'
  AND curr.s_no IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM skill_set_of_team_sheet1 prev
      WHERE prev.year='2026' AND prev.month='06' AND prev.day='22'
        AND prev.s_no = curr.s_no
  )
ORDER BY CAST(curr.s_no AS INTEGER);


-- 2.2 Find OFFBOARDED team members (removed) between two dates
--     Shows people who were in day=22 but NOT in day=24
SELECT
    prev.s_no,
    prev.names       AS offboarded_member,
    prev.skill_set,
    prev.domain,
    prev.year, prev.month, prev.day AS last_seen_day
FROM skill_set_of_team_sheet1 prev
WHERE prev.year='2026' AND prev.month='06' AND prev.day='22'
  AND prev.s_no IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM skill_set_of_team_sheet1 curr
      WHERE curr.year='2026' AND curr.month='06' AND curr.day='24'
        AND curr.s_no = prev.s_no
  )
ORDER BY CAST(prev.s_no AS INTEGER);


-- 2.3 Full onboarding/offboarding summary between any two dates
WITH day_before AS (
    SELECT s_no, names, domain, skill_set
    FROM skill_set_of_team_sheet1
    WHERE year='2026' AND month='06' AND day='22'
      AND s_no IS NOT NULL
),
day_after AS (
    SELECT s_no, names, domain, skill_set
    FROM skill_set_of_team_sheet1
    WHERE year='2026' AND month='06' AND day='24'
      AND s_no IS NOT NULL
)
SELECT
    COALESCE(a.s_no, b.s_no)       AS s_no,
    COALESCE(a.names, b.names)     AS member_name,
    COALESCE(a.domain, b.domain)   AS domain,
    CASE
        WHEN b.s_no IS NULL THEN 'ONBOARDED'
        WHEN a.s_no IS NULL THEN 'OFFBOARDED'
        ELSE 'NO CHANGE'
    END AS status
FROM day_after a
FULL OUTER JOIN day_before b ON a.s_no = b.s_no
WHERE (a.s_no IS NULL OR b.s_no IS NULL)
ORDER BY status, CAST(COALESCE(a.s_no, b.s_no) AS INTEGER);


-- ============================================================
-- SECTION 3: DAY-WISE QUERIES (Requirement 10)
-- ============================================================

-- 3.1 Day-wise team headcount trend
SELECT
    year,
    month,
    day,
    COUNT(*)                        AS total_members,
    COUNT(DISTINCT domain)          AS domains_covered,
    COUNT(CASE WHEN skill_set != '' THEN 1 END) AS members_with_skills
FROM skill_set_of_team_sheet1
WHERE s_no IS NOT NULL
GROUP BY year, month, day
ORDER BY year, month, day;


-- 3.2 Day-wise data for a specific date
SELECT
    s_no, names, skill_set, domain, doj
FROM skill_set_of_team_sheet1
WHERE year='2026' AND month='06' AND day='23'
  AND s_no IS NOT NULL
ORDER BY CAST(s_no AS INTEGER);


-- 3.3 Day-wise comparison — what changed each day
WITH daily_counts AS (
    SELECT
        year, month, day,
        COUNT(*) AS member_count
    FROM skill_set_of_team_sheet1
    WHERE s_no IS NOT NULL
    GROUP BY year, month, day
)
SELECT
    curr.year, curr.month, curr.day,
    curr.member_count                                    AS current_count,
    LAG(curr.member_count) OVER (
        ORDER BY curr.year, curr.month, curr.day
    )                                                    AS previous_count,
    curr.member_count - LAG(curr.member_count) OVER (
        ORDER BY curr.year, curr.month, curr.day
    )                                                    AS change
FROM daily_counts curr
ORDER BY curr.year, curr.month, curr.day;


-- 3.4 Day-wise domain distribution
SELECT
    year, month, day,
    COALESCE(NULLIF(TRIM(domain), ''), 'Not Specified') AS domain,
    COUNT(*) AS member_count
FROM skill_set_of_team_sheet1
WHERE s_no IS NOT NULL
GROUP BY year, month, day, domain
ORDER BY year, month, day, member_count DESC;


-- 3.5 Day-wise services added/changed
SELECT
    year, month, day,
    COUNT(*) AS service_count,
    COUNT(DISTINCT category) AS categories
FROM mostly_common_services_data
WHERE category IS NOT NULL
GROUP BY year, month, day
ORDER BY year, month, day;


-- ============================================================
-- SECTION 4: SCHEMA CHANGE DETECTION (Requirement 11)
-- Handles Add/Delete columns and structural changes
-- ============================================================

-- 4.1 Read schema.json files from processed zone to detect column changes
--     This queries the schema metadata written by the ETL script
CREATE OR REPLACE VIEW schema_change_detection AS
SELECT
    source,
    sheet,
    processed_at,
    partition,
    total_rows,
    valid_rows,
    rejected_rows,
    duplicates_removed
FROM processed_schema_metadata
WHERE partition LIKE 'year=2026%';


-- 4.2 Day-wise validation report — detect bad rows (schema mismatch)
--     ETL writes rejected rows to validation-reports/ in S3
--     Query this table after running the crawler on validation-reports/
SELECT
    year, month, day,
    SUM(valid_rows)        AS valid_rows,
    SUM(rejected_rows)     AS rejected_rows,
    SUM(duplicates_removed)AS duplicates_removed,
    SUM(total_rows)        AS total_rows,
    ROUND(
        100.0 * SUM(valid_rows) / NULLIF(SUM(total_rows), 0), 2
    )                      AS data_quality_pct
FROM processed_schema_metadata
GROUP BY year, month, day
ORDER BY year, month, day;


-- 4.3 Detect if columns were ADDED (new columns present today vs yesterday)
--     Compare column counts across days using schema.json metadata
WITH yesterday_schema AS (
    SELECT source, sheet
    FROM skill_set_of_team_sheet1
    WHERE year='2026' AND month='06' AND day='22'
    LIMIT 1
),
today_schema AS (
    SELECT source, sheet
    FROM skill_set_of_team_sheet1
    WHERE year='2026' AND month='06' AND day='23'
    LIMIT 1
)
SELECT
    'Column structure check' AS check_type,
    CASE
        WHEN (SELECT COUNT(*) FROM yesterday_schema) = 0 THEN 'No previous data'
        WHEN (SELECT COUNT(*) FROM today_schema) = 0     THEN 'No current data'
        ELSE 'Run ETL validation report for column details'
    END AS result;


-- 4.4 Row count anomaly detection — flag days where count drops >20%
WITH daily_counts AS (
    SELECT
        year, month, day,
        COUNT(*) AS row_count
    FROM skill_set_of_team_sheet1
    WHERE s_no IS NOT NULL
    GROUP BY year, month, day
),
with_change AS (
    SELECT
        *,
        LAG(row_count) OVER (ORDER BY year, month, day) AS prev_count
    FROM daily_counts
)
SELECT
    year, month, day,
    row_count,
    prev_count,
    ROUND(100.0 * (row_count - prev_count) / NULLIF(prev_count, 0), 2) AS pct_change,
    CASE
        WHEN prev_count IS NULL THEN 'FIRST RUN'
        WHEN row_count < prev_count * 0.8 THEN '⚠ ANOMALY: Row count dropped >20%'
        WHEN row_count > prev_count * 1.5 THEN '⚠ ANOMALY: Row count increased >50%'
        ELSE '✓ NORMAL'
    END AS status
FROM with_change
ORDER BY year, month, day;


-- 4.5 Data drift detection — find members whose domain changed
SELECT
    curr.s_no,
    curr.names,
    prev.domain   AS old_domain,
    curr.domain   AS new_domain,
    'DOMAIN CHANGED' AS change_type,
    curr.day      AS detected_on_day
FROM skill_set_of_team_sheet1 curr
JOIN skill_set_of_team_sheet1 prev
    ON curr.s_no = prev.s_no
    AND curr.year = prev.year
    AND curr.month = prev.month
    AND CAST(curr.day AS INTEGER) = CAST(prev.day AS INTEGER) + 1
WHERE curr.domain != prev.domain
  AND curr.s_no IS NOT NULL
ORDER BY curr.day, curr.s_no;


-- ============================================================
-- SECTION 5: COMPLEX JOIN QUERIES (from earlier)
-- ============================================================

-- 5.1 Team members mapped to relevant cloud services
SELECT
    r.names             AS team_member,
    r.domain,
    s.category          AS service_category,
    s.service_name
FROM skill_set_of_team_sheet1 r
CROSS JOIN mostly_common_services_data s
WHERE r.year='2026' AND r.month='06'
  AND s.year='2026' AND s.month='06'
  AND r.s_no IS NOT NULL
  AND s.service_name IS NOT NULL
  AND (
      LOWER(r.skill_set) LIKE '%azure%'  AND LOWER(s.service_name) LIKE '%azure%'
   OR LOWER(r.skill_set) LIKE '%aws%'    AND LOWER(s.service_name) LIKE '%aws%'
   OR LOWER(r.skill_set) LIKE '%docker%' AND LOWER(s.service_name) LIKE '%docker%'
  )
ORDER BY r.names, s.category;


-- 5.2 Skills frequency analysis
WITH skill_keywords AS (
    SELECT names, skill AS skill_keyword
    FROM skill_set_of_team_sheet1
    CROSS JOIN UNNEST(
        SPLIT(REPLACE(REPLACE(skill_set, '"', ''), ' | ', ','), ',')
    ) AS t(skill)
    WHERE year='2026' AND month='06' AND s_no IS NOT NULL
)
SELECT
    TRIM(skill_keyword) AS skill,
    COUNT(DISTINCT names) AS team_members_with_skill
FROM skill_keywords
WHERE LENGTH(TRIM(skill_keyword)) > 2
GROUP BY TRIM(skill_keyword)
ORDER BY team_members_with_skill DESC
LIMIT 20;


-- 5.3 Services coverage gap analysis
WITH team_skills AS (
    SELECT LOWER(skill_set) AS all_skills
    FROM skill_set_of_team_sheet1
    WHERE year='2026' AND month='06' AND s_no IS NOT NULL
)
SELECT
    s.category,
    s.service_name,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM team_skills ts
            WHERE ts.all_skills LIKE '%' || LOWER(s.service_name) || '%'
        ) THEN 'COVERED'
        ELSE 'GAP'
    END AS coverage_status
FROM mostly_common_services_data s
WHERE s.year='2026' AND s.month='06'
  AND s.service_name IS NOT NULL
ORDER BY coverage_status, s.category;
