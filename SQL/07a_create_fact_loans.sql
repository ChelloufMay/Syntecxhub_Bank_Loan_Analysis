-- 07a_create_fact_loans.sql
USE Syntecxhub_Bank_Loan_Analysis;
GO

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/*  1. Source view: all joins and conversions in one place  */
CREATE OR ALTER VIEW audit.v_Fact_Loans_Source AS
SELECT
    r.Loan_ID,
    di.Date_Key                                    AS Issue_Date_Key,
    ls.Loan_Status_Key,
    g.Grade_Key,
    p.Purpose_Key,
    ho.Home_Ownership_Key,
    t.Term_Key,
    v.Verification_Key,
    ap.Application_Type_Key,
    el.Emp_Length_Key,
    geo.Geography_Key,
    CAST(COALESCE(bd.Band_Key, 6) AS TINYINT)      AS DTI_Band_Key,
    CAST(COALESCE(bi.Band_Key, 7) AS TINYINT)      AS Income_Band_Key,
    CAST(COALESCE(ba.Band_Key, 7) AS TINYINT)      AS Loan_Amount_Band_Key,
    CAST(COALESCE(br.Band_Key, 6) AS TINYINT)      AS Risk_Band_Key,
    CAST(r.loan_amnt   AS DECIMAL(18,2))           AS Loan_Amount,
    CAST(r.funded_amnt AS DECIMAL(18,2))           AS Funded_Amount,
    CAST(r.installment AS DECIMAL(18,2))           AS Installment,
    CAST(r.int_rate    AS DECIMAL(9,2))            AS Interest_Rate,
    CAST(r.annual_inc_clean AS DECIMAL(18,2))      AS Annual_Income,
    CAST(r.dti_clean   AS DECIMAL(9,2))            AS DTI,
    CAST(r.total_pymnt AS DECIMAL(18,2))           AS Total_Payment,
    CAST(r.rec_prncp   AS DECIMAL(18,2))           AS Total_Rec_Principal,
    CAST(r.rec_int     AS DECIMAL(18,2))           AS Total_Rec_Interest,
    CAST(r.rec_late    AS DECIMAL(18,2))           AS Total_Rec_Late_Fee,
    CAST(r.recoveries  AS DECIMAL(18,2))           AS Recoveries,
    CAST(r.out_prncp   AS DECIMAL(18,2))           AS Out_Principal,
    CAST(r.last_pymnt_amnt AS DECIMAL(18,2))       AS Last_Payment_Amount,
    CAST(r.fico_low  AS INT)                       AS FICO_Low,
    CAST(r.fico_high AS INT)                       AS FICO_High,
    CAST(r.delinq    AS SMALLINT)                  AS Delinq_2yrs,
    CAST(r.inq       AS SMALLINT)                  AS Inq_Last_6mths,
    CAST(r.open_acc  AS SMALLINT)                  AS Open_Acc,
    CAST(r.pub_rec   AS SMALLINT)                  AS Pub_Rec,
    CAST(r.revol_bal  AS DECIMAL(18,2))            AS Revol_Bal,
    CAST(r.revol_util AS DECIMAL(9,2))             AS Revol_Util,
    CAST(CASE WHEN r.Earliest_Cr_Dt IS NULL THEN NULL
              ELSE DATEDIFF(YEAR, r.Earliest_Cr_Dt, r.Issue_Dt) END AS SMALLINT) AS Credit_History_Years,
    r.Last_Payment_Date,
    CAST(CASE WHEN DATEADD(MONTH, t.Term_Months, r.Issue_Dt) <= cfg.Snapshot_Date THEN 1 ELSE 0 END AS BIT) AS Is_Matured,
    CAST(CASE WHEN r.annual_inc_clean > cfg.Income_Outlier_Min THEN 1 ELSE 0 END AS BIT)                   AS Is_Income_Outlier,
    CAST(CASE WHEN r.Loan_ID IN (470612, 470026) THEN 1 ELSE 0 END AS BIT)                                 AS Is_Possible_Duplicate
