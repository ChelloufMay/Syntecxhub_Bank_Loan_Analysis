-- 02_staging_basic_validation.sql
USE Syntecxhub_Bank_Loan_Analysis;
GO

/* 1. ROW COUNTS vs EXPECTED: prove the load is complete against the baseline from the file facts. */

SELECT 'Accepted_Raw' AS tbl, COUNT_BIG(*) AS staged_rows, 2260701 AS expected_rows,
       COUNT_BIG(*) - 2260701 AS difference
FROM stg.Accepted_Raw
UNION ALL
SELECT 'Rejected_Raw', COUNT_BIG(*), 27648741, COUNT_BIG(*) - 27648741
FROM stg.Rejected_Raw;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 2. COLUMN COUNTS: confirm no column was lost or shifted (accepted should be 151, rejected 9). */

SELECT TABLE_NAME, COUNT(*) AS column_count
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'stg'
GROUP BY TABLE_NAME;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 3. FOOTER ROWS (accepted): the file ends with 2 non-loan summary lines. 
They must be identified so they can be excluded later instead of polluting counts and sums. */

SELECT id, loan_amnt, funded_amnt, loan_status, issue_d
FROM stg.Accepted_Raw
WHERE TRY_CAST(id AS BIGINT) IS NULL;

/* test if the footer totals reconcile with the data. */
SELECT policy_code,
       COUNT_BIG(*) AS loans,
       SUM(TRY_CAST(funded_amnt AS DECIMAL(18,2))) AS sum_funded_amnt
FROM stg.Accepted_Raw
WHERE TRY_CAST(id AS BIGINT) IS NOT NULL
GROUP BY policy_code;
-- footer says: policy 1 = 1,465,324,575 ; policy 2 = 521,953,170

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 4. LINE-ENDING CONTAMINATION: wrong row terminator leaves a hidden CHAR(13) on the last column. Expect 0. */
SELECT
  (SELECT COUNT_BIG(*) FROM stg.Accepted_Raw WHERE RIGHT(settlement_term,1) = CHAR(13)) AS accepted_cr_rows,
  (SELECT COUNT_BIG(*) FROM stg.Rejected_Raw WHERE RIGHT(Policy_Code,1)   = CHAR(13)) AS rejected_cr_rows;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 5. BLANK / NULL COUNT PER COLUMN (accepted): shows which of the 151 columns are usable. Mostly-empty columns are
   candidates to leave out of the clean model. One table scan, built dynamically
   so we don't hand-type 151 expressions. */

IF SCHEMA_ID('audit') IS NULL EXEC('CREATE SCHEMA audit');
DROP TABLE IF EXISTS audit.Accepted_Blank_Profile;

DECLARE @sums NVARCHAR(MAX), @vals NVARCHAR(MAX), @sql NVARCHAR(MAX);

