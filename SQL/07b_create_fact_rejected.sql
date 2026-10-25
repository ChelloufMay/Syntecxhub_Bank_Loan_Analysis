-- 07b_create_fact_rejected.sql
USE Syntecxhub_Bank_Loan_Analysis;
GO

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/* 1. Source view: all cleaning and lookups in one place */
CREATE OR ALTER VIEW audit.v_Fact_Rejected_Source AS
SELECT
    TRY_CAST(LEFT(r.Application_Date, 4) AS INT)   AS App_Year,
    dd.Date_Key                                    AS Application_Date_Key,
    geo.Geography_Key,
    el.Emp_Length_Key,
    CAST(COALESCE(bd.Band_Key, 6) AS TINYINT)      AS DTI_Band_Key,
    CAST(COALESCE(ba.Band_Key, 7) AS TINYINT)      AS Loan_Amount_Band_Key,
    CAST(COALESCE(br.Band_Key, 6) AS TINYINT)      AS Risk_Band_Key,
    x.amt                                          AS Amount_Requested,
    x.dti                                          AS DTI,
    CAST(x.risk AS SMALLINT)                       AS Risk_Score
FROM stg.Rejected_Raw r
CROSS JOIN (
    SELECT CAST(MAX(CASE WHEN Config_Key='DTI_Invalid_From' THEN Config_Value END) AS DECIMAL(9,2)) AS DTI_Invalid_From,
           CAST(MAX(CASE WHEN Config_Key='Risk_Score_Min'   THEN Config_Value END) AS DECIMAL(9,2)) AS Risk_Score_Min,
           CAST(MAX(CASE WHEN Config_Key='Risk_Score_Max'   THEN Config_Value END) AS DECIMAL(9,2)) AS Risk_Score_Max
    FROM ref.Config) cfg
CROSS APPLY (SELECT
    ROUND(TRY_CAST(NULLIF(LTRIM(RTRIM(r.Amount_Requested)),'') AS FLOAT), 2)                              AS amt_raw,
    ROUND(TRY_CAST(REPLACE(NULLIF(LTRIM(RTRIM(r.Debt_To_Income_Ratio)),''), '%', '') AS FLOAT), 2)         AS dti_raw,
    TRY_CAST(NULLIF(LTRIM(RTRIM(r.Risk_Score)),'') AS FLOAT)                                               AS risk_raw
) p
CROSS APPLY (SELECT
    CAST(NULLIF(p.amt_raw, 0) AS DECIMAL(18,2)) AS amt,
    CASE WHEN p.dti_raw < 0 OR p.dti_raw >= cfg.DTI_Invalid_From THEN NULL
         ELSE CAST(p.dti_raw AS DECIMAL(9,2)) END AS dti,
    CASE WHEN p.risk_raw < cfg.Risk_Score_Min OR p.risk_raw > cfg.Risk_Score_Max THEN NULL
         ELSE CAST(ROUND(p.risk_raw, 0) AS DECIMAL(9,2)) END AS risk
) x
LEFT JOIN dim.Date dd              ON dd.Full_Date = TRY_CONVERT(date, r.Application_Date)
LEFT JOIN dim.Geography geo        ON geo.State_Code = COALESCE(NULLIF(LTRIM(RTRIM(r.State)),''), 'XX')
LEFT JOIN dim.Employment_Length el ON el.Emp_Length_Label = COALESCE(NULLIF(LTRIM(RTRIM(r.Employment_Length)),''), 'Unknown')
LEFT JOIN ref.DTI_Band bd          ON x.dti  >= bd.Lower_Bound AND x.dti  < bd.Upper_Bound
LEFT JOIN ref.Loan_Amount_Band ba  ON x.amt  >= ba.Lower_Bound AND x.amt  < ba.Upper_Bound
LEFT JOIN ref.Risk_Band br         ON x.risk >= br.Lower_Bound AND x.risk < br.Upper_Bound;
GO

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/*  2. ORPHAN CHECK source_rows must be 27,648,741 and every other column 0. */
SELECT COUNT_BIG(*) AS source_rows,
  SUM(CASE WHEN App_Year             IS NULL THEN 1 ELSE 0 END) AS year_missing,
  SUM(CASE WHEN Application_Date_Key IS NULL THEN 1 ELSE 0 END) AS date_missing,
  SUM(CASE WHEN Geography_Key        IS NULL THEN 1 ELSE 0 END) AS geography_missing,
  SUM(CASE WHEN Emp_Length_Key       IS NULL THEN 1 ELSE 0 END) AS emp_missing