FROM audit.v_Accepted_Loans a
CROSS JOIN (
    SELECT CAST(MAX(CASE WHEN Config_Key='Snapshot_Date'      THEN Config_Value END) AS DATE)          AS Snapshot_Date,
           CAST(MAX(CASE WHEN Config_Key='Income_Outlier_Min' THEN Config_Value END) AS DECIMAL(18,2)) AS Income_Outlier_Min,
           CAST(MAX(CASE WHEN Config_Key='DTI_Invalid_From'   THEN Config_Value END) AS DECIMAL(9,2))  AS DTI_Invalid_From
    FROM ref.Config) cfg
CROSS APPLY (SELECT
    CAST(a.id AS BIGINT)                                                   AS Loan_ID,
    TRY_CONVERT(date,'01 '+REPLACE(a.issue_d,'-',' '),106)                 AS Issue_Dt,
    TRY_CONVERT(date,'01 '+REPLACE(a.last_pymnt_d,'-',' '),106)            AS Last_Payment_Date,
    TRY_CONVERT(date,'01 '+REPLACE(a.earliest_cr_line,'-',' '),106)        AS Earliest_Cr_Dt,
    ROUND(TRY_CAST(a.loan_amnt   AS FLOAT),2)                              AS loan_amnt,
    ROUND(TRY_CAST(a.funded_amnt AS FLOAT),2)                              AS funded_amnt,
    ROUND(TRY_CAST(a.installment AS FLOAT),2)                              AS installment,
    ROUND(TRY_CAST(a.int_rate    AS FLOAT),2)                              AS int_rate,
    NULLIF(ROUND(TRY_CAST(a.annual_inc AS FLOAT),2),0)                     AS annual_inc_clean,
    CASE WHEN ROUND(TRY_CAST(a.dti AS FLOAT),2) < 0
           OR ROUND(TRY_CAST(a.dti AS FLOAT),2) >= cfg.DTI_Invalid_From THEN NULL
         ELSE ROUND(TRY_CAST(a.dti AS FLOAT),2) END                        AS dti_clean,
    ROUND(TRY_CAST(a.total_pymnt        AS FLOAT),2)                       AS total_pymnt,
    ROUND(TRY_CAST(a.total_rec_prncp    AS FLOAT),2)                       AS rec_prncp,
    ROUND(TRY_CAST(a.total_rec_int      AS FLOAT),2)                       AS rec_int,
    ROUND(TRY_CAST(a.total_rec_late_fee AS FLOAT),2)                       AS rec_late,
    ROUND(TRY_CAST(a.recoveries         AS FLOAT),2)                       AS recoveries,
    ROUND(TRY_CAST(a.out_prncp          AS FLOAT),2)                       AS out_prncp,
    ROUND(TRY_CAST(a.last_pymnt_amnt    AS FLOAT),2)                       AS last_pymnt_amnt,
    ROUND(TRY_CAST(a.fico_range_low  AS FLOAT),0)                          AS fico_low,
    ROUND(TRY_CAST(a.fico_range_high AS FLOAT),0)                          AS fico_high,
    ROUND(TRY_CAST(a.delinq_2yrs     AS FLOAT),0)                          AS delinq,
    ROUND(TRY_CAST(a.inq_last_6mths  AS FLOAT),0)                          AS inq,
    ROUND(TRY_CAST(a.open_acc        AS FLOAT),0)                          AS open_acc,
    ROUND(TRY_CAST(a.pub_rec         AS FLOAT),0)                          AS pub_rec,
    ROUND(TRY_CAST(a.revol_bal       AS FLOAT),2)                          AS revol_bal,
    ROUND(TRY_CAST(a.revol_util      AS FLOAT),2)                          AS revol_util
) r
LEFT JOIN dim.Date di                 ON di.Full_Date = r.Issue_Dt
LEFT JOIN ref.Loan_Status_Map m       ON m.Loan_Status_Raw = a.loan_status
LEFT JOIN dim.Loan_Status ls          ON ls.Loan_Status = m.Loan_Status_Clean
LEFT JOIN dim.Grade g                 ON g.Sub_Grade = LTRIM(RTRIM(a.sub_grade))
LEFT JOIN dim.Purpose p               ON p.Purpose_Raw = LTRIM(RTRIM(a.purpose))
LEFT JOIN ref.Home_Ownership_Map hm   ON hm.Home_Ownership_Raw = LTRIM(RTRIM(a.home_ownership))
LEFT JOIN dim.Home_Ownership ho       ON ho.Home_Ownership = hm.Home_Ownership_Clean
LEFT JOIN dim.Term t                  ON t.Term_Months = CAST(LEFT(LTRIM(a.term),2) AS INT)
LEFT JOIN dim.Verification_Status v   ON v.Verification_Status = LTRIM(RTRIM(a.verification_status))
LEFT JOIN dim.Application_Type ap     ON ap.Application_Type = LTRIM(RTRIM(a.application_type))
LEFT JOIN dim.Employment_Length el    ON el.Emp_Length_Label = COALESCE(NULLIF(LTRIM(RTRIM(a.emp_length)),''),'Unknown')
LEFT JOIN dim.Geography geo           ON geo.State_Code = LTRIM(RTRIM(a.addr_state))
LEFT JOIN ref.DTI_Band bd             ON r.dti_clean >= bd.Lower_Bound AND r.dti_clean < bd.Upper_Bound
LEFT JOIN ref.Income_Band bi          ON r.annual_inc_clean >= bi.Lower_Bound AND r.annual_inc_clean < bi.Upper_Bound
LEFT JOIN ref.Loan_Amount_Band ba     ON r.loan_amnt >= ba.Lower_Bound AND r.loan_amnt < ba.Upper_Bound
LEFT JOIN ref.Risk_Band br            ON r.fico_low >= br.Lower_Bound AND r.fico_low < br.Upper_Bound;
GO


