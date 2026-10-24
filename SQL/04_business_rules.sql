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

