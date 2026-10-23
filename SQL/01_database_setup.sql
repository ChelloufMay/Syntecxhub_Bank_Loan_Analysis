-- 01_database_setup.sql
USE master;
GO
IF DB_ID('Syntecxhub_Bank_Loan_Analysis') IS NULL
    CREATE DATABASE Syntecxhub_Bank_Loan_Analysis;
GO

-- SIMPLE recovery keeps the transaction log from growing during huge loads
ALTER DATABASE Syntecxhub_Bank_Loan_Analysis SET RECOVERY SIMPLE;
GO
USE Syntecxhub_Bank_Loan_Analysis;
GO
IF SCHEMA_ID('stg')  IS NULL EXEC('CREATE SCHEMA stg');
IF SCHEMA_ID('dim')  IS NULL EXEC('CREATE SCHEMA dim');
IF SCHEMA_ID('fact') IS NULL EXEC('CREATE SCHEMA fact');
GO

-- Rejected applications (9 columns, positional; clean names)
DROP TABLE IF EXISTS stg.Rejected_Raw;
CREATE TABLE stg.Rejected_Raw (
    Amount_Requested      VARCHAR(100) NULL,
    Application_Date      VARCHAR(100) NULL,
    Loan_Title            VARCHAR(500) NULL,
    Risk_Score            VARCHAR(100) NULL,
    Debt_To_Income_Ratio  VARCHAR(100) NULL,
    Zip_Code              VARCHAR(100) NULL,
    State                 VARCHAR(100) NULL,
    Employment_Length     VARCHAR(100) NULL,
    Policy_Code           VARCHAR(100) NULL
);

