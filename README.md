# E-Commerce Revenue, Delivery & Customer Satisfaction Analytics
### Olist (Brazilian marketplace) • Snowflake • Layered SQL • Power BI

An end-to-end analytics project on the **Brazilian E-Commerce Public Dataset by Olist** (Kaggle).
It loads 8 raw CSVs into Snowflake, builds a **RAW → CLEAN → MART** pipeline with a star schema,
answers **7 business questions** in SQL, and presents the findings in a **3-page Power BI dashboard**.

This project demonstrates cloud data warehousing (Snowflake), dimensional modelling
(star schema), advanced SQL (CTEs, window functions), data-quality handling, and BI on a warehouse.

---

## 1. Problem statement

Olist is a Brazilian e-commerce marketplace. Management wants to understand:

1. How is revenue growing month over month, and are there seasonal peaks?
2. Which product categories drive revenue?
3. Does late delivery hurt customer satisfaction — and how much?
4. How many customers come back for a second purchase?
5. Is seller revenue concentrated (a Pareto pattern)?
6. How do customers pay?
7. Which states matter most for revenue, and how does delivery perform there?

## 2. Data source

- **Dataset:** [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) — Kaggle
- **Licence:** CC BY-NC-SA 4.0 (see Kaggle page)
- **Rows used:** 8 tables, ~550,759 rows total (geolocation excluded — 1M rows, not needed for this analysis)
- **Period:** Sep 2016 – Oct 2018 (analysis limited to complete months: **Jan 2017 – Aug 2018**)

**Credit:** Data is published by Olist on Kaggle. Raw CSVs are **not** committed to this repo;
download them from the link above and place them in a Snowflake stage to reproduce.

## 3. Architecture

Three-layer Snowflake database **`OLIST_DW`**:

| Schema | Purpose |
|---|---|
| **RAW** | CSVs loaded exactly as-is via internal stage + `COPY INTO` |
| **CLEAN** | Cleaned tables + `DQ_REPORT` (one row per data-quality issue) |
| **MART** | Star schema used by SQL analysis and Power BI |

**Star schema:**

- Dimensions: `DIM_CUSTOMER`, `DIM_PRODUCT`, `DIM_SELLER`, `DIM_DATE`
- Fact 1: `FACT_ORDER_ITEMS` — one row per item sold (product / seller / category grain)
- Fact 2: `FACT_ORDERS` — one row per order (delivery, payment, review grain)

**Key modelling rules:**
- `customer_id` is per order; `customer_unique_id` is the real person (used for repeat-buyer analysis)
- Reviews are order-level, so `review_score` lives only on `FACT_ORDERS` (never averaged on the item table)
- `is_valid_sale = 1` excludes only `canceled` / `unavailable` orders — used for all revenue KPIs

![Star schema](screenshots/model_view.png)

## 4. Data-quality findings

All 9 issues found and resolved before modelling (full report: [`docs/data_quality_report.md`](docs/data_quality_report.md)).

![DQ report](screenshots/dq_report.png)

| # | Issue | Rows | Action |
|---|---|---:|---|
| 1 | Duplicate `review_id` in raw reviews | 814 | Kept one review per order (latest) |
| 2 | Orders with more than one review | 551 | Kept latest review only |
| 3 | Delivered orders with no delivery date | 8 | Excluded from delivery-time metrics |
| 4 | Non-delivered orders that have a delivery date | 6 | Ignored delivery date |
| 5 | Orders with no items | 775 | Excluded from item-level revenue |
| 6 | Orders with no payment record | 1 | Flagged |
| 7 | Zero-value payments (voucher / not_defined) | 9 | Removed |
| 8 | Products with no category | 610 | Set to `unknown` |
| 9 | Products whose category has no English translation | 13 | Kept Portuguese name |

**Reconciliation (proof the pipeline is lossless):**
- Item price total: **R$13,591,643.70** in RAW, in `FACT_ORDER_ITEMS`, and in `FACT_ORDERS` — identical
- Orphan-key checks across all fact → dimension joins: **0** rows
- Payment totals (~R$16.01M) vs item + freight (~R$15.84M) differ by ~1% — see Limitations

## 5. Business findings

Analysis queries: [`sql/06_business_analysis.sql`](sql/06_business_analysis.sql).
All numbers below are verified in Snowflake on the MART star schema.

### Q1 — Monthly revenue trend
Peak month: **Nov 2017** — 7,423 orders, **R$1,003,862** revenue, **+52.1% MoM**.
Dec 2017 dropped **−26.1%** — the classic post-Black-Friday cliff.
The Nov 2017 spike is **likely** Black Friday (inference, not stated in the data).

![Overview](screenshots/overview.png)

### Q2 — Top categories by revenue
| Category | Revenue | Share |
|---|---:|---:|
| health_beauty | R$1,255,695 | 9.3% |
| watches_gifts | R$1,198,185 | 8.9% |
| bed_bath_table | R$1,035,964 | 7.7% |
| sports_leisure | — | 7.3% |
| computers_accessories | — | 6.7% |

Top 10 categories = **62.4%** of total revenue.

### Q3 — Late delivery vs customer satisfaction
| Delivery status | Orders | Avg review | % 1–2 stars |
|---|---:|---:|---:|
| On time / early | 89,443 | **4.29** | — |
| 1–3 days late | 1,852 | 3.29 | — |
| 4–7 days late | 1,748 | 2.10 | — |
| 8+ days late | 2,781 | **1.70** | 79.3% |

