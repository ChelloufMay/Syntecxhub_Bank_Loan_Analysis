-- 05_create_clean_dimensions.sql
USE Syntecxhub_Bank_Loan_Analysis;
GO

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* dim.Loan_Status (clean status grain, from the business-rule map) */
DROP TABLE IF EXISTS dim.Loan_Status;
CREATE TABLE dim.Loan_Status (
    Loan_Status_Key INT IDENTITY(1,1) PRIMARY KEY,
    Loan_Status     VARCHAR(50) NOT NULL UNIQUE,
    Loan_Class      VARCHAR(10) NOT NULL,
    Class_Sort      TINYINT     NOT NULL,
    Is_Resolved     BIT         NOT NULL,
    Is_Charged_Off  BIT         NOT NULL
);
INSERT INTO dim.Loan_Status (Loan_Status, Loan_Class, Class_Sort, Is_Resolved, Is_Charged_Off)
SELECT DISTINCT Loan_Status_Clean, Loan_Class, Class_Sort, Is_Resolved, Is_Charged_Off
FROM ref.Loan_Status_Map
ORDER BY Class_Sort, Loan_Status_Clean;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* dim.Grade (one row per sub-grade, grade is the parent level) */
DROP TABLE IF EXISTS dim.Grade;
CREATE TABLE dim.Grade (
    Grade_Key  INT IDENTITY(1,1) PRIMARY KEY,
    Sub_Grade  CHAR(2) NOT NULL UNIQUE,
    Grade      CHAR(1) NOT NULL
);
INSERT INTO dim.Grade (Sub_Grade, Grade)
SELECT DISTINCT LTRIM(RTRIM(sub_grade)), LEFT(LTRIM(RTRIM(sub_grade)), 1)
FROM audit.v_Accepted_Loans
ORDER BY 1;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* dim.Purpose */
DROP TABLE IF EXISTS dim.Purpose;
CREATE TABLE dim.Purpose (
    Purpose_Key   INT IDENTITY(1,1) PRIMARY KEY,
    Purpose_Raw   VARCHAR(50) NOT NULL UNIQUE,
    Purpose_Label VARCHAR(50) NOT NULL
);
INSERT INTO dim.Purpose (Purpose_Raw, Purpose_Label)
SELECT DISTINCT p, UPPER(LEFT(REPLACE(p,'_',' '),1)) + SUBSTRING(REPLACE(p,'_',' '),2,100)
FROM (SELECT LTRIM(RTRIM(purpose)) AS p FROM audit.v_Accepted_Loans) x
ORDER BY 1;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* dim.Home_Ownership (ANY / OTHER / NONE merged into Other) */
DROP TABLE IF EXISTS ref.Home_Ownership_Map;
CREATE TABLE ref.Home_Ownership_Map (
    Home_Ownership_Raw   VARCHAR(20) NOT NULL PRIMARY KEY,
    Home_Ownership_Clean VARCHAR(20) NOT NULL
);
INSERT INTO ref.Home_Ownership_Map VALUES
 ('MORTGAGE','Mortgage'),('RENT','Rent'),('OWN','Own'),
 ('ANY','Other'),('OTHER','Other'),('NONE','Other');

