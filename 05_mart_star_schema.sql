-- ============================================================
-- STEP 5: MART layer = star schema  (CLEAN -> MART)
-- Run with "Run all". Safe to re-run.
--
--   DIM_CUSTOMER  DIM_PRODUCT  DIM_SELLER  DIM_DATE
--          \          |          |          /
--           FACT_ORDER_ITEMS  (1 row per item sold)
--   DIM_CUSTOMER   DIM_DATE
--          \          /
--           FACT_ORDERS       (1 row per order)
-- ============================================================
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE OLIST_DW;
USE SCHEMA MART;

-- ---------- DIMENSIONS ----------
CREATE OR REPLACE TABLE MART.DIM_CUSTOMER AS
SELECT customer_id,              -- one per ORDER in this dataset
       customer_unique_id,       -- the real person (use this for repeat-buyer analysis)
       city, state, zip_prefix
FROM CLEAN.CUSTOMERS;

CREATE OR REPLACE TABLE MART.DIM_PRODUCT AS
SELECT product_id, category_pt, category_en, name_length, description_length,
       photos_qty, weight_g, length_cm, height_cm, width_cm
FROM CLEAN.PRODUCTS;

CREATE OR REPLACE TABLE MART.DIM_SELLER AS
SELECT seller_id, city, state, zip_prefix
FROM CLEAN.SELLERS;

CREATE OR REPLACE TABLE MART.DIM_DATE AS
SELECT d                          AS date_key,
       YEAR(d)                    AS year,
       QUARTER(d)                 AS quarter,
       MONTH(d)                   AS month_num,
       MONTHNAME(d)               AS month_name,
       DATE_TRUNC('month', d)     AS month_start,
       DAYNAME(d)                 AS day_name,
       CASE WHEN DAYOFWEEK(d) IN (0, 6) THEN 1 ELSE 0 END AS is_weekend
FROM (SELECT DISTINCT purchase_ts::DATE AS d FROM CLEAN.ORDERS);

-- ---------- FACT 1: one row per order item ----------
CREATE OR REPLACE TABLE MART.FACT_ORDER_ITEMS AS
SELECT i.order_id,
       i.order_item_id,
       i.product_id,
       i.seller_id,
       o.customer_id,
       o.purchase_ts::DATE AS purchase_date,
       o.order_status,
       i.price,
       i.freight_value,
       i.price + i.freight_value AS line_total,
       o.delivery_days,
       o.is_late
FROM CLEAN.ORDER_ITEMS i
JOIN CLEAN.ORDERS o ON o.order_id = i.order_id;

-- ---------- FACT 2: one row per order ----------
CREATE OR REPLACE TABLE MART.FACT_ORDERS AS
WITH items AS (
    SELECT order_id, COUNT(*) AS item_count,
           SUM(price) AS items_value, SUM(freight_value) AS freight_value
    FROM CLEAN.ORDER_ITEMS GROUP BY order_id
),
pay AS (
    SELECT order_id, SUM(payment_value) AS payment_total,
           MAX(payment_installments) AS max_installments
    FROM CLEAN.PAYMENTS GROUP BY order_id
),
pay_main AS (
    SELECT order_id, payment_type AS primary_payment_type
    FROM CLEAN.PAYMENTS
    QUALIFY ROW_NUMBER() OVER (PARTITION BY order_id
                               ORDER BY payment_value DESC, payment_sequential) = 1
)
SELECT o.order_id,
       o.customer_id,
       o.purchase_ts::DATE            AS purchase_date,
       o.purchase_month,
       o.order_status,
       COALESCE(i.item_count, 0)      AS item_count,
       COALESCE(i.items_value, 0)     AS items_value,
       COALESCE(i.freight_value, 0)   AS freight_value,
       COALESCE(p.payment_total, 0)   AS payment_total,
       p.max_installments,
       pm.primary_payment_type,
       r.review_score,
       o.delivery_days,
       o.is_late,
       o.days_vs_estimate,
       CASE WHEN o.order_status IN ('canceled', 'unavailable') THEN 0 ELSE 1 END AS is_valid_sale
FROM CLEAN.ORDERS o
LEFT JOIN items    i  ON i.order_id  = o.order_id
LEFT JOIN pay      p  ON p.order_id  = o.order_id
LEFT JOIN pay_main pm ON pm.order_id = o.order_id
LEFT JOIN CLEAN.REVIEWS r ON r.order_id = o.order_id;

-- ---------- VALIDATION ----------
-- 1. Row counts
SELECT 'DIM_CUSTOMER' t, COUNT(*) n FROM MART.DIM_CUSTOMER UNION ALL
SELECT 'DIM_PRODUCT', COUNT(*) FROM MART.DIM_PRODUCT UNION ALL
SELECT 'DIM_SELLER', COUNT(*) FROM MART.DIM_SELLER UNION ALL
SELECT 'DIM_DATE', COUNT(*) FROM MART.DIM_DATE UNION ALL
SELECT 'FACT_ORDER_ITEMS', COUNT(*) FROM MART.FACT_ORDER_ITEMS UNION ALL
SELECT 'FACT_ORDERS', COUNT(*) FROM MART.FACT_ORDERS;

-- 2. Orphan check: every fact row must find its dimension row (all should be 0)
SELECT
  (SELECT COUNT(*) FROM MART.FACT_ORDER_ITEMS f LEFT JOIN MART.DIM_PRODUCT  d ON f.product_id  = d.product_id  WHERE d.product_id  IS NULL) AS items_no_product,
  (SELECT COUNT(*) FROM MART.FACT_ORDER_ITEMS f LEFT JOIN MART.DIM_SELLER   d ON f.seller_id   = d.seller_id   WHERE d.seller_id   IS NULL) AS items_no_seller,
  (SELECT COUNT(*) FROM MART.FACT_ORDER_ITEMS f LEFT JOIN MART.DIM_CUSTOMER d ON f.customer_id = d.customer_id WHERE d.customer_id IS NULL) AS items_no_customer,
  (SELECT COUNT(*) FROM MART.FACT_ORDER_ITEMS f LEFT JOIN MART.DIM_DATE     d ON f.purchase_date = d.date_key WHERE d.date_key    IS NULL) AS items_no_date,
  (SELECT COUNT(*) FROM MART.FACT_ORDERS      f LEFT JOIN MART.DIM_CUSTOMER d ON f.customer_id = d.customer_id WHERE d.customer_id IS NULL) AS orders_no_customer;

-- 3. Reconciliation: the item totals must be identical in RAW, both facts
SELECT
  (SELECT ROUND(SUM(price), 2) FROM RAW.ORDER_ITEMS)         AS raw_items_price,
  (SELECT ROUND(SUM(price), 2) FROM MART.FACT_ORDER_ITEMS)   AS fact_items_price,
  (SELECT ROUND(SUM(items_value), 2) FROM MART.FACT_ORDERS)  AS fact_orders_items_value;

-- 4. KPI preview (valid sales = everything except canceled and unavailable orders)
SELECT COUNT(*)                                        AS valid_orders,
       ROUND(SUM(items_value), 0)                      AS revenue_excl_freight,
       ROUND(SUM(items_value) / NULLIF(COUNT(CASE WHEN item_count > 0 THEN 1 END), 0), 2) AS avg_order_value,
       ROUND(AVG(review_score), 2)                     AS avg_review_score
FROM MART.FACT_ORDERS WHERE is_valid_sale = 1;