SELECT @sums = STRING_AGG(CAST(
         'SUM(CASE WHEN [' + COLUMN_NAME + '] IS NULL OR LTRIM(RTRIM([' + COLUMN_NAME + ']))='''' THEN 1 ELSE 0 END) AS [' + COLUMN_NAME + ']'
       AS NVARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY ORDINAL_POSITION),
       @vals = STRING_AGG(CAST(
         '(''' + COLUMN_NAME + ''', s.[' + COLUMN_NAME + '])'
       AS NVARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY ORDINAL_POSITION)
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'stg' AND TABLE_NAME = 'Accepted_Raw';

SET @sql = N'SELECT v.column_name, v.blank_rows,
             CAST(100.0 * v.blank_rows / t.total AS DECIMAL(6,2)) AS blank_pct
             INTO audit.Accepted_Blank_Profile
             FROM (SELECT ' + @sums + N' FROM stg.Accepted_Raw) s
             CROSS APPLY (VALUES ' + @vals + N') v(column_name, blank_rows)
             CROSS JOIN (SELECT COUNT_BIG(*) AS total FROM stg.Accepted_Raw) t;';
EXEC sp_executesql @sql;

SELECT * FROM audit.Accepted_Blank_Profile ORDER BY blank_pct DESC;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 6. KEY COLUMN BLANKS (rejected) */
SELECT
  SUM(CASE WHEN NULLIF(LTRIM(RTRIM(Amount_Requested)),'')     IS NULL THEN 1 ELSE 0 END) AS amount_blank,
  SUM(CASE WHEN NULLIF(LTRIM(RTRIM(Application_Date)),'')     IS NULL THEN 1 ELSE 0 END) AS date_blank,
  SUM(CASE WHEN NULLIF(LTRIM(RTRIM(Risk_Score)),'')           IS NULL THEN 1 ELSE 0 END) AS risk_blank,
  SUM(CASE WHEN NULLIF(LTRIM(RTRIM(Debt_To_Income_Ratio)),'') IS NULL THEN 1 ELSE 0 END) AS dti_blank,
  SUM(CASE WHEN NULLIF(LTRIM(RTRIM(State)),'')                IS NULL THEN 1 ELSE 0 END) AS state_blank,
  SUM(CASE WHEN NULLIF(LTRIM(RTRIM(Employment_Length)),'')    IS NULL THEN 1 ELSE 0 END) AS emp_len_blank
FROM stg.Rejected_Raw;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 7. CATEGORY VALUES (accepted): reveals the real list of statuses, terms, grades etc. before we design
   business rules and dimensions around them. */
SELECT loan_status, COUNT_BIG(*) AS n FROM stg.Accepted_Raw GROUP BY loan_status ORDER BY n DESC;
SELECT term,        COUNT_BIG(*) AS n FROM stg.Accepted_Raw GROUP BY term ORDER BY n DESC;
SELECT grade,       COUNT_BIG(*) AS n FROM stg.Accepted_Raw GROUP BY grade ORDER BY grade;
SELECT home_ownership,      COUNT_BIG(*) AS n FROM stg.Accepted_Raw GROUP BY home_ownership ORDER BY n DESC;
SELECT verification_status, COUNT_BIG(*) AS n FROM stg.Accepted_Raw GROUP BY verification_status ORDER BY n DESC;
SELECT purpose,     COUNT_BIG(*) AS n FROM stg.Accepted_Raw GROUP BY purpose ORDER BY n DESC;
SELECT application_type, COUNT_BIG(*) AS n FROM stg.Accepted_Raw GROUP BY application_type ORDER BY n DESC;
SELECT emp_length,  COUNT_BIG(*) AS n FROM stg.Accepted_Raw GROUP BY emp_length ORDER BY n DESC;
SELECT COUNT(DISTINCT addr_state) AS distinct_states FROM stg.Accepted_Raw;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 8. CATEGORY VALUES (rejected) */
SELECT Policy_Code,       COUNT_BIG(*) AS n FROM stg.Rejected_Raw GROUP BY Policy_Code ORDER BY n DESC;
SELECT Employment_Length, COUNT_BIG(*) AS n FROM stg.Rejected_Raw GROUP BY Employment_Length ORDER BY n DESC;
SELECT COUNT(DISTINCT State) AS distinct_states FROM stg.Rejected_Raw;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 9. DATE PARSING (accepted issue_d, format Mon-YYYY): the time dimension depends on this. Failures are counted, not hidden. */
SELECT
  COUNT_BIG(*) AS rows_checked,
  SUM(CASE WHEN TRY_CONVERT(date, '01 ' + REPLACE(issue_d,'-',' '), 106) IS NULL THEN 1 ELSE 0 END) AS unparseable,
  MIN(TRY_CONVERT(date, '01 ' + REPLACE(issue_d,'-',' '), 106)) AS min_issue,
  MAX(TRY_CONVERT(date, '01 ' + REPLACE(issue_d,'-',' '), 106)) AS max_issue
FROM stg.Accepted_Raw
WHERE TRY_CAST(id AS BIGINT) IS NOT NULL;

/* Rejected application dates */
SELECT TOP 5 Application_Date FROM stg.Rejected_Raw;   -- inspect the format
SELECT
  SUM(CASE WHEN TRY_CONVERT(date, Application_Date) IS NULL THEN 1 ELSE 0 END) AS unparseable,
  MIN(TRY_CONVERT(date, Application_Date)) AS min_date,
  MAX(TRY_CONVERT(date, Application_Date)) AS max_date
FROM stg.Rejected_Raw;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 10. NUMERIC PARSING (accepted): any non-blank value that fails conversion would silently become NULL later. */
SELECT
  SUM(CASE WHEN NULLIF(loan_amnt,'')   IS NOT NULL AND TRY_CAST(loan_amnt   AS DECIMAL(18,2)) IS NULL THEN 1 ELSE 0 END) AS bad_loan_amnt,
  SUM(CASE WHEN NULLIF(funded_amnt,'') IS NOT NULL AND TRY_CAST(funded_amnt AS DECIMAL(18,2)) IS NULL THEN 1 ELSE 0 END) AS bad_funded_amnt,
  SUM(CASE WHEN NULLIF(int_rate,'')    IS NOT NULL AND TRY_CAST(int_rate    AS DECIMAL(9,4))  IS NULL THEN 1 ELSE 0 END) AS bad_int_rate,
  SUM(CASE WHEN NULLIF(annual_inc,'')  IS NOT NULL AND TRY_CAST(annual_inc  AS DECIMAL(18,2)) IS NULL THEN 1 ELSE 0 END) AS bad_annual_inc,
  SUM(CASE WHEN NULLIF(dti,'')         IS NOT NULL AND TRY_CAST(dti         AS DECIMAL(9,2))  IS NULL THEN 1 ELSE 0 END) AS bad_dti,
  SUM(CASE WHEN NULLIF(total_pymnt,'') IS NOT NULL AND TRY_CAST(total_pymnt AS DECIMAL(18,2)) IS NULL THEN 1 ELSE 0 END) AS bad_total_pymnt
FROM stg.Accepted_Raw
WHERE TRY_CAST(id AS BIGINT) IS NOT NULL;

SELECT
  MIN(TRY_CAST(loan_amnt AS DECIMAL(18,2))) AS min_loan, MAX(TRY_CAST(loan_amnt AS DECIMAL(18,2))) AS max_loan,
  MIN(TRY_CAST(int_rate  AS DECIMAL(9,4)))  AS min_rate, MAX(TRY_CAST(int_rate  AS DECIMAL(9,4)))  AS max_rate,
  MIN(TRY_CAST(annual_inc AS DECIMAL(18,2))) AS min_income, MAX(TRY_CAST(annual_inc AS DECIMAL(18,2))) AS max_income,
  MIN(TRY_CAST(dti AS DECIMAL(9,2))) AS min_dti, MAX(TRY_CAST(dti AS DECIMAL(9,2))) AS max_dti
FROM stg.Accepted_Raw
WHERE TRY_CAST(id AS BIGINT) IS NOT NULL;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 11. NUMERIC PARSING (rejected): Rejected DTI is expected to contain a % sign, so strip it before testing. */
SELECT TOP 5 Debt_To_Income_Ratio, Risk_Score, Amount_Requested FROM stg.Rejected_Raw;
SELECT
  SUM(CASE WHEN NULLIF(Amount_Requested,'') IS NOT NULL AND TRY_CAST(Amount_Requested AS DECIMAL(18,2)) IS NULL THEN 1 ELSE 0 END) AS bad_amount,
  SUM(CASE WHEN NULLIF(Debt_To_Income_Ratio,'') IS NOT NULL AND TRY_CAST(REPLACE(Debt_To_Income_Ratio,'%','') AS DECIMAL(18,2)) IS NULL THEN 1 ELSE 0 END) AS bad_dti,
  SUM(CASE WHEN NULLIF(Risk_Score,'') IS NOT NULL AND TRY_CAST(Risk_Score AS DECIMAL(9,2)) IS NULL THEN 1 ELSE 0 END) AS bad_risk
FROM stg.Rejected_Raw;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 12. ID UNIQUENESS (accepted) */
SELECT COUNT_BIG(*) AS loan_rows, COUNT_BIG(DISTINCT id) AS distinct_ids
FROM stg.Accepted_Raw
WHERE TRY_CAST(id AS BIGINT) IS NOT NULL;

/* 13. DATABASE SIZE vs 50 GB CAP */
EXEC sp_spaceused;