/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 2. ORPHAN CHECK (every count except source_rows must be 0)  */
SELECT COUNT_BIG(*) AS source_rows,   -- must be 2,260,668 (joins must not multiply or drop rows)
  SUM(CASE WHEN Issue_Date_Key        IS NULL THEN 1 ELSE 0 END) AS issue_date_missing,
  SUM(CASE WHEN Loan_Status_Key       IS NULL THEN 1 ELSE 0 END) AS status_missing,
  SUM(CASE WHEN Grade_Key             IS NULL THEN 1 ELSE 0 END) AS grade_missing,
  SUM(CASE WHEN Purpose_Key           IS NULL THEN 1 ELSE 0 END) AS purpose_missing,
  SUM(CASE WHEN Home_Ownership_Key    IS NULL THEN 1 ELSE 0 END) AS home_missing,
  SUM(CASE WHEN Term_Key              IS NULL THEN 1 ELSE 0 END) AS term_missing,
  SUM(CASE WHEN Verification_Key      IS NULL THEN 1 ELSE 0 END) AS verification_missing,
  SUM(CASE WHEN Application_Type_Key  IS NULL THEN 1 ELSE 0 END) AS apptype_missing,
  SUM(CASE WHEN Emp_Length_Key        IS NULL THEN 1 ELSE 0 END) AS emp_missing,
  SUM(CASE WHEN Geography_Key         IS NULL THEN 1 ELSE 0 END) AS geography_missing,
  SUM(CASE WHEN Funded_Amount IS NULL OR Loan_Amount IS NULL OR Installment IS NULL OR Interest_Rate IS NULL
             OR Total_Payment IS NULL OR Total_Rec_Principal IS NULL OR Total_Rec_Interest IS NULL
             OR Total_Rec_Late_Fee IS NULL OR Recoveries IS NULL OR Out_Principal IS NULL
             OR Last_Payment_Amount IS NULL THEN 1 ELSE 0 END)  AS required_money_null