DROP TABLE IF EXISTS dim.Home_Ownership;
CREATE TABLE dim.Home_Ownership (
    Home_Ownership_Key INT IDENTITY(1,1) PRIMARY KEY,
    Home_Ownership     VARCHAR(20) NOT NULL UNIQUE
);
INSERT INTO dim.Home_Ownership (Home_Ownership)
SELECT DISTINCT Home_Ownership_Clean FROM ref.Home_Ownership_Map ORDER BY 1;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* dim.Term */
DROP TABLE IF EXISTS dim.Term;
CREATE TABLE dim.Term (
    Term_Key    INT IDENTITY(1,1) PRIMARY KEY,
    Term_Months TINYINT     NOT NULL UNIQUE,
    Term_Label  VARCHAR(20) NOT NULL
);
INSERT INTO dim.Term (Term_Months, Term_Label)
SELECT DISTINCT CAST(LEFT(LTRIM(term),2) AS INT), LTRIM(RTRIM(term))
FROM audit.v_Accepted_Loans
ORDER BY 1;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* dim.Verification_Status */
DROP TABLE IF EXISTS dim.Verification_Status;
CREATE TABLE dim.Verification_Status (
    Verification_Key    INT IDENTITY(1,1) PRIMARY KEY,
    Verification_Status VARCHAR(30) NOT NULL UNIQUE
);
INSERT INTO dim.Verification_Status (Verification_Status)
SELECT DISTINCT LTRIM(RTRIM(verification_status))
FROM audit.v_Accepted_Loans
ORDER BY 1;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* dim.Application_Type */
DROP TABLE IF EXISTS dim.Application_Type;
CREATE TABLE dim.Application_Type (
    Application_Type_Key INT IDENTITY(1,1) PRIMARY KEY,
    Application_Type     VARCHAR(30) NOT NULL UNIQUE
);
INSERT INTO dim.Application_Type (Application_Type)
SELECT DISTINCT LTRIM(RTRIM(application_type))
FROM audit.v_Accepted_Loans
ORDER BY 1;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* dim.Employment_Length (blank -> Unknown; sorted by years) */
DROP TABLE IF EXISTS dim.Employment_Length;
CREATE TABLE dim.Employment_Length (
    Emp_Length_Key   INT IDENTITY(1,1) PRIMARY KEY,
    Emp_Length_Label VARCHAR(20) NOT NULL UNIQUE,
    Emp_Length_Sort  TINYINT     NOT NULL
);
INSERT INTO dim.Employment_Length (Emp_Length_Label, Emp_Length_Sort) VALUES
 ('< 1 year',0),('1 year',1),('2 years',2),('3 years',3),('4 years',4),('5 years',5),
 ('6 years',6),('7 years',7),('8 years',8),('9 years',9),('10+ years',10),('Unknown',99);

 /*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/*  dim.Geography (US states + DC + Unknown)  */
DROP TABLE IF EXISTS dim.Geography;
CREATE TABLE dim.Geography (
    Geography_Key INT IDENTITY(1,1) PRIMARY KEY,
    State_Code    CHAR(2)     NOT NULL UNIQUE,
    State_Name    VARCHAR(30) NOT NULL
);
INSERT INTO dim.Geography (State_Code, State_Name) VALUES
 ('AL','Alabama'),('AK','Alaska'),('AZ','Arizona'),('AR','Arkansas'),('CA','California'),
 ('CO','Colorado'),('CT','Connecticut'),('DE','Delaware'),('DC','District of Columbia'),
 ('FL','Florida'),('GA','Georgia'),('HI','Hawaii'),('ID','Idaho'),('IL','Illinois'),
 ('IN','Indiana'),('IA','Iowa'),('KS','Kansas'),('KY','Kentucky'),('LA','Louisiana'),
 ('ME','Maine'),('MD','Maryland'),('MA','Massachusetts'),('MI','Michigan'),('MN','Minnesota'),
 ('MS','Mississippi'),('MO','Missouri'),('MT','Montana'),('NE','Nebraska'),('NV','Nevada'),
 ('NH','New Hampshire'),('NJ','New Jersey'),('NM','New Mexico'),('NY','New York'),
 ('NC','North Carolina'),('ND','North Dakota'),('OH','Ohio'),('OK','Oklahoma'),('OR','Oregon'),
 ('PA','Pennsylvania'),('RI','Rhode Island'),('SC','South Carolina'),('SD','South Dakota'),
 ('TN','Tennessee'),('TX','Texas'),('UT','Utah'),('VT','Vermont'),('VA','Virginia'),
 ('WA','Washington'),('WV','West Virginia'),('WI','Wisconsin'),('WY','Wyoming'),
 ('XX','Unknown');
GO

/* ======================================================================== VALIDATION ======================================================================== */

