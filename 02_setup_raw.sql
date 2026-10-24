-- STEP 2: structure (database, 3 schemas, file format, stage, 8 raw tables). Run with "Run all".
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
ALTER WAREHOUSE COMPUTE_WH SET AUTO_SUSPEND = 60;   -- stops billing after 1 idle minute

CREATE DATABASE IF NOT EXISTS OLIST_DW;
CREATE SCHEMA IF NOT EXISTS OLIST_DW.RAW;      -- data exactly as loaded
CREATE SCHEMA IF NOT EXISTS OLIST_DW.CLEAN;    -- cleaned tables
CREATE SCHEMA IF NOT EXISTS OLIST_DW.MART;     -- star schema for analysis
USE SCHEMA OLIST_DW.RAW;

CREATE OR REPLACE FILE FORMAT CSV_FMT
  TYPE = 'CSV' FIELD_DELIMITER = ',' SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"';

CREATE OR REPLACE STAGE OLIST_STAGE FILE_FORMAT = CSV_FMT;

CREATE OR REPLACE TABLE CUSTOMERS (
  customer_id VARCHAR, customer_unique_id VARCHAR,
  customer_zip_code_prefix VARCHAR, customer_city VARCHAR, customer_state VARCHAR);

CREATE OR REPLACE TABLE ORDERS (
  order_id VARCHAR, customer_id VARCHAR, order_status VARCHAR,
  order_purchase_timestamp TIMESTAMP_NTZ, order_approved_at TIMESTAMP_NTZ,
  order_delivered_carrier_date TIMESTAMP_NTZ, order_delivered_customer_date TIMESTAMP_NTZ,
  order_estimated_delivery_date TIMESTAMP_NTZ);

CREATE OR REPLACE TABLE ORDER_ITEMS (
  order_id VARCHAR, order_item_id INT, product_id VARCHAR, seller_id VARCHAR,
  shipping_limit_date TIMESTAMP_NTZ, price NUMBER(10,2), freight_value NUMBER(10,2));

CREATE OR REPLACE TABLE PAYMENTS (
  order_id VARCHAR, payment_sequential INT, payment_type VARCHAR,
  payment_installments INT, payment_value NUMBER(10,2));

CREATE OR REPLACE TABLE REVIEWS (
  review_id VARCHAR, order_id VARCHAR, review_score INT,
  review_comment_title VARCHAR, review_comment_message VARCHAR,
  review_creation_date TIMESTAMP_NTZ, review_answer_timestamp TIMESTAMP_NTZ);

CREATE OR REPLACE TABLE PRODUCTS (
  product_id VARCHAR, product_category_name VARCHAR, product_name_lenght INT,
  product_description_lenght INT, product_photos_qty INT, product_weight_g INT,
  product_length_cm INT, product_height_cm INT, product_width_cm INT);

CREATE OR REPLACE TABLE SELLERS (
  seller_id VARCHAR, seller_zip_code_prefix VARCHAR, seller_city VARCHAR, seller_state VARCHAR);

CREATE OR REPLACE TABLE CATEGORY_TRANSLATION (
  product_category_name VARCHAR, product_category_name_english VARCHAR);
