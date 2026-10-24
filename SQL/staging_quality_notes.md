# Staging Quality Notes: Syntecxhub Bank Loan Analysis

## 1. Source files
| File | Size | Lines (incl. header) | Expected data rows | Columns |
|---|---|---|---|---|
| accepted_2007_to_2018Q4.csv | 1.56 GB | 2,260,702 | 2,260,701 (incl. 2 footer lines, so 2,260,699 loans) | 151 |
| rejected_2007_to_2018Q4.csv | 1.66 GB | 27,648,742 | 27,648,741 | 9 |

Source: Kaggle, "Lending Club" (wordsforthewise). Originals are never edited or opened in Excel.
Assumption: no quoted field contains a line break (line count - 1 = expected rows).
To be confirmed in later by comparing against the staged row count.

## 2. Environment
- SQL Server 2025 Express (RTM) 17.0.1000.7, Windows 10 Pro
- Express limit: 50 GB per database (data files; the log is not counted)
- Free disk space: 175 GB
- Decision: staging tables are all text (VARCHAR); the database uses the SIMPLE recovery model to keep the log small.

## 3. Quirks observed in the raw files (decision for each)
| # | Observation | Why it matters | Decision |
|---|---|---|---|
| 1 | Accepted file contains 33 non-loan rows (32 "Total amount funded in policy code N" lines + 1 "Loans that do not meet the credit policy" marker), scattered between yearly sections, not only at the end | Would corrupt counts and sums | Valid loan = numeric id. Clean layer uses only these rows: 2,260,668 loans. Footers loaded into staging unchanged. |
| 2 | `term` has a leading space (" 60 months") | Breaks joins and GROUP BY consistency | LTRIM/RTRIM when building dimensions |
| 3 | `emp_title` has trailing spaces ("Vice President ") | Duplicate categories | TRIM in clean layer |
| 4 | `int_rate`, `dti`, `revol_util` stored as percentages (10.49), not fractions | The reference project multiplied by 100; here it must not be | Keep as percent; document the unit |
| 5 | Dates are text in `Mon-YYYY` form (issue_d = Oct-2016) | Not real dates | Convert to DATE (first day of month) in the clean layer; log failures |
| 6 | Rows are not sorted by date (tail shows 2016 issue dates) | Row order cannot be trusted | Never rely on file order; always ORDER BY explicitly |
| 7 | `member_id`, `desc` empty in samples; `url` is just a pattern of the id | No analytical value | Plan to leave out of the clean model; confirm with NULL counts in Phase 3 |
| 8 | Many loan_status values expected (Current, Fully Paid, Charged Off, Late, Default, ...) | The reference good/bad rule covers only 3 | Define the rule explicitly in Phase 5 |
| 9 | Rejected file headers contain spaces/hyphens ("Amount Requested", "Debt-To-Income Ratio") | Awkward column names | Staging uses positional load with clean names |
| 10 | Rejected file has no loan_status, only the application attributes | It can support approval analysis only for the shared fields (amount, DTI, state, employment length, date) | Handle in Phase 7/8 |
| 11 | Rejected `Loan Title` holds free-text descriptions (several hundred characters) for 2007-era rows, some with corrupted characters (ï¿½) already present in the source file | VARCHAR(500) caused truncation and invalid-character load errors | Staged as NVARCHAR(MAX); this column carries no analytical value and will be left out of the clean model |
| 12 | Rejected `Debt-To-Income Ratio` values carry a % sign ("0.39%") | Not numeric | Strip "%" and convert in the clean layer |
| 13 | Rejected `Risk_Score` contains 0.0 values (for example row with 0.0 and 0%) | A 0 score is probably missing data, not a real score | Treat 0 as unknown in the clean layer; confirm in Phase 4 |

## 4. Decision log (updated as the project progresses)
| Date | Phase | Finding | Decision | Reason |
| 23-10-2026 | 2 | Rejected load failed: Loan_Title truncation + invalid characters | Changed column to NVARCHAR(MAX), truncated table, reloaded | Free-text field is longer than expected and contains bad characters |
| 23-10-2026 | 3 | Row counts: accepted 2,260,701 / rejected 27,648,741 staged = expected | Load accepted | Exact match to file line counts |
| 23-10-2026 | 3 | Rejected Loan_Title exceeded VARCHAR(500) | Widened to NVARCHAR(MAX), reloaded | No data loss in staging |
| 23-10-2026 | 3 | Policy-1 footer totals sum to 34,004,208,600 = SUM(funded_amnt) of the 2,260,668 loans | Loan set validated at dollar level | Proves load integrity |
| 23-10-2026 | 3 | Policy-2 footers describe loans absent from the file (all loans have policy_code 1) | Ignore policy-2 footers | Not part of the data |
| 23-10-2026 | 3 | member_id 100% blank; hardship_*, settlement_*, sec_app_*, *_joint, desc, orig_projected_additional_accrued_interest 94-99.6% blank | Exclude from clean model | No analytical value |
| 23-10-2026 | 3 | 9 loan statuses incl. 2 legacy "Does not meet the credit policy" | Define explicit good/bad/in-progress rule (Phase 5) | Video rule does not cover Late/Grace/Default |
| 23-10-2026 | 3 | annual_inc min 0, max 110,000,000; dti min -1, max 999 | Quantify in Step 4, then flag/nullify | Likely invalid or placeholder values |
| 23-10-2026 | 3 | Rejected DTI contains '%' | Strip in clean layer | Needed for numeric conversion |
| 23-10-2026 | 3 | Rejected Employment_Length ~83% "< 1 year"; Risk_Score ~67% blank | Test by year in Step 4 | Possible defaulted or discontinued fields |
| 23-10-2026 | 3 | DB size 4.9 GB / 50 GB | OK | |