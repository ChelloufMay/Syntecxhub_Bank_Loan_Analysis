-- 08b_dti_zero_band.sql
USE Syntecxhub_Bank_Loan_Analysis;
GO

-- 1. Sort column 
IF COL_LENGTH('ref.DTI_Band','Sort_Order') IS NULL
    ALTER TABLE ref.DTI_Band ADD Sort_Order TINYINT NULL;
GO

-- 2. Split exactly-zero DTI into its own band
UPDATE ref.DTI_Band SET Band_Label = '0.01-9.99', Lower_Bound = 0.01 WHERE Band_Key = 1;
IF NOT EXISTS (SELECT 1 FROM ref.DTI_Band WHERE Band_Key = 7)
    INSERT INTO ref.DTI_Band (Band_Key, Band_Label, Lower_Bound, Upper_Bound) VALUES (7, 'Zero (0)', 0, 0.01);
UPDATE ref.DTI_Band
SET Sort_Order = CASE Band_Key WHEN 7 THEN 1 WHEN 1 THEN 2 WHEN 2 THEN 3 WHEN 3 THEN 4
                               WHEN 4 THEN 5 WHEN 5 THEN 6 WHEN 6 THEN 7 END;
GO

-- 3. Re-key rows with DTI = 0 
UPDATE fact.Loans                 SET DTI_Band_Key = 7 WHERE DTI = 0;
UPDATE fact.Rejected_Applications SET DTI_Band_Key = 7 WHERE DTI = 0;     
GO

-- 4. Rebuild the monthly aggregate from the detail table
TRUNCATE TABLE fact.Rejected_Monthly;
INSERT INTO fact.Rejected_Monthly
SELECT dm.Date_Key, f.Geography_Key, f.DTI_Band_Key, f.Loan_Amount_Band_Key, f.Risk_Band_Key,
       CAST(COUNT_BIG(*) AS INT), ISNULL(SUM(f.Amount_Requested), 0)
FROM fact.Rejected_Applications f
JOIN dim.Date d  ON d.Date_Key   = f.Application_Date_Key
JOIN dim.Date dm ON dm.Full_Date = d.Month_Start
GROUP BY dm.Date_Key, f.Geography_Key, f.DTI_Band_Key, f.Loan_Amount_Band_Key, f.Risk_Band_Key;
GO

/* ========================================================================================== VALIDATION ========================================================================================== */

-- Z1. Accepted loans by DTI band (expect Zero (0) = 1,732 and 0.01-9.99 = 406,116; the rest unchanged)
SELECT b.Band_Label, COUNT_BIG(*) AS loans
FROM fact.Loans f JOIN ref.DTI_Band b ON b.Band_Key = f.DTI_Band_Key
GROUP BY b.Band_Label, b.Sort_Order ORDER BY b.Sort_Order;


-- Z2. Aggregate still reconciles (count 27,648,741; amount 363,117,559,783.53; rows slightly above 702,577)
SELECT COUNT_BIG(*) AS aggregate_rows, SUM(CAST(Rejected_Count AS BIGINT)) AS aggregate_count,
       SUM(Amount_Requested_Sum) AS aggregate_amount
FROM fact.Rejected_Monthly;


-- Z3. Approval by DTI band after the split
SELECT b.Band_Label, a.accepted, r.rejected,
       CAST(100.0 * a.accepted / NULLIF(a.accepted + r.rejected, 0) AS DECIMAL(5,2)) AS approval_rate_pct
FROM ref.DTI_Band b
LEFT JOIN (SELECT DTI_Band_Key AS k, COUNT_BIG(*) AS accepted FROM fact.Loans GROUP BY DTI_Band_Key) a ON a.k = b.Band_Key
LEFT JOIN (SELECT DTI_Band_Key AS k, SUM(CAST(Rejected_Count AS BIGINT)) AS rejected
           FROM fact.Rejected_Monthly GROUP BY DTI_Band_Key) r ON r.k = b.Band_Key
ORDER BY b.Sort_Order;


-- Z4. No row's band disagrees with its DTI value (both must be 0)
SELECT
 (SELECT COUNT_BIG(*) FROM fact.Loans WHERE (DTI = 0 AND DTI_Band_Key <> 7) OR (DTI > 0 AND DTI_Band_Key = 7)) AS loans_inconsistent,
 (SELECT COUNT_BIG(*) FROM fact.Rejected_Applications WHERE (DTI = 0 AND DTI_Band_Key <> 7) OR (DTI > 0 AND DTI_Band_Key = 7)) AS rejected_inconsistent;