FROM audit.v_Fact_Rejected_Source;
GO

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/*  3. Create the detail fact table  */
DROP TABLE IF EXISTS fact.Rejected_Applications;
CREATE TABLE fact.Rejected_Applications (
    Rejected_ID          BIGINT IDENTITY(1,1) NOT NULL,
    Application_Date_Key INT           NOT NULL,
    Geography_Key        INT           NOT NULL,
    Emp_Length_Key       INT           NOT NULL,
    DTI_Band_Key         TINYINT       NOT NULL,
    Loan_Amount_Band_Key TINYINT       NOT NULL,
    Risk_Band_Key        TINYINT       NOT NULL,
    Amount_Requested     DECIMAL(18,2) NULL,
    DTI                  DECIMAL(9,2)  NULL,
    Risk_Score           SMALLINT      NULL,
    CONSTRAINT PK_fact_Rejected PRIMARY KEY CLUSTERED (Rejected_ID)
) WITH (DATA_COMPRESSION = PAGE);
GO

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/*  4. Load one application year at a time  */
DECLARE @y INT = 2007;
WHILE @y <= 2018
BEGIN
    INSERT INTO fact.Rejected_Applications WITH (TABLOCK)
        (Application_Date_Key, Geography_Key, Emp_Length_Key, DTI_Band_Key,
         Loan_Amount_Band_Key, Risk_Band_Key, Amount_Requested, DTI, Risk_Score)
    SELECT Application_Date_Key, Geography_Key, Emp_Length_Key, DTI_Band_Key,
           Loan_Amount_Band_Key, Risk_Band_Key, Amount_Requested, DTI, Risk_Score
    FROM audit.v_Fact_Rejected_Source
    WHERE App_Year = @y;

    RAISERROR('Loaded application year %d', 0, 1, @y) WITH NOWAIT;
    SET @y += 1;
END;
GO

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/*  5. Foreign keys   */
ALTER TABLE fact.Rejected_Applications WITH CHECK ADD CONSTRAINT FK_Rej_Date      FOREIGN KEY (Application_Date_Key) REFERENCES dim.Date(Date_Key);
ALTER TABLE fact.Rejected_Applications WITH CHECK ADD CONSTRAINT FK_Rej_Geography FOREIGN KEY (Geography_Key)        REFERENCES dim.Geography(Geography_Key);
ALTER TABLE fact.Rejected_Applications WITH CHECK ADD CONSTRAINT FK_Rej_EmpLength FOREIGN KEY (Emp_Length_Key)       REFERENCES dim.Employment_Length(Emp_Length_Key);
ALTER TABLE fact.Rejected_Applications WITH CHECK ADD CONSTRAINT FK_Rej_DTIBand   FOREIGN KEY (DTI_Band_Key)         REFERENCES ref.DTI_Band(Band_Key);
ALTER TABLE fact.Rejected_Applications WITH CHECK ADD CONSTRAINT FK_Rej_AmtBand   FOREIGN KEY (Loan_Amount_Band_Key) REFERENCES ref.Loan_Amount_Band(Band_Key);
ALTER TABLE fact.Rejected_Applications WITH CHECK ADD CONSTRAINT FK_Rej_RiskBand  FOREIGN KEY (Risk_Band_Key)        REFERENCES ref.Risk_Band(Band_Key);
GO

