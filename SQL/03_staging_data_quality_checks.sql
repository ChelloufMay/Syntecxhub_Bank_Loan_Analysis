-- 03_staging_data_quality_checks.sql
USE Syntecxhub_Bank_Loan_Analysis;
GO

-- View of valid loans only (numeric id). A view modifies no data.
CREATE OR ALTER VIEW audit.v_Accepted_Loans AS
SELECT * FROM stg.Accepted_Raw WHERE TRY_CAST(id AS BIGINT) IS NOT NULL;
GO

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* ===== A1. NON-LOAN ROWS + FOOTER RECONCILIATION (automated) ===== */
SELECT COUNT(*) AS non_loan_rows FROM stg.Accepted_Raw WHERE TRY_CAST(id AS BIGINT) IS NULL;      -- 33
SELECT COUNT(*) AS loans_with_blank_status FROM audit.v_Accepted_Loans WHERE NULLIF(loan_status,'') IS NULL; -- 0

SELECT
  SUM(CASE WHEN id LIKE 'Total amount funded in policy code 1:%'
           THEN TRY_CAST(LTRIM(SUBSTRING(id, CHARINDEX(':', id)+1, 50)) AS BIGINT) END) AS footer_policy1_total,
  (SELECT SUM(TRY_CAST(funded_amnt AS DECIMAL(18,2))) FROM audit.v_Accepted_Loans)      AS loans_funded_total
FROM stg.Accepted_Raw WHERE TRY_CAST(id AS BIGINT) IS NULL; 

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* ===== A2. POSSIBLE DUPLICATE LOANS (same attributes, different id): unique ids don't rule out a loan listed twice under two ids. ===== */
SELECT COUNT_BIG(*) AS duplicate_groups, SUM(n) AS rows_involved
FROM (SELECT COUNT_BIG(*) AS n
      FROM audit.v_Accepted_Loans
      GROUP BY loan_amnt, term, int_rate, installment, issue_d, annual_inc, earliest_cr_line, zip_code, dti, grade
      HAVING COUNT_BIG(*) > 1) d;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* ===== A3. INVALID / SUSPICIOUS NUMERIC VALUES (accepted) ===== */
SELECT
  SUM(CASE WHEN TRY_CAST(loan_amnt   AS DECIMAL(18,2)) <= 0 THEN 1 ELSE 0 END) AS loan_amnt_le0,
  SUM(CASE WHEN TRY_CAST(funded_amnt AS DECIMAL(18,2)) <= 0 THEN 1 ELSE 0 END) AS funded_le0,
  SUM(CASE WHEN TRY_CAST(funded_amnt AS DECIMAL(18,2)) > TRY_CAST(loan_amnt AS DECIMAL(18,2)) THEN 1 ELSE 0 END) AS funded_gt_requested,
  SUM(CASE WHEN TRY_CAST(installment AS DECIMAL(18,2)) <= 0 THEN 1 ELSE 0 END) AS installment_le0,
  SUM(CASE WHEN TRY_CAST(annual_inc  AS DECIMAL(18,2)) = 0 THEN 1 ELSE 0 END)  AS income_zero,
  SUM(CASE WHEN TRY_CAST(annual_inc  AS DECIMAL(18,2)) > 1000000 THEN 1 ELSE 0 END) AS income_gt_1m,
  SUM(CASE WHEN NULLIF(dti,'') IS NULL THEN 1 ELSE 0 END)                       AS dti_blank,
  SUM(CASE WHEN TRY_CAST(dti AS DECIMAL(9,2)) < 0 THEN 1 ELSE 0 END)            AS dti_negative,
  SUM(CASE WHEN TRY_CAST(dti AS DECIMAL(9,2)) >= 999 THEN 1 ELSE 0 END)         AS dti_999_sentinel,
  SUM(CASE WHEN TRY_CAST(dti AS DECIMAL(9,2)) > 100 AND TRY_CAST(dti AS DECIMAL(9,2)) < 999 THEN 1 ELSE 0 END) AS dti_100_to_998,
  SUM(CASE WHEN TRY_CAST(total_pymnt AS DECIMAL(18,2)) < 0 THEN 1 ELSE 0 END)   AS pymnt_negative,
  SUM(CASE WHEN TRY_CAST(out_prncp   AS DECIMAL(18,2)) < 0 THEN 1 ELSE 0 END)   AS out_prncp_negative,
  SUM(CASE WHEN TRY_CAST(fico_range_low AS DECIMAL(9,2)) > TRY_CAST(fico_range_high AS DECIMAL(9,2)) THEN 1 ELSE 0 END) AS fico_low_gt_high,
  SUM(CASE WHEN TRY_CAST(revol_util AS DECIMAL(9,2)) > 100 THEN 1 ELSE 0 END)   AS revol_util_gt_100