-- D1. Row counts (expected: 7, 35, 14, 4, 2, 3, 2, 12, 52)
SELECT 'dim.Loan_Status' AS dimension, COUNT(*) AS row_count, 7  AS expected FROM dim.Loan_Status
UNION ALL SELECT 'dim.Grade',               COUNT(*), 35 FROM dim.Grade
UNION ALL SELECT 'dim.Purpose',             COUNT(*), 14 FROM dim.Purpose
UNION ALL SELECT 'dim.Home_Ownership',      COUNT(*), 4  FROM dim.Home_Ownership
UNION ALL SELECT 'dim.Term',                COUNT(*), 2  FROM dim.Term
UNION ALL SELECT 'dim.Verification_Status', COUNT(*), 3  FROM dim.Verification_Status
UNION ALL SELECT 'dim.Application_Type',    COUNT(*), 2  FROM dim.Application_Type
UNION ALL SELECT 'dim.Employment_Length',   COUNT(*), 12 FROM dim.Employment_Length
UNION ALL SELECT 'dim.Geography',           COUNT(*), 52 FROM dim.Geography;

-- D2. Coverage: values in the data with no dimension match (all must be 0)
SELECT
 (SELECT COUNT_BIG(*) FROM audit.v_Accepted_Loans a
    LEFT JOIN dim.Grade d ON d.Sub_Grade = LTRIM(RTRIM(a.sub_grade))
    WHERE d.Grade_Key IS NULL)                                   AS grade_unmatched,
 (SELECT COUNT_BIG(*) FROM audit.v_Accepted_Loans a
    LEFT JOIN dim.Purpose d ON d.Purpose_Raw = LTRIM(RTRIM(a.purpose))
    WHERE d.Purpose_Key IS NULL)                                 AS purpose_unmatched,
 (SELECT COUNT_BIG(*) FROM audit.v_Accepted_Loans a
    LEFT JOIN ref.Home_Ownership_Map m ON m.Home_Ownership_Raw = LTRIM(RTRIM(a.home_ownership))
    WHERE m.Home_Ownership_Raw IS NULL)                          AS home_unmatched,
 (SELECT COUNT_BIG(*) FROM audit.v_Accepted_Loans a
    LEFT JOIN dim.Term d ON d.Term_Months = CAST(LEFT(LTRIM(a.term),2) AS INT)
    WHERE d.Term_Key IS NULL)                                    AS term_unmatched,
 (SELECT COUNT_BIG(*) FROM audit.v_Accepted_Loans a
    LEFT JOIN dim.Verification_Status d ON d.Verification_Status = LTRIM(RTRIM(a.verification_status))
    WHERE d.Verification_Key IS NULL)                            AS verif_unmatched,
 (SELECT COUNT_BIG(*) FROM audit.v_Accepted_Loans a
    LEFT JOIN dim.Application_Type d ON d.Application_Type = LTRIM(RTRIM(a.application_type))
    WHERE d.Application_Type_Key IS NULL)                        AS apptype_unmatched,
 (SELECT COUNT_BIG(*) FROM audit.v_Accepted_Loans a
    LEFT JOIN dim.Employment_Length d
      ON d.Emp_Length_Label = COALESCE(NULLIF(LTRIM(RTRIM(a.emp_length)),''),'Unknown')
    WHERE d.Emp_Length_Key IS NULL)                              AS emp_unmatched_accepted,
 (SELECT COUNT_BIG(*) FROM audit.v_Accepted_Loans a
    LEFT JOIN dim.Geography d ON d.State_Code = LTRIM(RTRIM(a.addr_state))
    WHERE d.Geography_Key IS NULL)                               AS state_unmatched_accepted;

-- D3. Same coverage check on the rejected file (27.6M rows: allow a few minutes)
SELECT
 (SELECT COUNT_BIG(*) FROM stg.Rejected_Raw r
    LEFT JOIN dim.Employment_Length d
      ON d.Emp_Length_Label = COALESCE(NULLIF(LTRIM(RTRIM(r.Employment_Length)),''),'Unknown')
    WHERE d.Emp_Length_Key IS NULL)                              AS emp_unmatched_rejected,
 (SELECT COUNT_BIG(*) FROM stg.Rejected_Raw r
    LEFT JOIN dim.Geography d
      ON d.State_Code = COALESCE(NULLIF(LTRIM(RTRIM(r.State)),''),'XX')
    WHERE d.Geography_Key IS NULL)                               AS state_unmatched_rejected;

-- D4. Look at the results
SELECT * FROM dim.Loan_Status ORDER BY Class_Sort, Loan_Status_Key;
SELECT * FROM dim.Purpose ORDER BY Purpose_Key;
SELECT * FROM dim.Home_Ownership;
SELECT * FROM dim.Term;