FROM audit.v_Fact_Loans_Source;
GO

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 3. Create and load the fact table (only after the orphan check is clean) */
DROP TABLE IF EXISTS fact.Loans;
CREATE TABLE fact.Loans (
    Loan_ID               BIGINT        NOT NULL,
    Issue_Date_Key        INT           NOT NULL,
    Loan_Status_Key       INT           NOT NULL,
    Grade_Key             INT           NOT NULL,
    Purpose_Key           INT           NOT NULL,
    Home_Ownership_Key    INT           NOT NULL,
    Term_Key              INT           NOT NULL,
    Verification_Key      INT           NOT NULL,
    Application_Type_Key  INT           NOT NULL,
    Emp_Length_Key        INT           NOT NULL,
    Geography_Key         INT           NOT NULL,
    DTI_Band_Key          TINYINT       NOT NULL,
    Income_Band_Key       TINYINT       NOT NULL,
    Loan_Amount_Band_Key  TINYINT       NOT NULL,
    Risk_Band_Key         TINYINT       NOT NULL,
    Loan_Amount           DECIMAL(18,2) NOT NULL,
    Funded_Amount         DECIMAL(18,2) NOT NULL,
    Installment           DECIMAL(18,2) NOT NULL,
    Interest_Rate         DECIMAL(9,2)  NOT NULL,
    Annual_Income         DECIMAL(18,2) NULL,
    DTI                   DECIMAL(9,2)  NULL,
    Total_Payment         DECIMAL(18,2) NOT NULL,
    Total_Rec_Principal   DECIMAL(18,2) NOT NULL,
    Total_Rec_Interest    DECIMAL(18,2) NOT NULL,
    Total_Rec_Late_Fee    DECIMAL(18,2) NOT NULL,
    Recoveries            DECIMAL(18,2) NOT NULL,
    Out_Principal         DECIMAL(18,2) NOT NULL,
    Last_Payment_Amount   DECIMAL(18,2) NOT NULL,
    FICO_Low              INT           NULL,
    FICO_High             INT           NULL,
    Delinq_2yrs           SMALLINT      NULL,
    Inq_Last_6mths        SMALLINT      NULL,
    Open_Acc              SMALLINT      NULL,
    Pub_Rec               SMALLINT      NULL,
    Revol_Bal             DECIMAL(18,2) NULL,
    Revol_Util            DECIMAL(9,2)  NULL,
    Credit_History_Years  SMALLINT      NULL,
    Last_Payment_Date     DATE          NULL,
    Is_Matured            BIT           NOT NULL,
    Is_Income_Outlier     BIT           NOT NULL,
    Is_Possible_Duplicate BIT           NOT NULL,
    CONSTRAINT PK_fact_Loans PRIMARY KEY CLUSTERED (Loan_ID),
    CONSTRAINT CK_Loans_Funded   CHECK (Funded_Amount > 0),
    CONSTRAINT CK_Loans_Rate     CHECK (Interest_Rate > 0 AND Interest_Rate < 100)
);
GO

INSERT INTO fact.Loans WITH (TABLOCK) (
    Loan_ID, Issue_Date_Key, Loan_Status_Key, Grade_Key, Purpose_Key, Home_Ownership_Key, Term_Key,
    Verification_Key, Application_Type_Key, Emp_Length_Key, Geography_Key,
    DTI_Band_Key, Income_Band_Key, Loan_Amount_Band_Key, Risk_Band_Key,
    Loan_Amount, Funded_Amount, Installment, Interest_Rate, Annual_Income, DTI,
    Total_Payment, Total_Rec_Principal, Total_Rec_Interest, Total_Rec_Late_Fee, Recoveries,
    Out_Principal, Last_Payment_Amount, FICO_Low, FICO_High, Delinq_2yrs, Inq_Last_6mths,
    Open_Acc, Pub_Rec, Revol_Bal, Revol_Util, Credit_History_Years, Last_Payment_Date,
    Is_Matured, Is_Income_Outlier, Is_Possible_Duplicate)
SELECT
    Loan_ID, Issue_Date_Key, Loan_Status_Key, Grade_Key, Purpose_Key, Home_Ownership_Key, Term_Key,
    Verification_Key, Application_Type_Key, Emp_Length_Key, Geography_Key,
    DTI_Band_Key, Income_Band_Key, Loan_Amount_Band_Key, Risk_Band_Key,
    Loan_Amount, Funded_Amount, Installment, Interest_Rate, Annual_Income, DTI,
    Total_Payment, Total_Rec_Principal, Total_Rec_Interest, Total_Rec_Late_Fee, Recoveries,
    Out_Principal, Last_Payment_Amount, FICO_Low, FICO_High, Delinq_2yrs, Inq_Last_6mths,
    Open_Acc, Pub_Rec, Revol_Bal, Revol_Util, Credit_History_Years, Last_Payment_Date,
    Is_Matured, Is_Income_Outlier, Is_Possible_Duplicate