FROM audit.v_Accepted_Loans;

-- The extreme incomes: are they real or typos?
SELECT TOP 20 id, annual_inc, loan_amnt, dti, grade, loan_status
FROM audit.v_Accepted_Loans
ORDER BY TRY_CAST(annual_inc AS DECIMAL(18,2)) DESC;

-- DTI distribution
SELECT CASE WHEN d IS NULL THEN 'blank'
            WHEN d < 0 THEN '<0'
            WHEN d < 10 THEN '0-9.99'  WHEN d < 20 THEN '10-19.99'
            WHEN d < 30 THEN '20-29.99' WHEN d < 40 THEN '30-39.99'
            WHEN d < 100 THEN '40-99.99' WHEN d < 999 THEN '100-998' ELSE '999+' END AS dti_band,
       COUNT_BIG(*) AS loans
FROM (SELECT TRY_CAST(dti AS DECIMAL(9,2)) AS d FROM audit.v_Accepted_Loans) x
GROUP BY CASE WHEN d IS NULL THEN 'blank'
            WHEN d < 0 THEN '<0'
            WHEN d < 10 THEN '0-9.99'  WHEN d < 20 THEN '10-19.99'
            WHEN d < 30 THEN '20-29.99' WHEN d < 40 THEN '30-39.99'
            WHEN d < 100 THEN '40-99.99' WHEN d < 999 THEN '100-998' ELSE '999+' END
ORDER BY MIN(ISNULL(d,-999));

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* ===== A4. DATE PARSING AND LOGIC (accepted) ===== */
SELECT
  SUM(CASE WHEN NULLIF(earliest_cr_line,'')   IS NOT NULL AND TRY_CONVERT(date,'01 '+REPLACE(earliest_cr_line,'-',' '),106)   IS NULL THEN 1 ELSE 0 END) AS bad_earliest_cr,
  SUM(CASE WHEN NULLIF(last_pymnt_d,'')       IS NOT NULL AND TRY_CONVERT(date,'01 '+REPLACE(last_pymnt_d,'-',' '),106)       IS NULL THEN 1 ELSE 0 END) AS bad_last_pymnt,
  SUM(CASE WHEN NULLIF(next_pymnt_d,'')       IS NOT NULL AND TRY_CONVERT(date,'01 '+REPLACE(next_pymnt_d,'-',' '),106)       IS NULL THEN 1 ELSE 0 END) AS bad_next_pymnt,
  SUM(CASE WHEN NULLIF(last_credit_pull_d,'') IS NOT NULL AND TRY_CONVERT(date,'01 '+REPLACE(last_credit_pull_d,'-',' '),106) IS NULL THEN 1 ELSE 0 END) AS bad_credit_pull
FROM audit.v_Accepted_Loans;

SELECT
  SUM(CASE WHEN d.last_pymnt < d.issue_dt THEN 1 ELSE 0 END)  AS last_pymnt_before_issue,
  SUM(CASE WHEN d.earliest_cr > d.issue_dt THEN 1 ELSE 0 END) AS credit_line_after_issue,
  SUM(CASE WHEN d.next_pymnt < d.issue_dt THEN 1 ELSE 0 END)  AS next_pymnt_before_issue
FROM audit.v_Accepted_Loans a
CROSS APPLY (SELECT
   TRY_CONVERT(date,'01 '+REPLACE(a.issue_d,'-',' '),106)          AS issue_dt,
   TRY_CONVERT(date,'01 '+REPLACE(a.last_pymnt_d,'-',' '),106)     AS last_pymnt,
   TRY_CONVERT(date,'01 '+REPLACE(a.earliest_cr_line,'-',' '),106) AS earliest_cr,
   TRY_CONVERT(date,'01 '+REPLACE(a.next_pymnt_d,'-',' '),106)     AS next_pymnt) d;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* ===== A5. CATEGORY CONSISTENCY (accepted) ===== */
SELECT
  SUM(CASE WHEN LEN(addr_state) <> 2 THEN 1 ELSE 0 END)                  AS state_not_2_chars,
  SUM(CASE WHEN LEFT(sub_grade,1) <> grade THEN 1 ELSE 0 END)            AS subgrade_grade_mismatch,
  SUM(CASE WHEN zip_code NOT LIKE '[0-9][0-9][0-9]xx' THEN 1 ELSE 0 END) AS zip_bad_format,
  SUM(CASE WHEN LEFT(term,1) = ' ' THEN 1 ELSE 0 END)                    AS term_leading_space,
  COUNT(DISTINCT sub_grade)                                              AS distinct_subgrades
