-- 08_analytical_queries.sql   (answer key for Power BI testing)
USE Syntecxhub_Bank_Loan_Analysis;
GO

/* ======================================================================== A. SUMMARY KPIs   (run section A as ONE batch: it uses variables) ======================================================================== */
DECLARE @cur  DATE = (SELECT MAX(d.Full_Date) FROM fact.Loans f JOIN dim.Date d ON d.Date_Key = f.Issue_Date_Key);
DECLARE @prev DATE = DATEADD(MONTH, -1, @cur);
SELECT @cur AS latest_issue_month, @prev AS previous_month;


-- A1. Headline KPIs: total, month-to-date (latest issue month), previous month, month-on-month %
WITH k AS (
  SELECT
    COUNT_BIG(*)                                                       AS total_loans,
    SUM(CASE WHEN d.Full_Date = @cur  THEN 1 ELSE 0 END)               AS mtd_loans,
    SUM(CASE WHEN d.Full_Date = @prev THEN 1 ELSE 0 END)               AS pmtd_loans,
    SUM(f.Funded_Amount)                                               AS total_funded,
    SUM(CASE WHEN d.Full_Date = @cur  THEN f.Funded_Amount ELSE 0 END) AS mtd_funded,
    SUM(CASE WHEN d.Full_Date = @prev THEN f.Funded_Amount ELSE 0 END) AS pmtd_funded,
    SUM(f.Total_Payment)                                               AS total_received,
    SUM(CASE WHEN d.Full_Date = @cur  THEN f.Total_Payment ELSE 0 END) AS mtd_received,
    SUM(CASE WHEN d.Full_Date = @prev THEN f.Total_Payment ELSE 0 END) AS pmtd_received,
    AVG(f.Interest_Rate)                                               AS avg_rate,
    AVG(CASE WHEN d.Full_Date = @cur  THEN f.Interest_Rate END)        AS mtd_rate,
    AVG(CASE WHEN d.Full_Date = @prev THEN f.Interest_Rate END)        AS pmtd_rate,
    AVG(f.DTI)                                                         AS avg_dti,      -- NULL DTIs are ignored
    AVG(CASE WHEN d.Full_Date = @cur  THEN f.DTI END)                  AS mtd_dti,
    AVG(CASE WHEN d.Full_Date = @prev THEN f.DTI END)                  AS pmtd_dti
  FROM fact.Loans f JOIN dim.Date d ON d.Date_Key = f.Issue_Date_Key)
SELECT v.KPI, v.[Total], v.MTD, v.PMTD,
       CAST(100.0 * (v.MTD - v.PMTD) / NULLIF(v.PMTD, 0) AS DECIMAL(9,2)) AS MoM_Pct
FROM k CROSS APPLY (VALUES
  ('Total Loan Applications', CAST(total_loans    AS DECIMAL(20,2)), CAST(mtd_loans    AS DECIMAL(20,2)), CAST(pmtd_loans    AS DECIMAL(20,2))),
  ('Total Funded Amount',     CAST(total_funded   AS DECIMAL(20,2)), CAST(mtd_funded   AS DECIMAL(20,2)), CAST(pmtd_funded   AS DECIMAL(20,2))),
  ('Total Amount Received',   CAST(total_received AS DECIMAL(20,2)), CAST(mtd_received AS DECIMAL(20,2)), CAST(pmtd_received AS DECIMAL(20,2))),
  ('Average Interest Rate %', CAST(avg_rate       AS DECIMAL(20,2)), CAST(mtd_rate     AS DECIMAL(20,2)), CAST(pmtd_rate     AS DECIMAL(20,2))),
  ('Average DTI',             CAST(avg_dti        AS DECIMAL(20,2)), CAST(mtd_dti      AS DECIMAL(20,2)), CAST(pmtd_dti      AS DECIMAL(20,2)))
) v(KPI, [Total], MTD, PMTD);
GO


