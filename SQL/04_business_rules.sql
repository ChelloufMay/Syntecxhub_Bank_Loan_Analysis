-- 04_business_rules.sql
USE Syntecxhub_Bank_Loan_Analysis;
GO
IF SCHEMA_ID('ref') IS NULL EXEC('CREATE SCHEMA ref');
GO

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* ---------- Config ---------- */
DROP TABLE IF EXISTS ref.Config;
CREATE TABLE ref.Config (
    Config_Key   VARCHAR(50)  NOT NULL PRIMARY KEY,
    Config_Value VARCHAR(100) NOT NULL,
    Description  VARCHAR(300) NULL
);
INSERT INTO ref.Config
SELECT 'Snapshot_Date',
       CONVERT(VARCHAR(10), MAX(TRY_CONVERT(date,'01 '+REPLACE(last_pymnt_d,'-',' '),106)), 23),
       'Latest last_pymnt_d in the data (extraction date, month precision); used for loan maturity'
FROM audit.v_Accepted_Loans;
INSERT INTO ref.Config VALUES
 ('DTI_Invalid_From',  '999',  'DTI below 0 or at/above this value is a placeholder, set to NULL'),
 ('Income_Outlier_Min','1000000','Annual income above this is flagged, not removed'),
 ('Risk_Score_Min',    '300',  'Risk_Score below this is invalid, set to NULL'),
 ('Risk_Score_Max',    '850',  'Risk_Score above this is invalid, set to NULL');
GO

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* ---------- Loan status -> class ---------- */
DROP TABLE IF EXISTS ref.Loan_Status_Map;
CREATE TABLE ref.Loan_Status_Map (
    Loan_Status_Raw         VARCHAR(100) NOT NULL PRIMARY KEY,
    Loan_Status_Clean       VARCHAR(50)  NOT NULL,
    Loan_Class              VARCHAR(10)  NOT NULL,   -- Good / At Risk / Bad
    Class_Sort              TINYINT      NOT NULL,
    Is_Resolved             BIT          NOT NULL,   -- Fully Paid or Charged Off
    Is_Charged_Off          BIT          NOT NULL,
    Is_Legacy_Policy_Status BIT          NOT NULL,
    Rule_Reason             VARCHAR(300) NOT NULL
);
INSERT INTO ref.Loan_Status_Map VALUES
 ('Fully Paid', 'Fully Paid', 'Good', 1, 1,0,0, 'Loan fully repaid'),
 ('Does not meet the credit policy. Status:Fully Paid', 'Fully Paid', 'Good', 1, 1,0,1, 'Legacy label; fully repaid'),
 ('Current', 'Current', 'Good', 1, 0,0,0, 'Ongoing, payments on schedule'),
 ('In Grace Period', 'In Grace Period', 'At Risk', 2, 0,0,0, 'Payment missed, inside grace period; outcome unknown'),
 ('Late (16-30 days)', 'Late (16-30 days)', 'At Risk', 2, 0,0,0, 'Delinquent; outcome unknown'),
 ('Late (31-120 days)', 'Late (31-120 days)', 'At Risk', 2, 0,0,0, 'Seriously delinquent; outcome unknown'),
 ('Default', 'Default', 'Bad', 3, 0,0,0, 'More than 120 days late; treated as bad, not yet charged off'),
 ('Charged Off', 'Charged Off', 'Bad', 3, 1,1,0, 'Written off by the lender'),
 ('Does not meet the credit policy. Status:Charged Off', 'Charged Off', 'Bad', 3, 1,1,1, 'Legacy label; charged off');
GO

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* ---------- Band tables (Lower_Bound <= value < Upper_Bound) ---------- */
DROP TABLE IF EXISTS ref.DTI_Band;
CREATE TABLE ref.DTI_Band (Band_Key TINYINT PRIMARY KEY, Band_Label VARCHAR(20) NOT NULL,
                           Lower_Bound DECIMAL(18,2) NULL, Upper_Bound DECIMAL(18,2) NULL);
INSERT INTO ref.DTI_Band VALUES
 (1,'0-9.99',0,10),(2,'10-19.99',10,20),(3,'20-29.99',20,30),(4,'30-39.99',30,40),
 (5,'40+',40,999),(6,'Unknown',NULL,NULL);

DROP TABLE IF EXISTS ref.Income_Band;
CREATE TABLE ref.Income_Band (Band_Key TINYINT PRIMARY KEY, Band_Label VARCHAR(20) NOT NULL,
                              Lower_Bound DECIMAL(18,2) NULL, Upper_Bound DECIMAL(18,2) NULL);
INSERT INTO ref.Income_Band VALUES
 (1,'Under 30K',0.01,30000),(2,'30K-49K',30000,50000),(3,'50K-74K',50000,75000),
 (4,'75K-99K',75000,100000),(5,'100K-149K',100000,150000),(6,'150K+',150000,999999999999),
 (7,'Unknown',NULL,NULL);

