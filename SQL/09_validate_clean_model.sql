-- 09_validate_clean_model.sql 
USE Syntecxhub_Bank_Loan_Analysis;
GO

DROP TABLE IF EXISTS audit.Validation_Results;
CREATE TABLE audit.Validation_Results (
    Check_No   INT IDENTITY(1,1) PRIMARY KEY,
    Area       VARCHAR(30)  NOT NULL,
    Check_Name VARCHAR(150) NOT NULL,
    Expected   DECIMAL(24,4) NULL,
    Actual     DECIMAL(24,4) NULL,
    Tolerance  DECIMAL(9,4)  NOT NULL DEFAULT 0,
    Status AS (CASE WHEN Actual IS NOT NULL AND Expected IS NOT NULL
                     AND ABS(Actual - Expected) <= Tolerance THEN 'PASS' ELSE 'FAIL' END)
);
GO

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 1. Staging vs source files  */
INSERT INTO audit.Validation_Results (Area, Check_Name, Expected, Actual, Tolerance)

SELECT 'Staging', 'Accepted_Raw rows = file lines minus header', 2260701, COUNT_BIG(*), 0 FROM stg.Accepted_Raw
UNION ALL

SELECT 'Staging', 'Rejected_Raw rows = file lines minus header', 27648741, COUNT_BIG(*), 0 FROM stg.Rejected_Raw
UNION ALL

SELECT 'Staging', 'Non-loan footer rows in accepted file', 33, COUNT_BIG(*), 0
FROM stg.Accepted_Raw WHERE TRY_CAST(id AS BIGINT) IS NULL;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 2. fact.Loans reconciliation to staging  */
INSERT INTO audit.Validation_Results (Area, Check_Name, Expected, Actual, Tolerance)

SELECT 'fact.Loans', 'Rows = valid staging loans', (SELECT COUNT_BIG(*) FROM audit.v_Accepted_Loans), COUNT_BIG(*), 0
FROM fact.Loans
UNION ALL

SELECT 'fact.Loans', 'Distinct Loan_ID = 2,260,668', 2260668, COUNT_BIG(DISTINCT Loan_ID), 0 FROM fact.Loans
UNION ALL

SELECT 'fact.Loans', 'Funded amount = staging (rounded) total',
       (SELECT SUM(ROUND(TRY_CAST(funded_amnt AS FLOAT),2)) FROM audit.v_Accepted_Loans), SUM(Funded_Amount), 0.01
FROM fact.Loans
UNION ALL

SELECT 'fact.Loans', 'Amount received = staging (rounded) total',
       (SELECT SUM(ROUND(TRY_CAST(total_pymnt AS FLOAT),2)) FROM audit.v_Accepted_Loans), SUM(Total_Payment), 0.01
FROM fact.Loans
UNION ALL

SELECT 'fact.Loans', 'Funded amount = source-file footer total (policy code 1)',
       (SELECT SUM(TRY_CAST(LTRIM(SUBSTRING(id, CHARINDEX(':', id) + 1, 50)) AS BIGINT))
        FROM stg.Accepted_Raw WHERE id LIKE 'Total amount funded in policy code 1:%'),
       SUM(Funded_Amount), 0.01
FROM fact.Loans
UNION ALL

SELECT 'fact.Loans', 'Loans where payment = principal + interest + late fee + recoveries', 2260668,
       SUM(CASE WHEN ABS(Total_Payment - (Total_Rec_Principal + Total_Rec_Interest + Total_Rec_Late_Fee + Recoveries)) <= 0.05
                THEN 1 ELSE 0 END), 0
FROM fact.Loans;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 3. Business rules */
INSERT INTO audit.Validation_Results (Area, Check_Name, Expected, Actual, Tolerance)

SELECT 'Business rules', 'Good loans', 1957056, COUNT_BIG(*), 0
FROM fact.Loans f JOIN dim.Loan_Status ls ON ls.Loan_Status_Key = f.Loan_Status_Key WHERE ls.Loan_Class = 'Good'
UNION ALL

SELECT 'Business rules', 'At Risk loans', 34252, COUNT_BIG(*), 0
FROM fact.Loans f JOIN dim.Loan_Status ls ON ls.Loan_Status_Key = f.Loan_Status_Key WHERE ls.Loan_Class = 'At Risk'
UNION ALL

SELECT 'Business rules', 'Bad loans', 269360, COUNT_BIG(*), 0
FROM fact.Loans f JOIN dim.Loan_Status ls ON ls.Loan_Status_Key = f.Loan_Status_Key WHERE ls.Loan_Class = 'Bad'
UNION ALL

SELECT 'Business rules', 'Matured loans (snapshot 2019-03-01)', 785915, SUM(CAST(Is_Matured AS INT)), 0 FROM fact.Loans
UNION ALL