-- Accepted loans: from accepted_create_table.sql 
DROP TABLE IF EXISTS stg.Accepted_Raw;
CREATE TABLE stg.Accepted_Raw (
    [id] VARCHAR(100) NULL,
    [member_id] VARCHAR(100) NULL,
    [loan_amnt] VARCHAR(100) NULL,
    [funded_amnt] VARCHAR(100) NULL,
    [funded_amnt_inv] VARCHAR(100) NULL,
    [term] VARCHAR(100) NULL,
    [int_rate] VARCHAR(100) NULL,
    [installment] VARCHAR(100) NULL,
    [grade] VARCHAR(100) NULL,
    [sub_grade] VARCHAR(100) NULL,
    [emp_title] VARCHAR(500) NULL,
    [emp_length] VARCHAR(100) NULL,
    [home_ownership] VARCHAR(100) NULL,
    [annual_inc] VARCHAR(100) NULL,
    [verification_status] VARCHAR(100) NULL,
    [issue_d] VARCHAR(100) NULL,
    [loan_status] VARCHAR(100) NULL,
    [pymnt_plan] VARCHAR(100) NULL,
    [url] VARCHAR(500) NULL,
    [desc] VARCHAR(MAX) NULL,
    [purpose] VARCHAR(100) NULL,
    [title] VARCHAR(500) NULL,
    [zip_code] VARCHAR(100) NULL,
    [addr_state] VARCHAR(100) NULL,
    [dti] VARCHAR(100) NULL,
    [delinq_2yrs] VARCHAR(100) NULL,
    [earliest_cr_line] VARCHAR(100) NULL,
    [fico_range_low] VARCHAR(100) NULL,
    [fico_range_high] VARCHAR(100) NULL,
    [inq_last_6mths] VARCHAR(100) NULL,
    [mths_since_last_delinq] VARCHAR(100) NULL,
    [mths_since_last_record] VARCHAR(100) NULL,
    [open_acc] VARCHAR(100) NULL,
    [pub_rec] VARCHAR(100) NULL,
    [revol_bal] VARCHAR(100) NULL,
    [revol_util] VARCHAR(100) NULL,
    [total_acc] VARCHAR(100) NULL,
    [initial_list_status] VARCHAR(100) NULL,
    [out_prncp] VARCHAR(100) NULL,
    [out_prncp_inv] VARCHAR(100) NULL,
    [total_pymnt] VARCHAR(100) NULL,
    [total_pymnt_inv] VARCHAR(100) NULL,
    [total_rec_prncp] VARCHAR(100) NULL,
    [total_rec_int] VARCHAR(100) NULL,
    [total_rec_late_fee] VARCHAR(100) NULL,
    [recoveries] VARCHAR(100) NULL,
    [collection_recovery_fee] VARCHAR(100) NULL,
    [last_pymnt_d] VARCHAR(100) NULL,
    [last_pymnt_amnt] VARCHAR(100) NULL,
    [next_pymnt_d] VARCHAR(100) NULL,
    [last_credit_pull_d] VARCHAR(100) NULL,
    [last_fico_range_high] VARCHAR(100) NULL,
    [last_fico_range_low] VARCHAR(100) NULL,
    [collections_12_mths_ex_med] VARCHAR(100) NULL,
    [mths_since_last_major_derog] VARCHAR(100) NULL,
    [policy_code] VARCHAR(100) NULL,
    [application_type] VARCHAR(100) NULL,
    [annual_inc_joint] VARCHAR(100) NULL,
    [dti_joint] VARCHAR(100) NULL,
    [verification_status_joint] VARCHAR(100) NULL,
    [acc_now_delinq] VARCHAR(100) NULL,
    [tot_coll_amt] VARCHAR(100) NULL,
    [tot_cur_bal] VARCHAR(100) NULL,
    [open_acc_6m] VARCHAR(100) NULL,
    [open_act_il] VARCHAR(100) NULL,
    [open_il_12m] VARCHAR(100) NULL,
    [open_il_24m] VARCHAR(100) NULL,
    [mths_since_rcnt_il] VARCHAR(100) NULL,
    [total_bal_il] VARCHAR(100) NULL,
    [il_util] VARCHAR(100) NULL,
    [open_rv_12m] VARCHAR(100) NULL,
    [open_rv_24m] VARCHAR(100) NULL,
    [max_bal_bc] VARCHAR(100) NULL,
    [all_util] VARCHAR(100) NULL,
    [total_rev_hi_lim] VARCHAR(100) NULL,
    [inq_fi] VARCHAR(100) NULL,
    [total_cu_tl] VARCHAR(100) NULL,
    [inq_last_12m] VARCHAR(100) NULL,
    [acc_open_past_24mths] VARCHAR(100) NULL,
    [avg_cur_bal] VARCHAR(100) NULL,
    [bc_open_to_buy] VARCHAR(100) NULL,
    [bc_util] VARCHAR(100) NULL,
    [chargeoff_within_12_mths] VARCHAR(100) NULL,
    [delinq_amnt] VARCHAR(100) NULL,
    [mo_sin_old_il_acct] VARCHAR(100) NULL,
    [mo_sin_old_rev_tl_op] VARCHAR(100) NULL,
    [mo_sin_rcnt_rev_tl_op] VARCHAR(100) NULL,
    [mo_sin_rcnt_tl] VARCHAR(100) NULL,
    [mort_acc] VARCHAR(100) NULL,
    [mths_since_recent_bc] VARCHAR(100) NULL,
    [mths_since_recent_bc_dlq] VARCHAR(100) NULL,
    [mths_since_recent_inq] VARCHAR(100) NULL,
    [mths_since_recent_revol_delinq] VARCHAR(100) NULL,
    [num_accts_ever_120_pd] VARCHAR(100) NULL,
    [num_actv_bc_tl] VARCHAR(100) NULL,
    [num_actv_rev_tl] VARCHAR(100) NULL,
    [num_bc_sats] VARCHAR(100) NULL,
    [num_bc_tl] VARCHAR(100) NULL,
    [num_il_tl] VARCHAR(100) NULL,
    [num_op_rev_tl] VARCHAR(100) NULL,
    [num_rev_accts] VARCHAR(100) NULL,
    [num_rev_tl_bal_gt_0] VARCHAR(100) NULL,
    [num_sats] VARCHAR(100) NULL,
    [num_tl_120dpd_2m] VARCHAR(100) NULL,
    [num_tl_30dpd] VARCHAR(100) NULL,
    [num_tl_90g_dpd_24m] VARCHAR(100) NULL,
    [num_tl_op_past_12m] VARCHAR(100) NULL,
    [pct_tl_nvr_dlq] VARCHAR(100) NULL,
    [percent_bc_gt_75] VARCHAR(100) NULL,
    [pub_rec_bankruptcies] VARCHAR(100) NULL,
    [tax_liens] VARCHAR(100) NULL,
    [tot_hi_cred_lim] VARCHAR(100) NULL,
    [total_bal_ex_mort] VARCHAR(100) NULL,
    [total_bc_limit] VARCHAR(100) NULL,
    [total_il_high_credit_limit] VARCHAR(100) NULL,
    [revol_bal_joint] VARCHAR(100) NULL,
    [sec_app_fico_range_low] VARCHAR(100) NULL,
    [sec_app_fico_range_high] VARCHAR(100) NULL,
    [sec_app_earliest_cr_line] VARCHAR(100) NULL,
    [sec_app_inq_last_6mths] VARCHAR(100) NULL,
    [sec_app_mort_acc] VARCHAR(100) NULL,
    [sec_app_open_acc] VARCHAR(100) NULL,
    [sec_app_revol_util] VARCHAR(100) NULL,
    [sec_app_open_act_il] VARCHAR(100) NULL,
    [sec_app_num_rev_accts] VARCHAR(100) NULL,
    [sec_app_chargeoff_within_12_mths] VARCHAR(100) NULL,
    [sec_app_collections_12_mths_ex_med] VARCHAR(100) NULL,
    [sec_app_mths_since_last_major_derog] VARCHAR(100) NULL,
    [hardship_flag] VARCHAR(100) NULL,
    [hardship_type] VARCHAR(100) NULL,
    [hardship_reason] VARCHAR(100) NULL,
    [hardship_status] VARCHAR(100) NULL,
    [deferral_term] VARCHAR(100) NULL,
    [hardship_amount] VARCHAR(100) NULL,
    [hardship_start_date] VARCHAR(100) NULL,
    [hardship_end_date] VARCHAR(100) NULL,
    [payment_plan_start_date] VARCHAR(100) NULL,
    [hardship_length] VARCHAR(100) NULL,
    [hardship_dpd] VARCHAR(100) NULL,
    [hardship_loan_status] VARCHAR(100) NULL,
    [orig_projected_additional_accrued_interest] VARCHAR(100) NULL,
    [hardship_payoff_balance_amount] VARCHAR(100) NULL,
    [hardship_last_payment_amount] VARCHAR(100) NULL,
    [disbursement_method] VARCHAR(100) NULL,
    [debt_settlement_flag] VARCHAR(100) NULL,
    [debt_settlement_flag_date] VARCHAR(100) NULL,
    [settlement_status] VARCHAR(100) NULL,
    [settlement_date] VARCHAR(100) NULL,
    [settlement_amount] VARCHAR(100) NULL,
    [settlement_percentage] VARCHAR(100) NULL,
    [settlement_term] VARCHAR(100) NULL
);
GO