-- A2. Good / At Risk / Bad summary
SELECT ls.Loan_Class,
       COUNT_BIG(*) AS loans,
       CAST(100.0 * COUNT_BIG(*) / SUM(COUNT_BIG(*)) OVER () AS DECIMAL(5,2)) AS pct_of_loans,
       SUM(f.Funded_Amount)  AS funded,
       SUM(f.Total_Payment)  AS received,
       CAST(SUM(f.Total_Payment) / SUM(f.Funded_Amount) AS DECIMAL(6,3)) AS received_to_funded
FROM fact.Loans f JOIN dim.Loan_Status ls ON ls.Loan_Status_Key = f.Loan_Status_Key
GROUP BY ls.Loan_Class, ls.Class_Sort ORDER BY ls.Class_Sort;

-- A3. By loan status, with net return (Fully Paid and Charged Off ratios = the fair repayment ratio, resolved loans only)
SELECT ls.Loan_Status, ls.Loan_Class,
       COUNT_BIG(*) AS loans,
       SUM(f.Funded_Amount) AS funded,
       SUM(f.Total_Payment) AS received,
       CAST(SUM(f.Total_Payment) / SUM(f.Funded_Amount) AS DECIMAL(6,3)) AS received_to_funded,
       SUM(f.Total_Payment) - SUM(f.Funded_Amount) AS net_return
FROM fact.Loans f JOIN dim.Loan_Status ls ON ls.Loan_Status_Key = f.Loan_Status_Key
GROUP BY ls.Loan_Status, ls.Loan_Class, ls.Class_Sort
ORDER BY ls.Class_Sort, loans DESC;
GO

/* ======================================================================== B. TRENDS OVER TIME (by issue month) ======================================================================== */

-- B1. Monthly trend
SELECT d.Year_Month,
       COUNT_BIG(*) AS loans,
       SUM(f.Funded_Amount) AS funded,
       SUM(f.Total_Payment) AS received,
       CAST(AVG(f.Interest_Rate) AS DECIMAL(6,2)) AS avg_rate
FROM fact.Loans f JOIN dim.Date d ON d.Date_Key = f.Issue_Date_Key
GROUP BY d.Year_Month, d.Month_Sort ORDER BY d.Month_Sort;


-- B2. Yearly trend with year-on-year growth
WITH y AS (
  SELECT d.[Year] AS yr, COUNT_BIG(*) AS loans, SUM(f.Funded_Amount) AS funded, SUM(f.Total_Payment) AS received
  FROM fact.Loans f JOIN dim.Date d ON d.Date_Key = f.Issue_Date_Key
  GROUP BY d.[Year])
SELECT yr, loans, funded, received,
       CAST(100.0 * (loans  - LAG(loans)  OVER (ORDER BY yr)) / NULLIF(LAG(loans)  OVER (ORDER BY yr), 0) AS DECIMAL(9,2)) AS loans_yoy_pct,
       CAST(100.0 * (funded - LAG(funded) OVER (ORDER BY yr)) / NULLIF(LAG(funded) OVER (ORDER BY yr), 0) AS DECIMAL(9,2)) AS funded_yoy_pct
FROM y ORDER BY yr;
GO

/* =================================================================================================================================================================================
   C. FACTOR PROFILE: volume, money, rate and MATURED-ONLY charge-off rate for every level of 12 factors, in one pass.
   ================================================================================================================================================================================= */
DROP TABLE IF EXISTS audit.Factor_Profile;

