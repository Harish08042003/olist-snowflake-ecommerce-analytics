-- ============================================================
-- STEP 4: CLEAN layer  (RAW -> CLEAN)
-- Run with "Run all". Safe to re-run: every object is rebuilt.
-- ============================================================
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE OLIST_DW;
USE SCHEMA CLEAN;

-- 1. ORDERS: add delivery metrics, and only trust delivery dates for delivered orders
CREATE OR REPLACE TABLE CLEAN.ORDERS AS
SELECT
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp                         AS purchase_ts,
    order_approved_at                                AS approved_ts,
    order_delivered_carrier_date                     AS carrier_ts,
    order_delivered_customer_date                    AS delivered_ts,
    order_estimated_delivery_date                    AS estimated_delivery_ts,
    DATE_TRUNC('month', order_purchase_timestamp)    AS purchase_month,
    CASE WHEN order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL
         THEN DATEDIFF('day', order_purchase_timestamp, order_delivered_customer_date) END AS delivery_days,
    CASE WHEN order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL
         THEN IFF(order_delivered_customer_date > order_estimated_delivery_date, 1, 0) END AS is_late,
    CASE WHEN order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL
         THEN DATEDIFF('day', order_estimated_delivery_date, order_delivered_customer_date) END AS days_vs_estimate
FROM RAW.ORDERS;

-- 2. REVIEWS: keep ONE review per order (the latest answered one)
CREATE OR REPLACE TABLE CLEAN.REVIEWS AS
SELECT review_id, order_id, review_score, review_comment_title, review_comment_message,
       review_creation_date, review_answer_timestamp
FROM RAW.REVIEWS
QUALIFY ROW_NUMBER() OVER (
          PARTITION BY order_id
          ORDER BY review_answer_timestamp DESC, review_id) = 1;

-- 3. PRODUCTS: fix column typos, fill missing categories, add English names
CREATE OR REPLACE TABLE CLEAN.PRODUCTS AS
SELECT
    p.product_id,
    COALESCE(p.product_category_name, 'unknown')                                  AS category_pt,
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category_en,
    p.product_name_lenght        AS name_length,
    p.product_description_lenght AS description_length,
    p.product_photos_qty         AS photos_qty,
    p.product_weight_g           AS weight_g,
    p.product_length_cm          AS length_cm,
    p.product_height_cm          AS height_cm,
    p.product_width_cm           AS width_cm
FROM RAW.PRODUCTS p
LEFT JOIN RAW.CATEGORY_TRANSLATION t ON p.product_category_name = t.product_category_name;

-- 4. PAYMENTS: drop zero-value rows (6 vouchers + 3 'not_defined')
CREATE OR REPLACE TABLE CLEAN.PAYMENTS AS
SELECT * FROM RAW.PAYMENTS WHERE payment_value > 0;

-- 5. ORDER_ITEMS: add line total
CREATE OR REPLACE TABLE CLEAN.ORDER_ITEMS AS
SELECT *, price + freight_value AS line_total
FROM RAW.ORDER_ITEMS;

-- 6. CUSTOMERS and SELLERS: standardise state codes
CREATE OR REPLACE TABLE CLEAN.CUSTOMERS AS
SELECT customer_id, customer_unique_id, customer_zip_code_prefix AS zip_prefix,
       customer_city AS city, UPPER(customer_state) AS state
FROM RAW.CUSTOMERS;

CREATE OR REPLACE TABLE CLEAN.SELLERS AS
SELECT seller_id, seller_zip_code_prefix AS zip_prefix,
       seller_city AS city, UPPER(seller_state) AS state
FROM RAW.SELLERS;

-- 7. DATA QUALITY REPORT: every issue found, with counts (copy this into your README)
CREATE OR REPLACE TABLE CLEAN.DQ_REPORT AS
SELECT 'Duplicate review_id in raw reviews' AS issue,
       (SELECT COUNT(*) - COUNT(DISTINCT review_id) FROM RAW.REVIEWS) AS rows_affected,
       'Kept one review per order (latest)' AS action
UNION ALL SELECT 'Orders with more than one review',
       (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM RAW.REVIEWS),
       'Kept latest review only'
UNION ALL SELECT 'Delivered orders with no delivery date',
       (SELECT COUNT(*) FROM RAW.ORDERS WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL),
       'Excluded from delivery-time metrics'
UNION ALL SELECT 'Non-delivered orders that have a delivery date',
       (SELECT COUNT(*) FROM RAW.ORDERS WHERE order_status <> 'delivered' AND order_delivered_customer_date IS NOT NULL),
       'Ignored delivery date (status is not delivered)'
UNION ALL SELECT 'Orders with no items',
       (SELECT COUNT(*) FROM RAW.ORDERS o WHERE NOT EXISTS (SELECT 1 FROM RAW.ORDER_ITEMS i WHERE i.order_id = o.order_id)),
       'Excluded from item-level revenue'
UNION ALL SELECT 'Orders with no payment record',
       (SELECT COUNT(*) FROM RAW.ORDERS o WHERE NOT EXISTS (SELECT 1 FROM RAW.PAYMENTS p WHERE p.order_id = o.order_id)),
       'Flagged'
UNION ALL SELECT 'Zero-value payments (voucher / not_defined)',
       (SELECT COUNT(*) FROM RAW.PAYMENTS WHERE payment_value = 0),
       'Removed'
UNION ALL SELECT 'Products with no category',
       (SELECT COUNT(*) FROM RAW.PRODUCTS WHERE product_category_name IS NULL),
       'Set to unknown'
UNION ALL SELECT 'Products whose category has no English translation',
       (SELECT COUNT(*) FROM RAW.PRODUCTS p WHERE p.product_category_name IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM RAW.CATEGORY_TRANSLATION t WHERE t.product_category_name = p.product_category_name)),
       'Kept the Portuguese name';

-- 8. CHECKS
SELECT * FROM CLEAN.DQ_REPORT;

SELECT 'CLEAN.ORDERS' t, COUNT(*) n FROM CLEAN.ORDERS UNION ALL
SELECT 'CLEAN.REVIEWS', COUNT(*) FROM CLEAN.REVIEWS UNION ALL
SELECT 'CLEAN.PRODUCTS', COUNT(*) FROM CLEAN.PRODUCTS UNION ALL
SELECT 'CLEAN.PAYMENTS', COUNT(*) FROM CLEAN.PAYMENTS UNION ALL
SELECT 'CLEAN.ORDER_ITEMS', COUNT(*) FROM CLEAN.ORDER_ITEMS UNION ALL
SELECT 'CLEAN.CUSTOMERS', COUNT(*) FROM CLEAN.CUSTOMERS UNION ALL
SELECT 'CLEAN.SELLERS', COUNT(*) FROM CLEAN.SELLERS;

SELECT COUNT(*) AS delivered_with_metrics, ROUND(AVG(delivery_days),1) AS avg_delivery_days,
       ROUND(AVG(is_late)*100,1) AS pct_late
FROM CLEAN.ORDERS WHERE delivery_days IS NOT NULL;