DROP TABLE IF EXISTS ref.Loan_Amount_Band;
CREATE TABLE ref.Loan_Amount_Band (Band_Key TINYINT PRIMARY KEY, Band_Label VARCHAR(20) NOT NULL,
                                   Lower_Bound DECIMAL(18,2) NULL, Upper_Bound DECIMAL(18,2) NULL);
INSERT INTO ref.Loan_Amount_Band VALUES
 (1,'Under 5K',0.01,5000),(2,'5K-9.99K',5000,10000),(3,'10K-14.99K',10000,15000),
 (4,'15K-19.99K',15000,20000),(5,'20K-29.99K',20000,30000),(6,'30K+',30000,999999999999),
 (7,'Unknown',NULL,NULL);

DROP TABLE IF EXISTS ref.Risk_Band;
CREATE TABLE ref.Risk_Band (Band_Key TINYINT PRIMARY KEY, Band_Label VARCHAR(20) NOT NULL,
                            Lower_Bound DECIMAL(9,2) NULL, Upper_Bound DECIMAL(9,2) NULL);
INSERT INTO ref.Risk_Band VALUES
 (1,'Under 600',300,600),(2,'600-649',600,650),(3,'650-699',650,700),
 (4,'700-749',700,750),(5,'750+',750,851),(6,'Unknown',NULL,NULL);
GO

/* ======================================================================== VALIDATION OF THE RULES ======================================================================== */

-- V0. Snapshot date and config
SELECT * FROM ref.Config;

-- V1. Every loan status is mapped (unmapped_loans must be 0)
SELECT COUNT_BIG(*) AS unmapped_loans
FROM audit.v_Accepted_Loans a
LEFT JOIN ref.Loan_Status_Map m ON m.Loan_Status_Raw = a.loan_status
WHERE m.Loan_Status_Raw IS NULL;

-- V2. Class split (expect Good 1,957,056 / At Risk 34,252 / Bad 269,360)
SELECT m.Loan_Class, COUNT_BIG(*) AS loans,
       CAST(100.0 * COUNT_BIG(*) / SUM(COUNT_BIG(*)) OVER () AS DECIMAL(5,2)) AS pct
FROM audit.v_Accepted_Loans a
JOIN ref.Loan_Status_Map m ON m.Loan_Status_Raw = a.loan_status
GROUP BY m.Loan_Class, m.Class_Sort ORDER BY m.Class_Sort;

-- V3. Money by class: funded, received, repayment ratio
SELECT m.Loan_Class,
       SUM(TRY_CAST(a.funded_amnt AS DECIMAL(18,2))) AS funded,
       SUM(TRY_CAST(a.total_pymnt AS DECIMAL(18,2))) AS received,
       CAST(SUM(TRY_CAST(a.total_pymnt AS DECIMAL(18,2))) /
            SUM(TRY_CAST(a.funded_amnt AS DECIMAL(18,2))) AS DECIMAL(6,3)) AS repayment_ratio
FROM audit.v_Accepted_Loans a
JOIN ref.Loan_Status_Map m ON m.Loan_Status_Raw = a.loan_status
GROUP BY m.Loan_Class, m.Class_Sort ORDER BY m.Class_Sort;

-- V4. Why maturity matters: three ways to measure charge-off rate by issue year
WITH L AS (
  SELECT YEAR(i.issue_dt) AS issue_year,
         m.Is_Resolved, m.Is_Charged_Off,
         CASE WHEN DATEADD(MONTH, TRY_CAST(LEFT(LTRIM(a.term),2) AS INT), i.issue_dt)
                   <= CAST((SELECT Config_Value FROM ref.Config WHERE Config_Key='Snapshot_Date') AS date)
              THEN 1 ELSE 0 END AS Is_Matured
  FROM audit.v_Accepted_Loans a
  CROSS APPLY (SELECT TRY_CONVERT(date,'01 '+REPLACE(a.issue_d,'-',' '),106) AS issue_dt) i
  JOIN ref.Loan_Status_Map m ON m.Loan_Status_Raw = a.loan_status
)
SELECT issue_year,
       COUNT_BIG(*) AS loans,
       CAST(100.0 * SUM(CAST(Is_Charged_Off AS INT)) / COUNT_BIG(*) AS DECIMAL(5,2)) AS chargeoff_pct_all_loans,
       CAST(100.0 * SUM(CAST(Is_Charged_Off AS INT)) / NULLIF(SUM(CAST(Is_Resolved AS INT)),0) AS DECIMAL(5,2)) AS chargeoff_pct_resolved_only,
       SUM(Is_Matured) AS matured_loans,
       CAST(100.0 * SUM(CASE WHEN Is_Matured = 1 THEN CAST(Is_Charged_Off AS INT) ELSE 0 END)
            / NULLIF(SUM(Is_Matured),0) AS DECIMAL(5,2)) AS chargeoff_pct_matured_only
FROM L GROUP BY issue_year ORDER BY issue_year;