/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
/*  6. Monthly aggregate for Power BI  */
DROP TABLE IF EXISTS fact.Rejected_Monthly;
CREATE TABLE fact.Rejected_Monthly (
    Month_Date_Key       INT           NOT NULL,   -- Date_Key of the 1st day of the month
    Geography_Key        INT           NOT NULL,
    DTI_Band_Key         TINYINT       NOT NULL,
    Loan_Amount_Band_Key TINYINT       NOT NULL,
    Risk_Band_Key        TINYINT       NOT NULL,
    Rejected_Count       INT           NOT NULL,
    Amount_Requested_Sum DECIMAL(18,2) NOT NULL,
    CONSTRAINT PK_fact_Rejected_Monthly PRIMARY KEY CLUSTERED
        (Month_Date_Key, Geography_Key, DTI_Band_Key, Loan_Amount_Band_Key, Risk_Band_Key)
);
GO

INSERT INTO fact.Rejected_Monthly
SELECT dm.Date_Key, f.Geography_Key, f.DTI_Band_Key, f.Loan_Amount_Band_Key, f.Risk_Band_Key,
       CAST(COUNT_BIG(*) AS INT),
       ISNULL(SUM(f.Amount_Requested), 0)
FROM fact.Rejected_Applications f
JOIN dim.Date d  ON d.Date_Key  = f.Application_Date_Key
JOIN dim.Date dm ON dm.Full_Date = d.Month_Start
GROUP BY dm.Date_Key, f.Geography_Key, f.DTI_Band_Key, f.Loan_Amount_Band_Key, f.Risk_Band_Key;
GO

ALTER TABLE fact.Rejected_Monthly WITH CHECK ADD CONSTRAINT FK_RejM_Date      FOREIGN KEY (Month_Date_Key)       REFERENCES dim.Date(Date_Key);
ALTER TABLE fact.Rejected_Monthly WITH CHECK ADD CONSTRAINT FK_RejM_Geography FOREIGN KEY (Geography_Key)        REFERENCES dim.Geography(Geography_Key);
ALTER TABLE fact.Rejected_Monthly WITH CHECK ADD CONSTRAINT FK_RejM_DTIBand   FOREIGN KEY (DTI_Band_Key)         REFERENCES ref.DTI_Band(Band_Key);
ALTER TABLE fact.Rejected_Monthly WITH CHECK ADD CONSTRAINT FK_RejM_AmtBand   FOREIGN KEY (Loan_Amount_Band_Key) REFERENCES ref.Loan_Amount_Band(Band_Key);
ALTER TABLE fact.Rejected_Monthly WITH CHECK ADD CONSTRAINT FK_RejM_RiskBand  FOREIGN KEY (Risk_Band_Key)        REFERENCES ref.Risk_Band(Band_Key);
GO

/* ======================================================================== VALIDATION ======================================================================== */

-- RF1. Row count and the cleaning rules (expected values in the comments)
SELECT COUNT_BIG(*) AS rejected_rows,                                                    -- 27,648,741
  SUM(CASE WHEN f.Amount_Requested IS NULL THEN 1 ELSE 0 END) AS amount_null,            -- 1,288
  SUM(CASE WHEN f.DTI IS NULL THEN 1 ELSE 0 END)              AS dti_null,               -- 1,372,321
  SUM(CASE WHEN f.DTI = 100 THEN 1 ELSE 0 END)                AS dti_exactly_100,        -- 1,362,556
  SUM(CASE WHEN f.Risk_Score IS NULL THEN 1 ELSE 0 END)       AS risk_null,              -- 18,613,385
  SUM(CASE WHEN f.Geography_Key = k.unk_geo THEN 1 ELSE 0 END) AS state_unknown,         -- 22
  SUM(CASE WHEN f.Emp_Length_Key = k.unk_emp THEN 1 ELSE 0 END) AS emp_unknown           -- 951,355
FROM fact.Rejected_Applications f
CROSS JOIN (SELECT
    (SELECT Geography_Key FROM dim.Geography WHERE State_Code = 'XX')                      AS unk_geo,
    (SELECT Emp_Length_Key FROM dim.Employment_Length WHERE Emp_Length_Label = 'Unknown')  AS unk_emp) k;


-- RF2. Rows per year must equal the staging counts from R2
SELECT d.[Year] AS app_year, COUNT_BIG(*) AS fact_rows, e.expected_rows,
       COUNT_BIG(*) - e.expected_rows AS difference