-- Load accepted (set ROWTERMINATOR to '0x0a' because the line ending is in Unix endings )
BULK INSERT stg.Accepted_Raw
FROM 'C:\SQLImport\accepted_2007_to_2018Q4.csv'
WITH (
    FORMAT = 'CSV', FIELDQUOTE = '"', FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    FIRSTROW = 2, CODEPAGE = '65001',
    BATCHSIZE = 100000, TABLOCK
);
GO

-- Load rejected

TRUNCATE TABLE stg.Rejected_Raw;
ALTER TABLE stg.Rejected_Raw ALTER COLUMN Loan_Title NVARCHAR(MAX) NULL;
GO

BULK INSERT stg.Rejected_Raw
FROM 'C:\SQLImport\rejected_2007_to_2018Q4.csv'
WITH (
    FORMAT = 'CSV', FIELDQUOTE = '"', FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    FIRSTROW = 2, CODEPAGE = '65001',
    BATCHSIZE = 100000, TABLOCK
);
GO

-- Quick check (full validation is Step 3)
SELECT 'Accepted_Raw' AS tbl, COUNT_BIG(*) AS row_count FROM stg.Accepted_Raw
UNION ALL
SELECT 'Rejected_Raw', COUNT_BIG(*) FROM stg.Rejected_Raw;