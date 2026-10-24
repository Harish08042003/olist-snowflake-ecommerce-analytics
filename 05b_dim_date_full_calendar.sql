-- STEP 5b: replace DIM_DATE with a CONTINUOUS calendar (2016-01-01 to 2018-12-31).
-- Power BI time-intelligence (DATEADD, "Mark as date table") needs no gaps in the date column.
-- Run with "Run all", then refresh the data in Power BI.
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE OLIST_DW;
USE SCHEMA MART;

CREATE OR REPLACE TABLE MART.DIM_DATE AS
WITH days AS (
    SELECT DATEADD(day, ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2016-01-01'::DATE) AS d
    FROM TABLE(GENERATOR(ROWCOUNT => 1096))
)
SELECT d                          AS date_key,
       YEAR(d)                    AS year,
       QUARTER(d)                 AS quarter,
       MONTH(d)                   AS month_num,
       MONTHNAME(d)               AS month_name,
       DATE_TRUNC('month', d)     AS month_start,
       DAYNAME(d)                 AS day_name,
       CASE WHEN DAYOFWEEK(d) IN (0, 6) THEN 1 ELSE 0 END AS is_weekend
FROM days;

-- Expected: 1096 rows, 2016-01-01 to 2018-12-31, 0 orphan order dates
SELECT COUNT(*) AS days, MIN(date_key) AS first_day, MAX(date_key) AS last_day FROM MART.DIM_DATE;
SELECT COUNT(*) AS orders_without_date_row
FROM MART.FACT_ORDERS f LEFT JOIN MART.DIM_DATE d ON f.purchase_date = d.date_key
WHERE d.date_key IS NULL;