WITH L AS (
  SELECT f.Funded_Amount, f.Total_Payment, f.Interest_Rate, f.Is_Matured, ls.Is_Charged_Off,
         g.Grade, t.Term_Label, t.Term_Months,
         f.DTI_Band_Key,         dtb.Band_Label AS DTI_Band,
         f.Income_Band_Key,      inb.Band_Label AS Income_Band,
         f.Loan_Amount_Band_Key, amb.Band_Label AS Amount_Band,
         f.Risk_Band_Key,        rkb.Band_Label AS Risk_Band,
         p.Purpose_Key, p.Purpose_Label,
         ho.Home_Ownership_Key, ho.Home_Ownership,
         vs.Verification_Key, vs.Verification_Status,
         el.Emp_Length_Sort, el.Emp_Length_Label,
         apt.Application_Type_Key, apt.Application_Type,
         geo.Geography_Key, geo.State_Code
  FROM fact.Loans f
  JOIN dim.Loan_Status ls         ON ls.Loan_Status_Key       = f.Loan_Status_Key
  JOIN dim.Grade g                ON g.Grade_Key              = f.Grade_Key
  JOIN dim.Term t                 ON t.Term_Key               = f.Term_Key
  JOIN ref.DTI_Band dtb           ON dtb.Band_Key             = f.DTI_Band_Key
  JOIN ref.Income_Band inb        ON inb.Band_Key             = f.Income_Band_Key
  JOIN ref.Loan_Amount_Band amb   ON amb.Band_Key             = f.Loan_Amount_Band_Key
  JOIN ref.Risk_Band rkb          ON rkb.Band_Key             = f.Risk_Band_Key
  JOIN dim.Purpose p              ON p.Purpose_Key            = f.Purpose_Key
  JOIN dim.Home_Ownership ho      ON ho.Home_Ownership_Key    = f.Home_Ownership_Key
  JOIN dim.Verification_Status vs ON vs.Verification_Key      = f.Verification_Key
  JOIN dim.Employment_Length el   ON el.Emp_Length_Key        = f.Emp_Length_Key
  JOIN dim.Application_Type apt   ON apt.Application_Type_Key = f.Application_Type_Key
  JOIN dim.Geography geo          ON geo.Geography_Key        = f.Geography_Key)
SELECT v.Factor, v.[Level], MIN(v.Sort) AS Sort,
       COUNT_BIG(*)                                    AS loans,
       SUM(L.Funded_Amount)                            AS funded,
       SUM(L.Total_Payment)                            AS received,
       CAST(AVG(L.Interest_Rate) AS DECIMAL(6,2))      AS avg_rate,
       SUM(CASE WHEN L.Is_Matured = 1 THEN 1 ELSE 0 END)                            AS matured_loans,
       SUM(CASE WHEN L.Is_Matured = 1 AND L.Is_Charged_Off = 1 THEN 1 ELSE 0 END)   AS matured_charged_off,
       CAST(100.0 * SUM(CASE WHEN L.Is_Matured = 1 AND L.Is_Charged_Off = 1 THEN 1 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN L.Is_Matured = 1 THEN 1 ELSE 0 END), 0) AS DECIMAL(5,2)) AS chargeoff_pct_matured
INTO audit.Factor_Profile
FROM L
CROSS APPLY (VALUES
  ('01 Grade',               CAST(L.Grade AS VARCHAR(30)),           ASCII(L.Grade)),
  ('02 Term',                CAST(L.Term_Label AS VARCHAR(30)),      L.Term_Months),
  ('03 DTI band',            CAST(L.DTI_Band AS VARCHAR(30)),        L.DTI_Band_Key),
  ('04 Income band',         CAST(L.Income_Band AS VARCHAR(30)),     L.Income_Band_Key),
  ('05 Loan amount band',    CAST(L.Amount_Band AS VARCHAR(30)),     L.Loan_Amount_Band_Key),
  ('06 Credit score band',   CAST(L.Risk_Band AS VARCHAR(30)),       L.Risk_Band_Key),
  ('07 Purpose',             CAST(L.Purpose_Label AS VARCHAR(30)),   L.Purpose_Key),
  ('08 Home ownership',      CAST(L.Home_Ownership AS VARCHAR(30)),  L.Home_Ownership_Key),
  ('09 Verification status', CAST(L.Verification_Status AS VARCHAR(30)), L.Verification_Key),
  ('10 Employment length',   CAST(L.Emp_Length_Label AS VARCHAR(30)), L.Emp_Length_Sort),
  ('11 Application type',    CAST(L.Application_Type AS VARCHAR(30)), L.Application_Type_Key),
  ('12 State',               CAST(L.State_Code AS VARCHAR(30)),      L.Geography_Key)
) v(Factor, [Level], Sort)
GROUP BY v.Factor, v.[Level];
GO