FROM audit.v_Accepted_Loans;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* ===== A6. LOAN STATUS vs PAYMENT BEHAVIOUR: a status must make sense with its money columns, and this shows what
   "amount received" looks like for each status. ===== */
SELECT loan_status,
       COUNT_BIG(*) AS loans,
       SUM(CASE WHEN TRY_CAST(out_prncp AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END) AS has_outstanding_principal,
       SUM(CASE WHEN TRY_CAST(total_pymnt AS DECIMAL(18,2)) < TRY_CAST(funded_amnt AS DECIMAL(18,2)) THEN 1 ELSE 0 END) AS repaid_less_than_funded,
       CAST(AVG(TRY_CAST(total_pymnt AS DECIMAL(18,2)) / NULLIF(TRY_CAST(funded_amnt AS DECIMAL(18,2)),0)) AS DECIMAL(9,3)) AS avg_repay_ratio
FROM audit.v_Accepted_Loans
GROUP BY loan_status ORDER BY loans DESC;

/* Exploratory: what is total_pymnt made of? (defines the "amount received" KPI) */
SELECT COUNT_BIG(*) AS loans,
  SUM(CASE WHEN ABS(p - (rp + ri + lf))       <= 0.05 THEN 1 ELSE 0 END) AS matches_without_recoveries,
  SUM(CASE WHEN ABS(p - (rp + ri + lf + rec)) <= 0.05 THEN 1 ELSE 0 END) AS matches_with_recoveries
FROM audit.v_Accepted_Loans a
CROSS APPLY (SELECT TRY_CAST(a.total_pymnt AS DECIMAL(18,2)) p,
                    TRY_CAST(a.total_rec_prncp AS DECIMAL(18,2)) rp,
                    TRY_CAST(a.total_rec_int AS DECIMAL(18,2)) ri,
                    TRY_CAST(a.total_rec_late_fee AS DECIMAL(18,2)) lf,
                    TRY_CAST(a.recoveries AS DECIMAL(18,2)) rec) x;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* ===== A7. ISSUE YEAR x STATUS =====
   Why: recent loans are mostly "Current", so their default rate looks artificially
   low (they haven't had time to default). This decides how fairly we can
   compare years. */
SELECT YEAR(TRY_CONVERT(date,'01 '+REPLACE(issue_d,'-',' '),106)) AS issue_year,
       COUNT_BIG(*) AS loans,
       SUM(CASE WHEN loan_status LIKE '%Fully Paid'  THEN 1 ELSE 0 END) AS fully_paid,
       SUM(CASE WHEN loan_status LIKE '%Charged Off' OR loan_status = 'Default' THEN 1 ELSE 0 END) AS charged_off_or_default,
       SUM(CASE WHEN loan_status = 'Current' THEN 1 ELSE 0 END)         AS current_loans,
       SUM(CASE WHEN loan_status LIKE 'Late%' OR loan_status = 'In Grace Period' THEN 1 ELSE 0 END) AS late_or_grace
FROM audit.v_Accepted_Loans
GROUP BY YEAR(TRY_CONVERT(date,'01 '+REPLACE(issue_d,'-',' '),106))
ORDER BY issue_year;

/* ===== R1. REJECTED: VALUE RANGES ===== */
SELECT COUNT_BIG(*) AS rows_checked,
  SUM(CASE WHEN amt <= 0 THEN 1 ELSE 0 END)   AS amount_le0,
  MIN(amt) AS min_amount, MAX(amt) AS max_amount,
  SUM(CASE WHEN dti < 0 THEN 1 ELSE 0 END)    AS dti_negative,
  SUM(CASE WHEN dti > 100 THEN 1 ELSE 0 END)  AS dti_gt_100,
  MIN(dti) AS min_dti, MAX(dti) AS max_dti,
  MIN(risk) AS min_risk, MAX(risk) AS max_risk
FROM stg.Rejected_Raw
CROSS APPLY (SELECT TRY_CAST(Amount_Requested AS DECIMAL(18,2)) amt,
                    TRY_CAST(REPLACE(Debt_To_Income_Ratio,'%','') AS DECIMAL(18,2)) dti,
                    TRY_CAST(Risk_Score AS DECIMAL(9,2)) risk) x;

/* ===== R2. REJECTED: BY YEAR (are Risk_Score / Employment_Length usable?) ===== */
SELECT YEAR(TRY_CONVERT(date, Application_Date)) AS app_year,
       COUNT_BIG(*) AS rejected_apps,
       SUM(CASE WHEN NULLIF(Risk_Score,'') IS NULL THEN 1 ELSE 0 END) AS risk_blank,
       SUM(CASE WHEN Employment_Length = '< 1 year' THEN 1 ELSE 0 END) AS emp_lt_1yr
FROM stg.Rejected_Raw
GROUP BY YEAR(TRY_CONVERT(date, Application_Date))
ORDER BY app_year;

/* ===== R3. REJECTED: ODD ROWS ===== */
SELECT TOP 20 * FROM stg.Rejected_Raw WHERE NULLIF(Policy_Code,'') IS NULL;   -- 918 rows
SELECT TOP 20 * FROM stg.Rejected_Raw WHERE NULLIF(State,'') IS NULL;         -- 22 rows
SELECT State, COUNT_BIG(*) AS n FROM stg.Rejected_Raw
WHERE State IS NULL OR LEN(State) <> 2 GROUP BY State;
SELECT COUNT_BIG(*) AS zip_bad_format FROM stg.Rejected_Raw
WHERE Zip_Code IS NOT NULL AND Zip_Code NOT LIKE '[0-9][0-9][0-9]xx';

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* ===== C1. ACCEPTED vs REJECTED BY YEAR (preview of approval rate) =====
   Caveat: accepted uses issue date, rejected uses application date. */
WITH a AS (SELECT YEAR(TRY_CONVERT(date,'01 '+REPLACE(issue_d,'-',' '),106)) AS yr, COUNT_BIG(*) AS accepted
           FROM audit.v_Accepted_Loans GROUP BY YEAR(TRY_CONVERT(date,'01 '+REPLACE(issue_d,'-',' '),106))),
     r AS (SELECT YEAR(TRY_CONVERT(date, Application_Date)) AS yr, COUNT_BIG(*) AS rejected
           FROM stg.Rejected_Raw GROUP BY YEAR(TRY_CONVERT(date, Application_Date)))
SELECT COALESCE(a.yr, r.yr) AS yr, a.accepted, r.rejected,
       CAST(100.0 * a.accepted / NULLIF(a.accepted + r.rejected, 0) AS DECIMAL(5,2)) AS approval_rate_pct
FROM a FULL JOIN r ON a.yr = r.yr
ORDER BY yr;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* F1. The one duplicate pair: look at it */
SELECT * FROM (
  SELECT id, loan_amnt, term, int_rate, issue_d, annual_inc, zip_code, dti, grade,
         loan_status, total_pymnt, last_pymnt_d,
         COUNT(*) OVER (PARTITION BY loan_amnt, term, int_rate, installment, issue_d,
                        annual_inc, earliest_cr_line, zip_code, dti, grade) AS grp_size
  FROM audit.v_Accepted_Loans) x
WHERE grp_size > 1;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* F2. The 108 loans where total_pymnt does not equal the sum of its parts */
SELECT TOP 20 a.id, a.loan_status, x.p AS total_pymnt,
       x.rp + x.ri + x.lf + x.rec AS components,
       x.p - (x.rp + x.ri + x.lf + x.rec) AS diff
FROM audit.v_Accepted_Loans a
CROSS APPLY (SELECT TRY_CAST(a.total_pymnt AS DECIMAL(18,2)) p,
                    TRY_CAST(a.total_rec_prncp AS DECIMAL(18,2)) rp,
                    TRY_CAST(a.total_rec_int AS DECIMAL(18,2)) ri,
                    TRY_CAST(a.total_rec_late_fee AS DECIMAL(18,2)) lf,
                    TRY_CAST(a.recoveries AS DECIMAL(18,2)) rec) x
WHERE ABS(x.p - (x.rp + x.ri + x.lf + x.rec)) > 0.05
ORDER BY ABS(x.p - (x.rp + x.ri + x.lf + x.rec)) DESC;

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* F3. How many rejected rows will the DTI and Risk_Score rules affect */
SELECT
  SUM(CASE WHEN dti >= 999 THEN 1 ELSE 0 END)                         AS dti_ge_999,
  SUM(CASE WHEN dti >= 100 AND dti < 999 THEN 1 ELSE 0 END)           AS dti_100_to_998,
  SUM(CASE WHEN risk IS NOT NULL AND (risk < 300 OR risk > 850) THEN 1 ELSE 0 END) AS risk_outside_300_850,
  SUM(CASE WHEN risk = 0 THEN 1 ELSE 0 END)                           AS risk_zero
FROM stg.Rejected_Raw
CROSS APPLY (SELECT TRY_CAST(REPLACE(Debt_To_Income_Ratio,'%','') AS DECIMAL(18,2)) dti,
                    TRY_CAST(Risk_Score AS DECIMAL(9,2)) risk) x;