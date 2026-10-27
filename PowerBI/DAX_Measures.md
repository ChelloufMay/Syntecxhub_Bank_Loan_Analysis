# DAX Measures: Bank Loan Analysis
 
All measures live in the `_Measures` table of the Power BI model. The `.pbix` file is not committed to this repository (too large for GitHub), so this file, together with the SQL scripts, is the written definition of the semantic model. Every measure below was validated against the SQL answer key (`SQL/08_analytical_queries.sql`, `SQL/10_dashboard_expected_values.sql`).
 
## Contents
 
1. [Model conventions](#model-conventions)
2. [Calculated columns](#calculated-columns)
3. [Core KPIs](#core-kpis)
4. [Month-to-date and month-on-month](#month-to-date-and-month-on-month)
5. [Year-on-year growth](#year-on-year-growth)
6. [Good, At Risk and Bad loans](#good-at-risk-and-bad-loans)
7. [Repayment risk (matured loans)](#repayment-risk-matured-loans)
8. [Approval analysis](#approval-analysis)
9. [Field parameters](#field-parameters)
10. [Number formats](#number-formats)
11. [Regression test](#regression-test)
---
 
## Model conventions
 
| Topic | Convention |
|---|---|
| Percent-valued columns | `Interest_Rate` and `DTI` are stored as percentages (13.09 means 13.09%). Never multiply by 100. Format with the custom string `0.00"%"`, because the built-in Percentage format multiplies by 100. |
| Month-to-date | "Today" is the last date in `dim_Date`. `dim_Date` is trimmed in Power Query to 2007-05-01 .. 2018-12-31, so MTD means December 2018 when no date filter is applied. |
| Rate and DTI MoM | Relative change (percent of the previous value), not a percentage-point difference. |
| Matured loans | Issue month + term is on or before the snapshot date 2019-03-01 (`fact_Loans[Is_Matured]`, computed in SQL). |
| Minimum volume | Charge-off rate returns blank below 500 matured loans. 2017-2018 have no matured loans, so they return blank ("not matured yet"), never 0%. |
| Two fact tables | `fact_Loans` (2,260,668 rows) and `fact_Rejected_Monthly` (778,276 rows) share five dimensions: Date, Geography, DTI band, Loan amount band, Risk band. Loan-only dimensions (grade, purpose, term, income band, home ownership, verification, application type, employment length, loan status) are not related to the rejected table. |
| Approval guard | Approval measures return blank when a loan-only filter is active, because the rejected data has no such fields. |
| Interactions | Report default is cross-filtering, not cross-highlighting. |
 
---
 
## Calculated columns
 
```DAX
-- dim_Geography (Data category: Place)
Map_Location = dim_Geography[State_Name] & ", United States"
```
 
```DAX
-- dim_Date: used by the DTI-band-by-era approval matrix
Era =
SWITCH (
    TRUE (),
    dim_Date[Year] <= 2012, "2007-2012",
    dim_Date[Year] <= 2014, "2013-2014",
    dim_Date[Year] <= 2016, "2015-2016",
    "2017-2018"
)
```
 
Date hierarchy on `dim_Date`: `Date Hierarchy` = Year > Year_Quarter > Year_Month.
 
---
 
## Core KPIs
 
```DAX
Total Loans = COUNTROWS ( fact_Loans )
 
Total Funded Amount = SUM ( fact_Loans[Funded_Amount] )
 
Total Amount Received = SUM ( fact_Loans[Total_Payment] )
 
Avg Interest Rate = AVERAGE ( fact_Loans[Interest_Rate] )
 
Avg DTI = AVERAGE ( fact_Loans[DTI] )
 
Avg Loan Funded = DIVIDE ( [Total Funded Amount], [Total Loans] )
 
Received to Funded = DIVIDE ( [Total Amount Received], [Total Funded Amount] )
 
Net Return = [Total Amount Received] - [Total Funded Amount]
```
 
`Avg DTI` ignores blanks, which matches SQL `AVG` (1,848 placeholder values were set to NULL in `fact.Loans`). Amount received includes recoveries (`total_pymnt`).
 
---
 
## Month-to-date and month-on-month
 
The previous-month measures shift the date filter back one month and then take month-to-date. Use year selections or contiguous months in slicers. Non-adjacent month selections can misbehave.
 
```DAX
MTD Loans = TOTALMTD ( [Total Loans], dim_Date[Full_Date] )
 
PMTD Loans =
CALCULATE ( [Total Loans], DATESMTD ( DATEADD ( dim_Date[Full_Date], -1, MONTH ) ) )
 
MoM Loans % = DIVIDE ( [MTD Loans] - [PMTD Loans], [PMTD Loans] )
```
 
```DAX
MTD Funded Amount = TOTALMTD ( [Total Funded Amount], dim_Date[Full_Date] )
 
PMTD Funded Amount =
CALCULATE ( [Total Funded Amount], DATESMTD ( DATEADD ( dim_Date[Full_Date], -1, MONTH ) ) )
 
MoM Funded % = DIVIDE ( [MTD Funded Amount] - [PMTD Funded Amount], [PMTD Funded Amount] )
```
 
```DAX
MTD Amount Received = TOTALMTD ( [Total Amount Received], dim_Date[Full_Date] )
 
PMTD Amount Received =
CALCULATE ( [Total Amount Received], DATESMTD ( DATEADD ( dim_Date[Full_Date], -1, MONTH ) ) )
 
MoM Received % = DIVIDE ( [MTD Amount Received] - [PMTD Amount Received], [PMTD Amount Received] )
```
 
MoM for amount received is not like-for-like: recent loans have had little time to repay (December 2018 received/funded is about 0.11).
 
```DAX
MTD Avg Interest Rate = TOTALMTD ( [Avg Interest Rate], dim_Date[Full_Date] )
 
PMTD Avg Interest Rate =
CALCULATE ( [Avg Interest Rate], DATESMTD ( DATEADD ( dim_Date[Full_Date], -1, MONTH ) ) )
 
MoM Avg Interest Rate % =
DIVIDE ( [MTD Avg Interest Rate] - [PMTD Avg Interest Rate], [PMTD Avg Interest Rate] )
```
 
```DAX
MTD Avg DTI = TOTALMTD ( [Avg DTI], dim_Date[Full_Date] )
 
PMTD Avg DTI =
CALCULATE ( [Avg DTI], DATESMTD ( DATEADD ( dim_Date[Full_Date], -1, MONTH ) ) )
 
MoM Avg DTI % = DIVIDE ( [MTD Avg DTI] - [PMTD Avg DTI], [PMTD Avg DTI] )
```
 
---
 
## Year-on-year growth
 
Totals rows are meaningless for these measures, so turn totals off in matrices. The first year in the data (2007) has no prior year and shows blank.
 
```DAX
Loans Previous Year =
CALCULATE ( [Total Loans], SAMEPERIODLASTYEAR ( dim_Date[Full_Date] ) )
 
Loans YoY % = DIVIDE ( [Total Loans] - [Loans Previous Year], [Loans Previous Year] )
 
Funded Previous Year =
CALCULATE ( [Total Funded Amount], SAMEPERIODLASTYEAR ( dim_Date[Full_Date] ) )
 
Funded YoY % =
DIVIDE ( [Total Funded Amount] - [Funded Previous Year], [Funded Previous Year] )
```
 
2007 starts in June, so 2008 growth (+296.85% loans) is inflated by the partial first year.
 
---
 
## Good, At Risk and Bad loans
 
Class rule (`ref.Loan_Status_Map`): Good = Fully Paid, Current. At Risk = In Grace Period, Late (16-30), Late (31-120). Bad = Charged Off, Default. The two legacy "Does not meet the credit policy" statuses fold into Fully Paid and Charged Off.
 
```DAX
Good Loans = CALCULATE ( [Total Loans], dim_Loan_Status[Loan_Class] = "Good" )
At Risk Loans = CALCULATE ( [Total Loans], dim_Loan_Status[Loan_Class] = "At Risk" )
Bad Loans = CALCULATE ( [Total Loans], dim_Loan_Status[Loan_Class] = "Bad" )
 
Good Loan % = DIVIDE ( [Good Loans], [Total Loans] )
At Risk Loan % = DIVIDE ( [At Risk Loans], [Total Loans] )
Bad Loan % = DIVIDE ( [Bad Loans], [Total Loans] )
```
 
```DAX
Good Loan Funded Amount =
CALCULATE ( [Total Funded Amount], dim_Loan_Status[Loan_Class] = "Good" )
 
Good Loan Amount Received =
CALCULATE ( [Total Amount Received], dim_Loan_Status[Loan_Class] = "Good" )
 
At Risk Loan Funded Amount =
CALCULATE ( [Total Funded Amount], dim_Loan_Status[Loan_Class] = "At Risk" )
 
At Risk Loan Amount Received =
CALCULATE ( [Total Amount Received], dim_Loan_Status[Loan_Class] = "At Risk" )
 
Bad Loan Funded Amount =
CALCULATE ( [Total Funded Amount], dim_Loan_Status[Loan_Class] = "Bad" )
 
Bad Loan Amount Received =
CALCULATE ( [Total Amount Received], dim_Loan_Status[Loan_Class] = "Bad" )
```
 
```DAX
-- Share of all loans, used in the class matrix (ignores the status filter on rows)
Loan Share % =
DIVIDE ( [Total Loans], CALCULATE ( [Total Loans], ALL ( dim_Loan_Status ) ) )
```
 
---
 
## Repayment risk (matured loans)
 
```DAX
Matured Loans = CALCULATE ( [Total Loans], fact_Loans[Is_Matured] = TRUE () )
 
Matured Charged-Off Loans =
CALCULATE (
    [Total Loans],
    fact_Loans[Is_Matured] = TRUE (),
    dim_Loan_Status[Is_Charged_Off] = TRUE ()
)
 
Charge-off Rate (Matured) =
VAR m = [Matured Loans]
RETURN
    IF ( m >= 500, DIVIDE ( [Matured Charged-Off Loans], m ) )
 
Matured Share % = DIVIDE ( [Matured Loans], [Total Loans] )
```
 
`Default` loans (40) are in the Bad class but are not counted as charged off, consistent with the SQL answer key.
 
---
 
## Approval analysis
 
Approval rate = accepted / (accepted + rejected). Accepted loans are dated by issue month and rejected applications by application month, so rates are approximate.
 
```DAX
Rejected Applications = SUM ( fact_Rejected_Monthly[Rejected_Count] )
 
Rejected Amount Requested = SUM ( fact_Rejected_Monthly[Amount_Requested_Sum] )
 
-- Helper (hidden): TRUE when a filter applies only to loans, which would make
-- an approval ratio mix filtered loans with unfiltered rejections
Loan-Only Filter Active =
ISCROSSFILTERED ( dim_Grade )
    || ISCROSSFILTERED ( dim_Purpose )
    || ISCROSSFILTERED ( dim_Home_Ownership )
    || ISCROSSFILTERED ( dim_Term )
    || ISCROSSFILTERED ( dim_Verification_Status )
    || ISCROSSFILTERED ( dim_Application_Type )
    || ISCROSSFILTERED ( dim_Employment_Length )
    || ISCROSSFILTERED ( dim_Income_Band )
    || ISCROSSFILTERED ( dim_Loan_Status )
    || ISFILTERED ( fact_Loans )
 
Applications Received =
IF ( [Loan-Only Filter Active], BLANK (), [Total Loans] + [Rejected Applications] )
 
-- Returns 0 (not blank) when a band has rejections but no accepted loans;
-- blank only when both are empty
Approval Rate =
IF (
    [Loan-Only Filter Active],
    BLANK (),
    VAR a = [Total Loans] + 0
    VAR r = [Rejected Applications] + 0
    RETURN
        IF ( a + r = 0, BLANK (), DIVIDE ( a, a + r ) )
)
 
-- Credit score is only reliable in the rejected file for 2007-2014
Approval Rate (2007-2014) =
CALCULATE ( [Approval Rate], KEEPFILTERS ( dim_Date[Year] <= 2014 ) )
```
 
---
 
## Field parameters
 
Created with Modeling > New parameter > Fields. Power BI generates each table and a matching slicer. The definitions below are what the generated tables contain.
 
```DAX
Select Measure =
{
    ( "Total Loans", NAMEOF ( '_Measures'[Total Loans] ), 0 ),
    ( "Total Funded Amount", NAMEOF ( '_Measures'[Total Funded Amount] ), 1 ),
    ( "Total Amount Received", NAMEOF ( '_Measures'[Total Amount Received] ), 2 )
}
```
 
```DAX
Other Factor =
{
    ( "Home Ownership", NAMEOF ( dim_Home_Ownership[Home_Ownership] ), 0 ),
    ( "Verification Status", NAMEOF ( dim_Verification_Status[Verification_Status] ), 1 ),
    ( "Application Type", NAMEOF ( dim_Application_Type[Application_Type] ), 2 ),
    ( "Term", NAMEOF ( dim_Term[Term_Label] ), 3 )
}
```
 
Both slicers are single-select. `Select Measure` drives the trend area chart and the map (Trends page). `Other Factor` drives the switchable charge-off chart (Risk & Repayment Factors page). Only nominal fields are included, so chart sorting cannot misbehave.
 
---
 
## Number formats
 
| Measures | Format |
|---|---|
| `Total Loans`, `MTD Loans`, `PMTD Loans`, `Loans Previous Year`, `Good Loans`, `At Risk Loans`, `Bad Loans`, `Matured Loans`, `Matured Charged-Off Loans`, `Rejected Applications`, `Applications Received` | Whole number, thousands separator |
| `Total Funded Amount`, `Total Amount Received`, `Avg Loan Funded`, `Net Return`, `MTD/PMTD Funded Amount`, `MTD/PMTD Amount Received`, `Funded Previous Year`, all class funded and received amounts, `Rejected Amount Requested` | Currency `$`, 2 decimals (display units on dashboard cards) |
| `Avg Interest Rate`, `Avg DTI`, `MTD/PMTD Avg Interest Rate`, `MTD/PMTD Avg DTI` | Custom `0.00"%"` |
| `MoM ... %` measures, `Loans YoY %`, `Funded YoY %`, `Good/At Risk/Bad Loan %`, `Loan Share %`, `Charge-off Rate (Matured)`, `Approval Rate`, `Approval Rate (2007-2014)` | Percentage, 2 decimals |
| `Matured Share %` | Percentage, 1 decimal |
| `Received to Funded` | Decimal, 3 places |
 
Column formats: `Funded_Amount`, `Loan_Amount`, `Installment`, `Total_Payment` as currency; `Interest_Rate` and `DTI` as `0.00"%"`; `Loan_ID` as whole number with the thousands separator off.
 
---
 
## Regression test
 
Paste into DAX query view (the measures already exist in the model, so no `DEFINE` is needed) with no slicers applied. The values must match the table below. If any differ after changing the model, a relationship, filter or formula was altered.
 
```DAX
EVALUATE
ROW (
    "Total Loans", [Total Loans],
    "Total Funded Amount", [Total Funded Amount],
    "Total Amount Received", [Total Amount Received],
    "Avg Interest Rate", [Avg Interest Rate],
    "Avg DTI", [Avg DTI],
    "MTD Loans", [MTD Loans],
    "PMTD Loans", [PMTD Loans],
    "MoM Loans %", [MoM Loans %],
    "MoM Avg Interest Rate %", [MoM Avg Interest Rate %],
    "MoM Avg DTI %", [MoM Avg DTI %],
    "Good Loans", [Good Loans],
    "At Risk Loans", [At Risk Loans],
    "Bad Loans", [Bad Loans],
    "Matured Loans", [Matured Loans],
    "Matured Charged-Off Loans", [Matured Charged-Off Loans],
    "Charge-off Rate (Matured)", [Charge-off Rate (Matured)],
    "Rejected Applications", [Rejected Applications],
    "Approval Rate", [Approval Rate]
)
```
 
| Measure | Expected (no slicers) |
|---|---|
| Total Loans | 2,260,668 |
| Total Funded Amount | 34,004,208,600.00 |
| Total Amount Received | 27,314,649,581.58 |
| Avg Interest Rate | 13.09 |
| Avg DTI | 18.77 |
| MTD Loans / PMTD Loans | 40,134 / 41,973 |
| MoM Loans % | -4.38% |
| MoM Avg Interest Rate % | -0.77% |
| MoM Avg DTI % | -1.28% |
| Good / At Risk / Bad Loans | 1,957,056 / 34,252 / 269,360 |
| Matured Loans / Matured Charged-Off Loans | 785,915 / 118,371 |
| Charge-off Rate (Matured) | 15.06% |
| Rejected Applications | 27,648,741 |
| Approval Rate | 7.56% |
 
Filter tests: Grade A + California returns 62,451 loans, 940,682,700.00 funded and 704,839,842.26 received. Approval Rate is blank under any Grade filter. Year 2018 shows Approval Rate 4.96% and a blank charge-off rate. Year 2013 shows 15.05% and 15.59%.
 