SELECT 'Business rules', 'Matured charged-off loans', 118371, COUNT_BIG(*), 0
FROM fact.Loans f JOIN dim.Loan_Status ls ON ls.Loan_Status_Key = f.Loan_Status_Key
WHERE f.Is_Matured = 1 AND ls.Is_Charged_Off = 1;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 4. Cleaning rules and flags on fact.Loans  */
INSERT INTO audit.Validation_Results (Area, Check_Name, Expected, Actual, Tolerance)

SELECT 'fact.Loans', 'Annual_Income NULL (zero or blank in source)', 1671, SUM(CASE WHEN Annual_Income IS NULL THEN 1 ELSE 0 END), 0 FROM fact.Loans
UNION ALL

SELECT 'fact.Loans', 'DTI NULL (blank, negative or >= 999)', 1848, SUM(CASE WHEN DTI IS NULL THEN 1 ELSE 0 END), 0 FROM fact.Loans
UNION ALL

SELECT 'fact.Loans', 'Income outliers flagged (> 1,000,000)', 583, SUM(CAST(Is_Income_Outlier AS INT)), 0 FROM fact.Loans
UNION ALL

SELECT 'fact.Loans', 'Possible duplicates flagged', 2, SUM(CAST(Is_Possible_Duplicate AS INT)), 0 FROM fact.Loans
UNION ALL

SELECT 'fact.Loans', 'First issue month key (June 2007)', 20070601, MIN(Issue_Date_Key), 0 FROM fact.Loans
UNION ALL

SELECT 'fact.Loans', 'Last issue month key (December 2018)', 20181201, MAX(Issue_Date_Key), 0 FROM fact.Loans;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/*  5. Rejected applications */
INSERT INTO audit.Validation_Results (Area, Check_Name, Expected, Actual, Tolerance)

SELECT 'Rejected', 'fact.Rejected_Applications rows', 27648741, COUNT_BIG(*), 0 FROM fact.Rejected_Applications
UNION ALL

SELECT 'Rejected', 'Amount_Requested NULL (was 0)', 1288, SUM(CASE WHEN Amount_Requested IS NULL THEN 1 ELSE 0 END), 0 FROM fact.Rejected_Applications
UNION ALL

SELECT 'Rejected', 'DTI NULL (negative or >= 999)', 1372321, SUM(CASE WHEN DTI IS NULL THEN 1 ELSE 0 END), 0 FROM fact.Rejected_Applications
UNION ALL

SELECT 'Rejected', 'Rows with DTI exactly 0', 1045102, SUM(CASE WHEN DTI = 0 THEN 1 ELSE 0 END), 0 FROM fact.Rejected_Applications
UNION ALL

SELECT 'Rejected', 'Monthly aggregate: total count = detail rows', 27648741, SUM(CAST(Rejected_Count AS BIGINT)), 0 FROM fact.Rejected_Monthly
UNION ALL

SELECT 'Rejected', 'Monthly aggregate: amount = detail amount',
       (SELECT SUM(Amount_Requested) FROM fact.Rejected_Applications), SUM(Amount_Requested_Sum), 0.01
FROM fact.Rejected_Monthly
UNION ALL

SELECT 'Rejected', 'Monthly aggregate rows', 778276, COUNT_BIG(*), 0 FROM fact.Rejected_Monthly;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 6. Band consistency */
INSERT INTO audit.Validation_Results (Area, Check_Name, Expected, Actual, Tolerance)

SELECT 'Consistency', 'fact.Loans rows whose DTI band disagrees with DTI', 0, COUNT_BIG(*), 0
FROM fact.Loans WHERE (DTI = 0 AND DTI_Band_Key <> 7) OR (DTI > 0 AND DTI_Band_Key = 7)
UNION ALL

SELECT 'Consistency', 'fact.Rejected_Applications rows whose DTI band disagrees with DTI', 0, COUNT_BIG(*), 0
FROM fact.Rejected_Applications WHERE (DTI = 0 AND DTI_Band_Key <> 7) OR (DTI > 0 AND DTI_Band_Key = 7);

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 7. Dimension row counts  */
INSERT INTO audit.Validation_Results (Area, Check_Name, Expected, Actual, Tolerance)

SELECT 'Dimensions', 'dim.Loan_Status rows',        7,    COUNT(*), 0 FROM dim.Loan_Status
UNION ALL SELECT 'Dimensions', 'dim.Grade rows',               35,   COUNT(*), 0 FROM dim.Grade
UNION ALL SELECT 'Dimensions', 'dim.Purpose rows',             14,   COUNT(*), 0 FROM dim.Purpose
UNION ALL SELECT 'Dimensions', 'dim.Home_Ownership rows',      4,    COUNT(*), 0 FROM dim.Home_Ownership
UNION ALL SELECT 'Dimensions', 'dim.Term rows',                2,    COUNT(*), 0 FROM dim.Term
UNION ALL SELECT 'Dimensions', 'dim.Verification_Status rows', 3,    COUNT(*), 0 FROM dim.Verification_Status
UNION ALL SELECT 'Dimensions', 'dim.Application_Type rows',    2,    COUNT(*), 0 FROM dim.Application_Type
UNION ALL SELECT 'Dimensions', 'dim.Employment_Length rows',   12,   COUNT(*), 0 FROM dim.Employment_Length
UNION ALL SELECT 'Dimensions', 'dim.Geography rows',           52,   COUNT(*), 0 FROM dim.Geography
UNION ALL SELECT 'Dimensions', 'dim.Date rows',                4748, COUNT(*), 0 FROM dim.Date
UNION ALL SELECT 'Dimensions', 'ref.DTI_Band rows',            7,    COUNT(*), 0 FROM ref.DTI_Band;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 8. Foreign keys  */
INSERT INTO audit.Validation_Results (Area, Check_Name, Expected, Actual, Tolerance)