FROM fact.Rejected_Applications f
JOIN dim.Date d ON d.Date_Key = f.Application_Date_Key
JOIN (VALUES (2007,5274),(2008,25596),(2009,56991),(2010,112561),(2011,217792),(2012,337277),
             (2013,760942),(2014,1933700),(2015,2859379),(2016,4769874),(2017,7072573),(2018,9496782)
     ) e(yr, expected_rows) ON e.yr = d.[Year]
GROUP BY d.[Year], e.expected_rows ORDER BY d.[Year];


-- RF3. Aggregate reconciliation with the detail table
SELECT
  (SELECT COUNT_BIG(*) FROM fact.Rejected_Monthly)                         AS aggregate_rows,
  (SELECT SUM(CAST(Rejected_Count AS BIGINT)) FROM fact.Rejected_Monthly)  AS aggregate_count,      -- 27,648,741
  (SELECT SUM(Amount_Requested_Sum) FROM fact.Rejected_Monthly)            AS aggregate_amount,
  (SELECT SUM(Amount_Requested) FROM fact.Rejected_Applications)           AS detail_amount;        -- must equal aggregate_amount


-- RF4. Approval rate by year from the fact tables (must reproduce C1 from Phase 4)
WITH a AS (SELECT d.[Year] AS yr, COUNT_BIG(*) AS accepted
           FROM fact.Loans f JOIN dim.Date d ON d.Date_Key = f.Issue_Date_Key GROUP BY d.[Year]),
     r AS (SELECT d.[Year] AS yr, SUM(CAST(m.Rejected_Count AS BIGINT)) AS rejected
           FROM fact.Rejected_Monthly m JOIN dim.Date d ON d.Date_Key = m.Month_Date_Key GROUP BY d.[Year])
SELECT a.yr, a.accepted, r.rejected,
       CAST(100.0 * a.accepted / (a.accepted + r.rejected) AS DECIMAL(5,2)) AS approval_rate_pct
FROM a JOIN r ON r.yr = a.yr ORDER BY a.yr;


-- RF5. First factor analysis: approval rate by DTI band (all years)
SELECT b.Band_Label, a.accepted, r.rejected,
       CAST(100.0 * a.accepted / NULLIF(a.accepted + r.rejected, 0) AS DECIMAL(5,2)) AS approval_rate_pct
FROM ref.DTI_Band b
LEFT JOIN (SELECT DTI_Band_Key, COUNT_BIG(*) AS accepted FROM fact.Loans GROUP BY DTI_Band_Key) a
       ON a.DTI_Band_Key = b.Band_Key
LEFT JOIN (SELECT DTI_Band_Key, SUM(CAST(Rejected_Count AS BIGINT)) AS rejected
           FROM fact.Rejected_Monthly GROUP BY DTI_Band_Key) r
       ON r.DTI_Band_Key = b.Band_Key
ORDER BY b.Band_Key;


-- RF6. Approval rate by risk band, application years 2007-2014 only (the years where Risk_Score is usable)
SELECT b.Band_Label, a.accepted, r.rejected,
       CAST(100.0 * a.accepted / NULLIF(a.accepted + r.rejected, 0) AS DECIMAL(5,2)) AS approval_rate_pct
FROM ref.Risk_Band b
LEFT JOIN (SELECT f.Risk_Band_Key, COUNT_BIG(*) AS accepted
           FROM fact.Loans f JOIN dim.Date d ON d.Date_Key = f.Issue_Date_Key
           WHERE d.[Year] BETWEEN 2007 AND 2014 GROUP BY f.Risk_Band_Key) a ON a.Risk_Band_Key = b.Band_Key
LEFT JOIN (SELECT m.Risk_Band_Key, SUM(CAST(m.Rejected_Count AS BIGINT)) AS rejected
           FROM fact.Rejected_Monthly m JOIN dim.Date d ON d.Date_Key = m.Month_Date_Key
           WHERE d.[Year] BETWEEN 2007 AND 2014 GROUP BY m.Risk_Band_Key) r ON r.Risk_Band_Key = b.Band_Key
ORDER BY b.Band_Key;


-- RF7. Database size (must stay well under 50 GB)
EXEC sp_spaceused;