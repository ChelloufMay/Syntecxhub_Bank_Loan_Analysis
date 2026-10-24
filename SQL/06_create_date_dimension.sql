-- 06_create_date_dimension.sql
USE Syntecxhub_Bank_Loan_Analysis;
GO

DROP TABLE IF EXISTS dim.Date;
CREATE TABLE dim.Date (
    Date_Key        INT         NOT NULL PRIMARY KEY,   -- YYYYMMDD
    Full_Date       DATE        NOT NULL UNIQUE,
    [Year]          SMALLINT    NOT NULL,
    [Quarter]       TINYINT     NOT NULL,
    Year_Quarter    CHAR(7)     NOT NULL,               -- 2015-Q3
    Month_Number    TINYINT     NOT NULL,
    Month_Name      VARCHAR(10) NOT NULL,
    Month_Short     CHAR(3)     NOT NULL,
    Year_Month      CHAR(7)     NOT NULL,               -- 2015-09
    Month_Sort      INT         NOT NULL,               -- 201509
    Month_Start     DATE        NOT NULL,
    Day_Number      TINYINT     NOT NULL,
    Day_Name        VARCHAR(10) NOT NULL,
    Week_Number     TINYINT     NOT NULL,
    Is_Weekend      BIT         NOT NULL,
    Is_Month_Start  BIT         NOT NULL
);

;WITH d AS (
    SELECT CAST('2007-01-01' AS DATE) AS dt
    UNION ALL
    SELECT DATEADD(DAY, 1, dt) FROM d WHERE dt < '2019-12-31'
)
INSERT INTO dim.Date
SELECT
    YEAR(dt) * 10000 + MONTH(dt) * 100 + DAY(dt),
    dt,
    YEAR(dt),
    DATEPART(QUARTER, dt),
    CAST(YEAR(dt) AS CHAR(4)) + '-Q' + CAST(DATEPART(QUARTER, dt) AS CHAR(1)),
    MONTH(dt),
    DATENAME(MONTH, dt),
    LEFT(DATENAME(MONTH, dt), 3),
    CAST(YEAR(dt) AS CHAR(4)) + '-' + RIGHT('0' + CAST(MONTH(dt) AS VARCHAR(2)), 2),
    YEAR(dt) * 100 + MONTH(dt),
    DATEFROMPARTS(YEAR(dt), MONTH(dt), 1),
    DAY(dt),
    DATENAME(WEEKDAY, dt),
    DATEPART(WEEK, dt),
    CASE WHEN DATEDIFF(DAY, '19000106', dt) % 7 < 2 THEN 1 ELSE 0 END,   -- 1900-01-06 was a Saturday
    CASE WHEN DAY(dt) = 1 THEN 1 ELSE 0 END
FROM d
OPTION (MAXRECURSION 0);
GO

/* ======================================================================== VALIDATION ======================================================================== */

-- DT1. Row count and range (4748 rows, 2007-01-01 to 2019-12-31, no gaps)
SELECT COUNT(*) AS date_rows,
       MIN(Full_Date) AS first_date,
       MAX(Full_Date) AS last_date,
       DATEDIFF(DAY, MIN(Full_Date), MAX(Full_Date)) + 1 AS expected_rows
FROM dim.Date;


-- DT2. Spot checks (2007-01-06 = Saturday/weekend 1; 2008-02-29 exists; 2019-03-01 = Friday)
SELECT Full_Date, Day_Name, Is_Weekend, Month_Name, Year_Quarter, Year_Month
FROM dim.Date
WHERE Full_Date IN ('2007-01-06', '2008-02-29', '2019-03-01');


-- DT3. Every accepted-loan issue month exists in the table (expect 0 unmatched)
SELECT COUNT_BIG(*) AS issue_dates_unmatched
FROM audit.v_Accepted_Loans a
LEFT JOIN dim.Date d
  ON d.Full_Date = TRY_CONVERT(date, '01 ' + REPLACE(a.issue_d, '-', ' '), 106)
WHERE d.Date_Key IS NULL;


-- DT4. Every distinct rejected application date exists (expect 0 unmatched)
SELECT COUNT(*) AS distinct_app_dates,
       SUM(CASE WHEN d.Date_Key IS NULL THEN 1 ELSE 0 END) AS app_dates_unmatched
FROM (SELECT DISTINCT TRY_CONVERT(date, Application_Date) AS dt FROM stg.Rejected_Raw) x
LEFT JOIN dim.Date d ON d.Full_Date = x.dt;


-- DT5. Weekend count sanity (about 2/7 of days)
SELECT SUM(CAST(Is_Weekend AS INT)) AS weekend_days, COUNT(*) AS total_days,
       CAST(100.0 * SUM(CAST(Is_Weekend AS INT)) / COUNT(*) AS DECIMAL(5,2)) AS weekend_pct
FROM dim.Date;