SELECT 'Constraints', 'Foreign keys on fact tables (14 + 6 + 5)', 25, COUNT(*), 0
FROM sys.foreign_keys fk JOIN sys.tables t ON t.object_id = fk.parent_object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id WHERE s.name = 'fact'
UNION ALL

SELECT 'Constraints', 'Foreign keys disabled or not trusted', 0, COUNT(*), 0
FROM sys.foreign_keys fk JOIN sys.tables t ON t.object_id = fk.parent_object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = 'fact' AND (fk.is_not_trusted = 1 OR fk.is_disabled = 1);

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 9. Approval rate, reference years (2 checks) */
INSERT INTO audit.Validation_Results (Area, Check_Name, Expected, Actual, Tolerance)

SELECT 'Approval', 'Approval rate 2018 (%)', 4.96, CAST(100.0 * a.n / (a.n + r.n) AS DECIMAL(9,2)), 0.01
FROM (SELECT COUNT_BIG(*) AS n FROM fact.Loans f JOIN dim.Date d ON d.Date_Key = f.Issue_Date_Key WHERE d.[Year] = 2018) a
CROSS JOIN (SELECT SUM(CAST(m.Rejected_Count AS BIGINT)) AS n FROM fact.Rejected_Monthly m
            JOIN dim.Date d ON d.Date_Key = m.Month_Date_Key WHERE d.[Year] = 2018) r
UNION ALL

SELECT 'Approval', 'Approval rate 2013 (%)', 15.05, CAST(100.0 * a.n / (a.n + r.n) AS DECIMAL(9,2)), 0.01
FROM (SELECT COUNT_BIG(*) AS n FROM fact.Loans f JOIN dim.Date d ON d.Date_Key = f.Issue_Date_Key WHERE d.[Year] = 2013) a
CROSS JOIN (SELECT SUM(CAST(m.Rejected_Count AS BIGINT)) AS n FROM fact.Rejected_Monthly m
            JOIN dim.Date d ON d.Date_Key = m.Month_Date_Key WHERE d.[Year] = 2013) r;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 10. Power BI filter test values: Grade A + California */
INSERT INTO audit.Validation_Results (Area, Check_Name, Expected, Actual, Tolerance)

SELECT 'Filter test', 'Grade A + CA: loans', 62451, COUNT_BIG(*), 0
FROM fact.Loans f JOIN dim.Grade g ON g.Grade_Key = f.Grade_Key
JOIN dim.Geography geo ON geo.Geography_Key = f.Geography_Key WHERE g.Grade = 'A' AND geo.State_Code = 'CA'
UNION ALL

SELECT 'Filter test', 'Grade A + CA: funded amount', 940682700.00, SUM(f.Funded_Amount), 0.01
FROM fact.Loans f JOIN dim.Grade g ON g.Grade_Key = f.Grade_Key
JOIN dim.Geography geo ON geo.Geography_Key = f.Geography_Key WHERE g.Grade = 'A' AND geo.State_Code = 'CA'
UNION ALL

SELECT 'Filter test', 'Grade A + CA: amount received', 704839842.26, SUM(f.Total_Payment), 0.01
FROM fact.Loans f JOIN dim.Grade g ON g.Grade_Key = f.Grade_Key
JOIN dim.Geography geo ON geo.Geography_Key = f.Geography_Key WHERE g.Grade = 'A' AND geo.State_Code = 'CA';

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 11. Capacity: PASS if data files <= 51,200 MB */
INSERT INTO audit.Validation_Results (Area, Check_Name, Expected, Actual, Tolerance)

SELECT 'Capacity', 'Data file size in MB (PASS if <= 51,200)', 25600, SUM(CAST(size AS BIGINT)) * 8 / 1024.0, 25600
FROM sys.database_files WHERE type = 0;
GO

/* ================== RESULTS ================== */
SELECT Status, COUNT(*) AS checks FROM audit.Validation_Results GROUP BY Status;     -- expect 48 
SELECT * FROM audit.Validation_Results WHERE Status = 'FAIL' ORDER BY Check_No;      -- expect no rows
SELECT Check_No, Area, Check_Name, Expected, Actual, Status FROM audit.Validation_Results ORDER BY Check_No;