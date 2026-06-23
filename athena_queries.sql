-- ============================================================
-- SharePoint Data Lake — Athena Query Library
-- Database: sharepoint_db
-- Workgroup: sharepoint-data-workgroup
-- ============================================================

-- ── TABLE REFERENCE ──────────────────────────────────────────
-- resources_details        → processed zone (people + skills)
-- skill_set_of_team_sheet1 → curated zone  (same, deduplicated)
-- services                 → processed zone (AWS/Azure services)
-- mostly_common_services_data → curated zone (services)


-- ============================================================
-- 1. BASIC — View all team members (current partition)
-- ============================================================
SELECT
    "s.no"     AS serial_no,
    names      AS team_member,
    skill_set,
    domain,
    doj        AS date_of_joining,
    year,
    month,
    day
FROM resources_details
WHERE year  = '2026'
  AND month = '06'
  AND "s.no" IS NOT NULL
ORDER BY CAST("s.no" AS INTEGER);


-- ============================================================
-- 2. BASIC — View all AWS/Azure services
-- ============================================================
SELECT *
FROM services
WHERE year  = '2026'
  AND month = '06'
  AND col_1 IS NOT NULL
ORDER BY col_1;


-- ============================================================
-- 3. COMPLEX JOIN — Team members with their cloud domain
--    mapping to relevant services
-- ============================================================
SELECT
    r.names                          AS team_member,
    r.skill_set,
    r.domain                         AS expertise_domain,
    s.col_1                          AS service_category,
    s.col_2                          AS service_name
FROM resources_details r
CROSS JOIN services s
WHERE r.year  = '2026'
  AND r.month = '06'
  AND s.year  = '2026'
  AND s.month = '06'
  AND r."s.no" IS NOT NULL
  AND s.col_1 IS NOT NULL
  AND (
      LOWER(r.skill_set) LIKE '%azure%'  AND LOWER(s.col_2) LIKE '%azure%'
   OR LOWER(r.skill_set) LIKE '%aws%'    AND LOWER(s.col_2) LIKE '%aws%'
   OR LOWER(r.skill_set) LIKE '%docker%' AND LOWER(s.col_2) LIKE '%docker%'
  )
ORDER BY r.names, s.col_1;


-- ============================================================
-- 4. COMPLEX — Count team members per domain
-- ============================================================
SELECT
    COALESCE(NULLIF(TRIM(domain), ''), 'Not Specified') AS domain,
    COUNT(*) AS team_count
FROM resources_details
WHERE year  = '2026'
  AND month = '06'
  AND "s.no" IS NOT NULL
GROUP BY domain
ORDER BY team_count DESC;


-- ============================================================
-- 5. COMPLEX — Skills frequency analysis
--    (how many people have each skill keyword)
-- ============================================================
WITH skill_keywords AS (
    SELECT
        names,
        skill AS skill_keyword
    FROM resources_details
    CROSS JOIN UNNEST(
        SPLIT(REPLACE(REPLACE(skill_set, '"', ''), ' | ', ','), ',')
    ) AS t(skill)
    WHERE year  = '2026'
      AND month = '06'
      AND "s.no" IS NOT NULL
)
SELECT
    TRIM(skill_keyword)  AS skill,
    COUNT(DISTINCT names) AS team_members_with_skill
FROM skill_keywords
WHERE LENGTH(TRIM(skill_keyword)) > 2
GROUP BY TRIM(skill_keyword)
ORDER BY team_members_with_skill DESC
LIMIT 20;


-- ============================================================
-- 6. COMPLEX — Services coverage gap analysis
--    (which services does the team NOT have skills for)
-- ============================================================
WITH team_skills AS (
    SELECT LOWER(skill_set) AS all_skills
    FROM resources_details
    WHERE year = '2026' AND month = '06' AND "s.no" IS NOT NULL
),
skill_coverage AS (
    SELECT
        s.col_1 AS category,
        s.col_2 AS service_name,
        CASE
            WHEN EXISTS (
                SELECT 1 FROM team_skills ts
                WHERE ts.all_skills LIKE '%' || LOWER(s.col_2) || '%'
            ) THEN 'COVERED'
            ELSE 'GAP - No team member has this skill'
        END AS coverage_status
    FROM services s
    WHERE s.year  = '2026'
      AND s.month = '06'
      AND s.col_2 IS NOT NULL
)
SELECT *
FROM skill_coverage
ORDER BY coverage_status, category, service_name;


-- ============================================================
-- 7. COMPLEX — Partition-aware historical trend
--    (data volume across all processed dates)
-- ============================================================
SELECT
    year,
    month,
    day,
    COUNT(*) AS records_processed,
    COUNT(DISTINCT names) AS unique_members
FROM resources_details
WHERE "s.no" IS NOT NULL
GROUP BY year, month, day
ORDER BY year, month, day;


-- ============================================================
-- 8. COMPLEX — Curated vs Processed comparison
--    (verify deduplication worked)
-- ============================================================
SELECT
    'processed' AS zone,
    COUNT(*)    AS total_records
FROM resources_details
WHERE year = '2026' AND month = '06' AND "s.no" IS NOT NULL

UNION ALL

SELECT
    'curated'   AS zone,
    COUNT(*)    AS total_records
FROM resources_details_9df077d43d1ebfb6a085313353c71d48
WHERE year = '2026' AND month = '06' AND "s.no" IS NOT NULL;
