-- ============================================================
-- STEP 6: Business analysis (7 questions) on the MART star schema
-- Run ONE query at a time: select it, then click Run.
-- "Valid sale" = every order except canceled / unavailable.
-- Complete months only: Jan 2017 - Aug 2018 (2016 and Sep 2018 are almost empty).
-- ============================================================
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE OLIST_DW;
USE SCHEMA MART;

-- ------------------------------------------------------------
-- Q1. How is revenue growing month over month?   (CTE + LAG)
-- ------------------------------------------------------------
WITH monthly AS (
    SELECT purchase_month::DATE AS month,
           COUNT(*)            AS orders,
           ROUND(SUM(items_value), 0) AS revenue
    FROM MART.FACT_ORDERS
    WHERE is_valid_sale = 1
      AND purchase_month BETWEEN '2017-01-01' AND '2018-08-01'
    GROUP BY 1
)
SELECT month, orders, revenue,
       ROUND((revenue - LAG(revenue) OVER (ORDER BY month))
             / NULLIF(LAG(revenue) OVER (ORDER BY month), 0) * 100, 1) AS revenue_growth_pct
FROM monthly
ORDER BY month;

-- ------------------------------------------------------------
-- Q2. Which product categories drive revenue?   (share + running total)
-- ------------------------------------------------------------
WITH cat AS (
    SELECT p.category_en AS category,
           ROUND(SUM(f.price), 0) AS revenue,
           COUNT(DISTINCT f.order_id) AS orders
    FROM MART.FACT_ORDER_ITEMS f
    JOIN MART.DIM_PRODUCT p ON p.product_id = f.product_id
    WHERE f.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY 1
)
SELECT category, revenue, orders,
       ROUND(revenue / SUM(revenue) OVER () * 100, 1) AS share_pct,
       ROUND(SUM(revenue) OVER (ORDER BY revenue DESC) / SUM(revenue) OVER () * 100, 1) AS cumulative_share_pct
FROM cat
ORDER BY revenue DESC
LIMIT 10;

-- ------------------------------------------------------------
-- Q3. Does late delivery hurt customer satisfaction?
-- ------------------------------------------------------------
SELECT CASE WHEN days_vs_estimate <= 0 THEN '1. On time or early'
            WHEN days_vs_estimate <= 3 THEN '2. 1-3 days late'
            WHEN days_vs_estimate <= 7 THEN '3. 4-7 days late'
            ELSE '4. 8+ days late' END AS delivery_status,
       COUNT(*)                              AS orders,
       ROUND(AVG(review_score), 2)           AS avg_review_score,
       ROUND(AVG(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) * 100, 1) AS pct_low_reviews
FROM MART.FACT_ORDERS
WHERE delivery_days IS NOT NULL AND review_score IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- ------------------------------------------------------------
-- Q4. How many customers come back?   (repeat-buyer rate by first-purchase quarter)
-- ------------------------------------------------------------
WITH cust AS (
    SELECT c.customer_unique_id,
           MIN(f.purchase_date) AS first_purchase,
           COUNT(*)             AS orders
    FROM MART.FACT_ORDERS f
    JOIN MART.DIM_CUSTOMER c ON c.customer_id = f.customer_id
    WHERE f.is_valid_sale = 1
    GROUP BY 1
)
SELECT DATE_TRUNC('quarter', first_purchase)::DATE AS first_purchase_quarter,
       COUNT(*)                                    AS customers,
       SUM(CASE WHEN orders >= 2 THEN 1 ELSE 0 END) AS repeat_customers,
       ROUND(AVG(CASE WHEN orders >= 2 THEN 1 ELSE 0 END) * 100, 2) AS repeat_rate_pct
FROM cust
WHERE first_purchase BETWEEN '2017-01-01' AND '2018-08-31'
GROUP BY 1
ORDER BY 1;

-- ------------------------------------------------------------
-- Q5. Is seller revenue concentrated?   (NTILE deciles / Pareto)
-- ------------------------------------------------------------
WITH seller_rev AS (
    SELECT f.seller_id, SUM(f.price) AS revenue
    FROM MART.FACT_ORDER_ITEMS f
    WHERE f.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY 1
),
ranked AS (
    SELECT seller_id, revenue,
           NTILE(10) OVER (ORDER BY revenue DESC) AS decile
    FROM seller_rev
)
SELECT decile,
       COUNT(*)                                          AS sellers,
       ROUND(SUM(revenue), 0)                            AS revenue,
       ROUND(SUM(revenue) / SUM(SUM(revenue)) OVER () * 100, 1) AS share_pct
FROM ranked
GROUP BY decile
ORDER BY decile;

-- ------------------------------------------------------------
-- Q6. How do customers pay?
-- ------------------------------------------------------------
SELECT primary_payment_type AS payment_type,
       COUNT(*)                                   AS orders,
       ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 1) AS share_pct,
       ROUND(AVG(payment_total), 2)               AS avg_order_payment,
       ROUND(AVG(max_installments), 1)            AS avg_installments
FROM MART.FACT_ORDERS
WHERE is_valid_sale = 1 AND primary_payment_type IS NOT NULL
GROUP BY 1
ORDER BY orders DESC;

-- ------------------------------------------------------------
-- Q7. Which states matter, and how is delivery there?
-- ------------------------------------------------------------
SELECT c.state,
       COUNT(*)                                       AS orders,
       ROUND(SUM(f.items_value), 0)                   AS revenue,
       ROUND(SUM(f.items_value) / SUM(SUM(f.items_value)) OVER () * 100, 1) AS revenue_share_pct,
       ROUND(AVG(f.delivery_days), 1)                 AS avg_delivery_days,
       ROUND(AVG(f.is_late) * 100, 1)                 AS pct_late,
       ROUND(SUM(f.freight_value) / NULLIF(SUM(f.items_value), 0) * 100, 1) AS freight_pct_of_items
FROM MART.FACT_ORDERS f
JOIN MART.DIM_CUSTOMER c ON c.customer_id = f.customer_id
WHERE f.is_valid_sale = 1
GROUP BY c.state
ORDER BY revenue DESC
LIMIT 10;
