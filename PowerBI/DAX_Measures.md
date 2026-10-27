# DAX Measures: Bank Loan Analysis

All measures are stored in the `_Measures` table of `Bank_Loan_Analysis.pbix`.
Interest rate and DTI are stored as percentages in SQL (13.09 = 13.09%), so none of
these measures multiply by 100.

## Conventions
- "MTD" is the latest month in the current filter context (December 2018 with no date slicer).
- MoM % for rate and DTI is a relative change, not a percentage-point difference.
- `Charge-off Rate (Matured)` uses matured loans only and returns blank below 500 matured loans.
- `Approval Rate` returns blank when a loan-only filter (grade, purpose, term and so on) is active.

## Measures
```DAX
DEFINE
    MEASURE '_Measures'[Total Loans] = COUNTROWS ( fact_Loans )
    MEASURE '_Measures'[Total Funded Amount] = SUM ( fact_Loans[Funded_Amount] )
    MEASURE '_Measures'[Total Amount Received] = SUM ( fact_Loans[Total_Payment] )
    MEASURE '_Measures'[Avg Interest Rate] = AVERAGE ( fact_Loans[Interest_Rate] )
    MEASURE '_Measures'[Avg DTI] = AVERAGE ( fact_Loans[DTI] )
    MEASURE '_Measures'[Avg Loan Funded] = DIVIDE ( [Total Funded Amount], [Total Loans] )
    MEASURE '_Measures'[Received to Funded] = DIVIDE ( [Total Amount Received], [Total Funded Amount] )
    MEASURE '_Measures'[Net Return] = [Total Amount Received] - [Total Funded Amount]
    MEASURE '_Measures'[MTD Loans] = TOTALMTD ( [Total Loans], dim_Date[Full_Date] )
    MEASURE '_Measures'[PMTD Loans] = CALCULATE ( [Total Loans], DATESMTD ( DATEADD ( dim_Date[Full_Date], -1, MONTH ) ) )
    MEASURE '_Measures'[MoM Loans %] = DIVIDE ( [MTD Loans] - [PMTD Loans], [PMTD Loans] )
    MEASURE '_Measures'[MTD Funded Amount] = TOTALMTD ( [Total Funded Amount], dim_Date[Full_Date] )
    MEASURE '_Measures'[PMTD Funded Amount] = CALCULATE ( [Total Funded Amount], DATESMTD ( DATEADD ( dim_Date[Full_Date], -1, MONTH ) ) )
    MEASURE '_Measures'[MoM Funded %] = DIVIDE ( [MTD Funded Amount] - [PMTD Funded Amount], [PMTD Funded Amount] )
    MEASURE '_Measures'[MTD Amount Received] = TOTALMTD ( [Total Amount Received], dim_Date[Full_Date] )
    MEASURE '_Measures'[PMTD Amount Received] = CALCULATE ( [Total Amount Received], DATESMTD ( DATEADD ( dim_Date[Full_Date], -1, MONTH ) ) )
    MEASURE '_Measures'[MoM Received %] = DIVIDE ( [MTD Amount Received] - [PMTD Amount Received], [PMTD Amount Received] )
    MEASURE '_Measures'[MTD Avg Interest Rate] = TOTALMTD ( [Avg Interest Rate], dim_Date[Full_Date] )
    MEASURE '_Measures'[PMTD Avg Interest Rate] = CALCULATE ( [Avg Interest Rate], DATESMTD ( DATEADD ( dim_Date[Full_Date], -1, MONTH ) ) )
    MEASURE '_Measures'[MoM Avg Interest Rate %] = DIVIDE ( [MTD Avg Interest Rate] - [PMTD Avg Interest Rate], [PMTD Avg Interest Rate] )
    MEASURE '_Measures'[MTD Avg DTI] = TOTALMTD ( [Avg DTI], dim_Date[Full_Date] )
    MEASURE '_Measures'[PMTD Avg DTI] = CALCULATE ( [Avg DTI], DATESMTD ( DATEADD ( dim_Date[Full_Date], -1, MONTH ) ) )
    MEASURE '_Measures'[MoM Avg DTI %] = DIVIDE ( [MTD Avg DTI] - [PMTD Avg DTI], [PMTD Avg DTI] )
    MEASURE '_Measures'[Good Loans] = CALCULATE ( [Total Loans], dim_Loan_Status[Loan_Class] = "Good" )
    MEASURE '_Measures'[At Risk Loans] = CALCULATE ( [Total Loans], dim_Loan_Status[Loan_Class] = "At Risk" )
    MEASURE '_Measures'[Bad Loans] = CALCULATE ( [Total Loans], dim_Loan_Status[Loan_Class] = "Bad" )
    MEASURE '_Measures'[Good Loan %] = DIVIDE ( [Good Loans], [Total Loans] )
    MEASURE '_Measures'[At Risk Loan %] = DIVIDE ( [At Risk Loans], [Total Loans] )
    MEASURE '_Measures'[Bad Loan %] = DIVIDE ( [Bad Loans], [Total Loans] )
    MEASURE '_Measures'[Good Loan Funded Amount] = CALCULATE ( [Total Funded Amount], dim_Loan_Status[Loan_Class] = "Good" )
    MEASURE '_Measures'[Good Loan Amount Received] = CALCULATE ( [Total Amount Received], dim_Loan_Status[Loan_Class] = "Good" )
    MEASURE '_Measures'[At Risk Loan Funded Amount] = CALCULATE ( [Total Funded Amount], dim_Loan_Status[Loan_Class] = "At Risk" )
    MEASURE '_Measures'[At Risk Loan Amount Received] = CALCULATE ( [Total Amount Received], dim_Loan_Status[Loan_Class] = "At Risk" )
    MEASURE '_Measures'[Bad Loan Funded Amount] = CALCULATE ( [Total Funded Amount], dim_Loan_Status[Loan_Class] = "Bad" )
    MEASURE '_Measures'[Bad Loan Amount Received] = CALCULATE ( [Total Amount Received], dim_Loan_Status[Loan_Class] = "Bad" )
    MEASURE '_Measures'[Matured Loans] = CALCULATE ( [Total Loans], fact_Loans[Is_Matured] = TRUE () )
    MEASURE '_Measures'[Matured Charged-Off Loans] = CALCULATE ( [Total Loans], fact_Loans[Is_Matured] = TRUE (), dim_Loan_Status[Is_Charged_Off] = TRUE () )
    MEASURE '_Measures'[Charge-off Rate (Matured)] = VAR m = [Matured Loans]
RETURN IF ( m >= 500, DIVIDE ( [Matured Charged-Off Loans], m ) )
    MEASURE '_Measures'[Rejected Applications] = SUM ( fact_Rejected_Monthly[Rejected_Count] )
    MEASURE '_Measures'[Rejected Amount Requested] = SUM ( fact_Rejected_Monthly[Amount_Requested_Sum] )
    MEASURE '_Measures'[Loan-Only Filter Active] = ISCROSSFILTERED ( dim_Grade ) || ISCROSSFILTERED ( dim_Purpose )
  || ISCROSSFILTERED ( dim_Home_Ownership ) || ISCROSSFILTERED ( dim_Term )
  || ISCROSSFILTERED ( dim_Verification_Status ) || ISCROSSFILTERED ( dim_Application_Type )
  || ISCROSSFILTERED ( dim_Employment_Length ) || ISCROSSFILTERED ( dim_Income_Band )
  || ISCROSSFILTERED ( dim_Loan_Status ) || ISFILTERED ( fact_Loans )
    MEASURE '_Measures'[Applications Received] = IF ( [Loan-Only Filter Active], BLANK (), [Total Loans] + [Rejected Applications] )
    MEASURE '_Measures'[Approval Rate] = IF ( [Loan-Only Filter Active], BLANK (), DIVIDE ( [Total Loans], [Total Loans] + [Rejected Applications] ) )
    MEASURE '_Measures'[Approval Rate (2007-2014)] = CALCULATE ( [Approval Rate], KEEPFILTERS ( dim_Date[Year] <= 2014 ) )

```