-- 10_dashboard_expected_values.sql
USE Syntecxhub_Bank_Loan_Analysis;
GO

-- E1. Matured charge-off by DTI band, current bands (Page 3)
SELECT b.Band_Label, COUNT_BIG(*) AS loans,
       SUM(CAST(f.Is_Matured AS INT)) AS matured_loans,
       CAST(100.0 * SUM(CASE WHEN f.Is_Matured = 1 AND ls.Is_Charged_Off = 1 THEN 1 ELSE 0 END)
            / NULLIF(SUM(CAST(f.Is_Matured AS INT)), 0) AS DECIMAL(5,2)) AS chargeoff_pct_matured
FROM fact.Loans f
JOIN ref.DTI_Band b     ON b.Band_Key = f.DTI_Band_Key
JOIN dim.Loan_Status ls ON ls.Loan_Status_Key = f.Loan_Status_Key
GROUP BY b.Band_Label, b.Sort_Order ORDER BY b.Sort_Order;

-- E2. Status grid with average rate and DTI (Page 1)
SELECT ls.Loan_Status, COUNT_BIG(*) AS loans,
       SUM(f.Funded_Amount) AS funded, SUM(f.Total_Payment) AS received,
       CAST(SUM(f.Total_Payment) / SUM(f.Funded_Amount) AS DECIMAL(6,3)) AS received_to_funded,
       CAST(AVG(f.Interest_Rate) AS DECIMAL(6,2)) AS avg_rate,
       CAST(AVG(f.DTI) AS DECIMAL(6,2)) AS avg_dti
FROM fact.Loans f JOIN dim.Loan_Status ls ON ls.Loan_Status_Key = f.Loan_Status_Key
GROUP BY ls.Loan_Status, ls.Class_Sort, ls.Loan_Status_Key ORDER BY ls.Loan_Status_Key;

-- E3. Approval rate: DTI band x era, current bands (Page 4)
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
SELECT COALESCE(a.era, r.era) AS era, b.Band_Label, ISNULL(a.accepted, 0) AS accepted, ISNULL(r.rejected, 0) AS rejected,
       CAST(100.0 * ISNULL(a.accepted, 0) / (ISNULL(a.accepted, 0) + ISNULL(r.rejected, 0)) AS DECIMAL(5,2)) AS approval_rate_pct
FROM a FULL JOIN r ON a.era = r.era AND a.band = r.band
JOIN ref.DTI_Band b ON b.Band_Key = COALESCE(a.band, r.band)
ORDER BY era, b.Sort_Order;

-- E4. Three loans from the raw file, for the Loan Details page
SELECT f.Loan_ID, d.Year_Month, ls.Loan_Status, g.Sub_Grade, p.Purpose_Label, t.Term_Label,
       geo.State_Code, ho.Home_Ownership, f.Funded_Amount, f.Interest_Rate, f.Installment, f.DTI, f.Total_Payment
FROM fact.Loans f
JOIN dim.Date d             ON d.Date_Key = f.Issue_Date_Key
JOIN dim.Loan_Status ls     ON ls.Loan_Status_Key = f.Loan_Status_Key
JOIN dim.Grade g            ON g.Grade_Key = f.Grade_Key
JOIN dim.Purpose p          ON p.Purpose_Key = f.Purpose_Key
JOIN dim.Term t             ON t.Term_Key = f.Term_Key
JOIN dim.Geography geo      ON geo.Geography_Key = f.Geography_Key
JOIN dim.Home_Ownership ho  ON ho.Home_Ownership_Key = f.Home_Ownership_Key
WHERE f.Loan_ID IN (88985880, 88224441, 88215728);