FROM audit.v_Fact_Loans_Source;
GO

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* ---------- 4. Foreign keys (after the load; WITH CHECK validates every row) ---------- */
ALTER TABLE fact.Loans WITH CHECK ADD CONSTRAINT FK_Loans_IssueDate    FOREIGN KEY (Issue_Date_Key)       REFERENCES dim.Date(Date_Key);
ALTER TABLE fact.Loans WITH CHECK ADD CONSTRAINT FK_Loans_Status       FOREIGN KEY (Loan_Status_Key)      REFERENCES dim.Loan_Status(Loan_Status_Key);
ALTER TABLE fact.Loans WITH CHECK ADD CONSTRAINT FK_Loans_Grade        FOREIGN KEY (Grade_Key)            REFERENCES dim.Grade(Grade_Key);
ALTER TABLE fact.Loans WITH CHECK ADD CONSTRAINT FK_Loans_Purpose      FOREIGN KEY (Purpose_Key)          REFERENCES dim.Purpose(Purpose_Key);
ALTER TABLE fact.Loans WITH CHECK ADD CONSTRAINT FK_Loans_Home         FOREIGN KEY (Home_Ownership_Key)   REFERENCES dim.Home_Ownership(Home_Ownership_Key);
ALTER TABLE fact.Loans WITH CHECK ADD CONSTRAINT FK_Loans_Term         FOREIGN KEY (Term_Key)             REFERENCES dim.Term(Term_Key);
ALTER TABLE fact.Loans WITH CHECK ADD CONSTRAINT FK_Loans_Verification FOREIGN KEY (Verification_Key)     REFERENCES dim.Verification_Status(Verification_Key);
ALTER TABLE fact.Loans WITH CHECK ADD CONSTRAINT FK_Loans_AppType      FOREIGN KEY (Application_Type_Key) REFERENCES dim.Application_Type(Application_Type_Key);
ALTER TABLE fact.Loans WITH CHECK ADD CONSTRAINT FK_Loans_EmpLength    FOREIGN KEY (Emp_Length_Key)       REFERENCES dim.Employment_Length(Emp_Length_Key);
ALTER TABLE fact.Loans WITH CHECK ADD CONSTRAINT FK_Loans_Geography    FOREIGN KEY (Geography_Key)        REFERENCES dim.Geography(Geography_Key);
ALTER TABLE fact.Loans WITH CHECK ADD CONSTRAINT FK_Loans_DTIBand      FOREIGN KEY (DTI_Band_Key)         REFERENCES ref.DTI_Band(Band_Key);
ALTER TABLE fact.Loans WITH CHECK ADD CONSTRAINT FK_Loans_IncomeBand   FOREIGN KEY (Income_Band_Key)      REFERENCES ref.Income_Band(Band_Key);
ALTER TABLE fact.Loans WITH CHECK ADD CONSTRAINT FK_Loans_AmountBand   FOREIGN KEY (Loan_Amount_Band_Key) REFERENCES ref.Loan_Amount_Band(Band_Key);
ALTER TABLE fact.Loans WITH CHECK ADD CONSTRAINT FK_Loans_RiskBand     FOREIGN KEY (Risk_Band_Key)        REFERENCES ref.Risk_Band(Band_Key);
GO

/* ======================================================================== VALIDATION ======================================================================== */

-- FL1. Row count and key uniqueness (expect 2,260,668 / 2,260,668)
SELECT COUNT_BIG(*) AS fact_rows, COUNT_BIG(DISTINCT Loan_ID) AS distinct_loans FROM fact.Loans;