-- C1. The profile (118 rows expected)
SELECT * FROM audit.Factor_Profile ORDER BY Factor, Sort;


-- C2. Self-check: every factor must total 2,260,668 loans and 34,004,208,600.00 funded
SELECT Factor, COUNT(*) AS levels, SUM(loans) AS total_loans, SUM(funded) AS total_funded
FROM audit.Factor_Profile GROUP BY Factor ORDER BY Factor;
GO


-- C3. Is risk priced adequately? Grade vs charge-off vs net return (matured loans, simple return, not annualized)
SELECT g.Grade,
       COUNT_BIG(*) AS matured_loans,
       CAST(AVG(f.Interest_Rate) AS DECIMAL(6,2)) AS avg_rate,
       CAST(100.0 * SUM(CASE WHEN ls.Is_Charged_Off = 1 THEN 1 ELSE 0 END) / COUNT_BIG(*) AS DECIMAL(5,2)) AS chargeoff_pct,
       SUM(f.Funded_Amount) AS funded,
       SUM(f.Total_Payment) AS received,
       CAST(100.0 * (SUM(f.Total_Payment) - SUM(f.Funded_Amount)) / SUM(f.Funded_Amount) AS DECIMAL(6,2)) AS net_return_pct
FROM fact.Loans f
JOIN dim.Grade g        ON g.Grade_Key = f.Grade_Key
JOIN dim.Loan_Status ls ON ls.Loan_Status_Key = f.Loan_Status_Key
WHERE f.Is_Matured = 1
GROUP BY g.Grade ORDER BY g.Grade;


-- C4. Grade x term, matured only: separates "riskier grade" from "longer term"
SELECT g.Grade, t.Term_Label,
       COUNT_BIG(*) AS matured_loans,
       CAST(100.0 * SUM(CASE WHEN ls.Is_Charged_Off = 1 THEN 1 ELSE 0 END) / COUNT_BIG(*) AS DECIMAL(5,2)) AS chargeoff_pct
FROM fact.Loans f
JOIN dim.Grade g        ON g.Grade_Key = f.Grade_Key
JOIN dim.Term t         ON t.Term_Key = f.Term_Key
JOIN dim.Loan_Status ls ON ls.Loan_Status_Key = f.Loan_Status_Key
WHERE f.Is_Matured = 1
GROUP BY g.Grade, t.Term_Label ORDER BY g.Grade, t.Term_Label;
GO

/* ======================================================================== D. FACTORS AFFECTING APPROVAL (accepted vs rejected; shared dimensions) ======================================================================== */

-- D1. By requested loan amount band (all years)
SELECT b.Band_Label, a.accepted, r.rejected,
       CAST(100.0 * a.accepted / NULLIF(a.accepted + r.rejected, 0) AS DECIMAL(5,2)) AS approval_rate_pct
FROM ref.Loan_Amount_Band b
LEFT JOIN (SELECT Loan_Amount_Band_Key AS k, COUNT_BIG(*) AS accepted
           FROM fact.Loans GROUP BY Loan_Amount_Band_Key) a ON a.k = b.Band_Key
LEFT JOIN (SELECT Loan_Amount_Band_Key AS k, SUM(CAST(Rejected_Count AS BIGINT)) AS rejected
           FROM fact.Rejected_Monthly GROUP BY Loan_Amount_Band_Key) r ON r.k = b.Band_Key
ORDER BY b.Band_Key;