**A 2.6-point review drop between on-time and 8+ days late.** This is the strongest single driver of dissatisfaction in the data.

![Delivery & satisfaction](screenshots/delivery_satisfaction.png)

### Q4 — Repeat-buyer rate by first-purchase quarter
5.07% (Q1-2017 cohort) → ~1.01% (Q3-2018 cohort).

**⚠️ Caveat (must not be read as "declining loyalty"):** later cohorts have had less time to make a second purchase. This is **right-censoring**, not a behavioural shift.

### Q5 — Seller revenue concentration (Pareto)
- Top 10% of sellers (306 sellers) = **67.5%** of revenue
- Next 10% = 15.1%
- Bottom 80% = 17.4%

**High concentration risk** — losing top sellers would materially damage revenue.

![Customers & sellers](screenshots/customers_sellers.png)

### Q6 — Payment methods
| Method | Orders | Share | Avg installments | Avg order value |
|---|---:|---:|---:|---:|
| credit_card | 74,116 | 75.5% | 3.6 | R$166.64 |
| boleto | 19,539 | 19.9% | — | — |
| voucher | 3,037 | 3.1% | — | — |
| debit_card | 1,514 | 1.5% | — | — |

### Q7 — Revenue by state & delivery performance there
| State | Orders | Revenue | Share | Avg delivery days | % late |
|---|---:|---:|---:|---:|---:|
| SP | 41,127 | R$5,163,867 | 38.3% | 8.7 | 5.9% |
| RJ | — | — | 13.4% | 15.2 | 13.5% |
| MG | — | — | 11.7% | — | — |
| BA | — | — | — | 19.3 | 14.0% |

Freight represents **13.8%–19.7%** of item value depending on state.

## 6. Recommendations

**All of the below are suggested next steps derived from this analysis — not facts.**

1. **Carrier & estimate accuracy in RJ and BA** — these states have 2–3× the late rate of SP and visibly lower review scores. Better delivery estimates or regional carrier SLAs would lift satisfaction fastest.
2. **Seller retention programme for the top 10%** — they generate 67.5% of revenue. Losing one is a material risk.
3. **Loyalty / second-purchase offers** — repeat rate is structurally low; even a small lift moves repeat revenue meaningfully.
4. **Promote instalment plans** — 75.5% of orders already use credit card with ~3.6 instalments. Highlighting instalments at checkout could lift AOV.
5. **Plan for the November peak** — stock, staffing, and logistics should be pre-positioned for a ~50% MoM spike around Black Friday.

## 7. Limitations

- **Q4 right-censoring:** repeat-buyer rates for later cohorts are understated — later customers have had less time to return. Do not read Q4 as a downward trend.
- **Nov 2017 peak is an inference.** The data shows the spike; attributing it to Black Friday is an interpretation, not a fact in the dataset.
- **Payments vs items gap (~1%):** payment totals (R$16.01M) exceed item + freight totals (R$15.84M) by ~1% — consistent with multi-payment orders / voucher stacking.
- **Olist is one marketplace, one country, one time window.** Results should not be generalised to other markets.
- **Delivery metrics exclude 8 delivered orders with missing delivery dates** (issue 3 in the DQ report).
- **Power BI avg review card shows 4.25 vs SQL's 4.29** for on-time orders — the DAX measure filters on `IS_VALID_SALE = 1` (excludes canceled/unavailable), while the SQL Q3 uses all orders with a valid delivery date. Both are correct; the SQL figure is used everywhere in this README.

## 8. How to reproduce

1. Sign up for a Snowflake trial account. Set role `SYSADMIN`, warehouse `COMPUTE_WH` (X-Small, auto-suspend 60s).
2. Download the 8 CSVs from the Kaggle link above (skip the geolocation file).
3. In Snowsight, run the SQL files **in this order**, one at a time:
   1. `sql/02_setup_raw.sql` — DB, schemas, file format, stage, raw tables
   2. Upload the 8 CSVs to `@OLIST_STAGE` (Snowsight → Data → Load)
   3. `sql/03_load_raw.sql` — COPY INTO + count check
   4. `sql/04_clean_layer.sql` — CLEAN tables + DQ_REPORT
   5. `sql/05_mart_star_schema.sql` — MART dimensions + facts + validation
   6. `sql/05b_dim_date_full_calendar.sql` — replaces DIM_DATE with a continuous 1,096-day calendar
   7. `sql/06_business_analysis.sql` — the 7 business queries (run **one at a time**)
4. Open `powerbi/olist_snowflake_dashboard.pbix` in Power BI Desktop. Use **Get Data → Snowflake** with your own account URL, warehouse `COMPUTE_WH`, role `SYSADMIN`.
5. Refresh. The 6 MART tables import; the star-schema relationships are already defined in the file.

Expected row counts after each step are in the comments at the top of each SQL file.

## 9. Tools

- **Snowflake** — cloud data warehouse (trial). RAW/CLEAN/MART layering, `COPY INTO`, `GENERATOR`, `QUALIFY`, `NTILE`, `LAG`.
- **SQL** — CTEs, window functions (running totals, MoM growth, ranking, cohort analysis).
- **Power BI Desktop** — Import mode, star-schema model, DAX measures, Mark-as-date-table, 3-page report.
- **Kaggle** — data source (Olist).

---

**Author:** Kedar Pawar
**Data credit:** Olist / Kaggle — Brazilian E-Commerce Public Dataset