-- FL2. Money reconciliation with staging (the funded total must equal 34,004,208,600.00)
SELECT
  (SELECT SUM(Funded_Amount) FROM fact.Loans) AS fact_funded,
  (SELECT SUM(ROUND(TRY_CAST(funded_amnt AS FLOAT),2)) FROM audit.v_Accepted_Loans) AS staging_funded,
  (SELECT SUM(Total_Payment) FROM fact.Loans) AS fact_received,
  (SELECT SUM(ROUND(TRY_CAST(total_pymnt AS FLOAT),2)) FROM audit.v_Accepted_Loans) AS staging_received;

-- FL3. Class split and money by class (compare with V2 and V3 from Phase 5)
SELECT ls.Loan_Class, COUNT_BIG(*) AS loans,
       SUM(f.Funded_Amount) AS funded, SUM(f.Total_Payment) AS received
FROM fact.Loans f JOIN dim.Loan_Status ls ON ls.Loan_Status_Key = f.Loan_Status_Key
GROUP BY ls.Loan_Class, ls.Class_Sort ORDER BY ls.Class_Sort;

-- FL4. NULL rules and flags
SELECT
  SUM(CASE WHEN Annual_Income IS NULL THEN 1 ELSE 0 END)     AS income_null,
  SUM(CASE WHEN DTI IS NULL THEN 1 ELSE 0 END)               AS dti_null,
  SUM(CAST(Is_Income_Outlier AS INT))                         AS income_outliers,
  SUM(CAST(Is_Possible_Duplicate AS INT))                     AS possible_duplicates,
  SUM(CAST(Is_Matured AS INT))                                AS matured_loans
FROM fact.Loans;

-- FL5. DTI band distribution (compare with the Step 4 DTI distribution)
SELECT b.Band_Label, COUNT_BIG(*) AS loans
FROM fact.Loans f JOIN ref.DTI_Band b ON b.Band_Key = f.DTI_Band_Key
GROUP BY b.Band_Label, b.Band_Key ORDER BY b.Band_Key;

-- FL6. Income, amount and risk bands
SELECT b.Band_Label, COUNT_BIG(*) AS loans FROM fact.Loans f JOIN ref.Income_Band b      ON b.Band_Key = f.Income_Band_Key      GROUP BY b.Band_Label, b.Band_Key ORDER BY b.Band_Key;
SELECT b.Band_Label, COUNT_BIG(*) AS loans FROM fact.Loans f JOIN ref.Loan_Amount_Band b ON b.Band_Key = f.Loan_Amount_Band_Key GROUP BY b.Band_Label, b.Band_Key ORDER BY b.Band_Key;
SELECT b.Band_Label, COUNT_BIG(*) AS loans FROM fact.Loans f JOIN ref.Risk_Band b        ON b.Band_Key = f.Risk_Band_Key        GROUP BY b.Band_Label, b.Band_Key ORDER BY b.Band_Key;

-- FL7. Money consistency on the clean table (expect 2,260,668 of 2,260,668)
SELECT COUNT_BIG(*) AS loans,
  SUM(CASE WHEN ABS(Total_Payment - (Total_Rec_Principal + Total_Rec_Interest + Total_Rec_Late_Fee + Recoveries)) <= 0.05
           THEN 1 ELSE 0 END) AS components_match
FROM fact.Loans;

-- FL8. Matured-only charge-off rate by issue year (must reproduce V4's last column)
SELECT d.[Year] AS issue_year, COUNT_BIG(*) AS loans,
       SUM(CAST(f.Is_Matured AS INT)) AS matured_loans,
       CAST(100.0 * SUM(CASE WHEN f.Is_Matured = 1 AND ls.Is_Charged_Off = 1 THEN 1 ELSE 0 END)
            / NULLIF(SUM(CAST(f.Is_Matured AS INT)), 0) AS DECIMAL(5,2)) AS chargeoff_pct_matured_only
FROM fact.Loans f
JOIN dim.Date d         ON d.Date_Key = f.Issue_Date_Key
JOIN dim.Loan_Status ls ON ls.Loan_Status_Key = f.Loan_Status_Key
GROUP BY d.[Year] ORDER BY d.[Year];