-- D2. By state (all years; state approval is confounded by each state's credit mix)
SELECT g.State_Code, a.accepted, r.rejected,
       CAST(100.0 * a.accepted / NULLIF(a.accepted + r.rejected, 0) AS DECIMAL(5,2)) AS approval_rate_pct
FROM dim.Geography g
LEFT JOIN (SELECT Geography_Key AS k, COUNT_BIG(*) AS accepted
           FROM fact.Loans GROUP BY Geography_Key) a ON a.k = g.Geography_Key
LEFT JOIN (SELECT Geography_Key AS k, SUM(CAST(Rejected_Count AS BIGINT)) AS rejected
           FROM fact.Rejected_Monthly GROUP BY Geography_Key) r ON r.k = g.Geography_Key
ORDER BY approval_rate_pct DESC;


-- D3. DTI band by era: does the pattern hold in every period, or is it a year-mix effect?
WITH a AS (
  SELECT e.era, f.DTI_Band_Key AS band, COUNT_BIG(*) AS accepted
  FROM fact.Loans f JOIN dim.Date d ON d.Date_Key = f.Issue_Date_Key
  CROSS APPLY (SELECT CASE WHEN d.[Year] <= 2012 THEN '2007-2012' WHEN d.[Year] <= 2014 THEN '2013-2014'
                           WHEN d.[Year] <= 2016 THEN '2015-2016' ELSE '2017-2018' END AS era) e
  GROUP BY e.era, f.DTI_Band_Key),
r AS (
  SELECT e.era, m.DTI_Band_Key AS band, SUM(CAST(m.Rejected_Count AS BIGINT)) AS rejected
  FROM fact.Rejected_Monthly m JOIN dim.Date d ON d.Date_Key = m.Month_Date_Key
  CROSS APPLY (SELECT CASE WHEN d.[Year] <= 2012 THEN '2007-2012' WHEN d.[Year] <= 2014 THEN '2013-2014'
                           WHEN d.[Year] <= 2016 THEN '2015-2016' ELSE '2017-2018' END AS era) e
  GROUP BY e.era, m.DTI_Band_Key)
SELECT a.era, b.Band_Label, a.accepted, r.rejected,
       CAST(100.0 * a.accepted / NULLIF(a.accepted + r.rejected, 0) AS DECIMAL(5,2)) AS approval_rate_pct
FROM a JOIN r ON r.era = a.era AND r.band = a.band
JOIN ref.DTI_Band b ON b.Band_Key = a.band
ORDER BY a.era, a.band;


-- D4. Diagnostic for the low approval rate in the 0-9.99 band: rejected rows with DTI = 0, by year
SELECT d.[Year] AS app_year,
       COUNT_BIG(*) AS rejected_dti_under_10,
       SUM(CASE WHEN f.DTI = 0 THEN 1 ELSE 0 END)             AS dti_exactly_0,
       SUM(CASE WHEN f.DTI > 0 AND f.DTI < 10 THEN 1 ELSE 0 END) AS dti_above0_below10
FROM fact.Rejected_Applications f JOIN dim.Date d ON d.Date_Key = f.Application_Date_Key
WHERE f.DTI >= 0 AND f.DTI < 10
GROUP BY d.[Year] ORDER BY d.[Year];


-- D5. Same question on the accepted side: how many accepted loans have DTI = 0?
SELECT SUM(CASE WHEN DTI = 0 THEN 1 ELSE 0 END) AS accepted_dti_exactly_0,
       SUM(CASE WHEN DTI > 0 AND DTI < 10 THEN 1 ELSE 0 END) AS accepted_dti_above0_below10
FROM fact.Loans;
GO

/* =================================================================================================================================================================================
   E. DASHBOARD FILTER CHECK --> Power BI with slicers Grade = A and State = CA must show these numbers.
   ================================================================================================================================================================================= */
SELECT COUNT_BIG(*) AS loans, SUM(f.Funded_Amount) AS funded, SUM(f.Total_Payment) AS received
FROM fact.Loans f
JOIN dim.Grade g      ON g.Grade_Key = f.Grade_Key
JOIN dim.Geography geo ON geo.Geography_Key = f.Geography_Key
WHERE g.Grade = 'A' AND geo.State_Code = 'CA';