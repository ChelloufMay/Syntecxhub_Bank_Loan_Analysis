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

## Business rules (final, implemented in 04_business_rules.sql)
1. Loan class: Good = Fully Paid, Current; At Risk = In Grace Period, Late (16-30), Late (31-120); Bad = Charged Off, Default. Legacy "Does not meet the credit policy" statuses map to Fully Paid / Charged Off.
2. Resolved = Fully Paid or Charged Off.
3. Bad Loan % = Bad / all loans (descriptive only; understates risk for recent vintages).
4. Matured = issue date + term <= snapshot date (2019-03-01). Primary risk measure: charge-off rate on matured loans. 2017-2018 have no matured loans.
5. Funded Amount = funded_amnt. Amount Received = total_pymnt (includes recoveries). Repayment Ratio = received / funded, interpreted on resolved loans only. Net Return = received - funded.
6. Money columns converted with ROUND(TRY_CAST(col AS FLOAT), 2).
7. Bands (ref schema): DTI, income, loan amount, risk score. DTI < 0 or >= 999 -> Unknown. Rejected DTI used by band only.
8. Approval rate = accepted / (accepted + rejected); rejected Employment_Length excluded; rejected Risk_Score used for 2007-2014 only.

## 4. Decision log (updated as the project progresses)
| Date | Phase | Finding | Decision | Reason |
|---|---|---|---|---|
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
| 24-10-2026 | 4 | 33 non-loan rows; footer policy-1 total = SUM(funded_amnt) = 34,004,208,600 | Clean layer = numeric id only (2,260,668 loans) | Dollar-level reconciliation passed |
| 24-10-2026 | 4 | 1 group of 2 loans identical on 10 attributes, different ids | Keep both, flag only | Different loan ids; identical attributes can occur by chance; impact negligible |
| 24-10-2026 | 4 | annual_inc = 0 for 1,667 loans | Annual_Income_Clean = NULL, flag kept | Zero income is "not reported", not a real value |
| 24-10-2026 | 4 | annual_inc > 1,000,000 for 583 loans (max 110M) with matching tiny DTI | Keep, flag Is_Income_Outlier; use income bands/median, never AVG | Internally consistent, can't prove error; bands neutralize skew |
| 24-10-2026 | 4 | dti blank 1,711; negative 2; = 999 for 135 | NULL for blank/negative/>=999; band "Unknown" | 999 and negatives are placeholders |
| 24-10-2026 | 4 | dti 100-998 for 2,426 loans | Keep, falls in "40+" band | Possible (debt exceeds income) |
| 24-10-2026 | 4 | revol_util > 100 for 7,343 loans | Keep | Over-limit usage is legitimate |
| 24-10-2026 | 4 | term has leading space on all rows | TRIM; term_months = 36/60 | Consistency |
| 24-10-2026 | 4 | All date columns parse; no date-order violations | Convert to DATE (1st of month) | |
| 24-10-2026 | 4 | total_pymnt = rec_prncp + rec_int + late_fee + recoveries for 99.995% of loans | "Amount Received" = total_pymnt (includes recoveries) | Matches component sum |
| 24-10-2026 | 4 | Charged-off loans repaid ~54% of funded on average | Report received vs funded for bad loans, not just "loss" | Bad loans partly recovered |
| 24-10-2026 | 4 | Charge-off rate by vintage: 15.6-18.0% (2013-15), 8.8% (2017), 1.8% (2018) | Add resolved-only and matured-cohort measures (Phase 5) | Recent loans immature |
| 24-10-2026 | 4 | Rejected amount = 0 for 1,288 rows | NULL the amount, exclude from amount analysis | Impossible request |
| 24-10-2026 | 4 | Rejected DTI: 1,203,063 below 0; 807,971 above 100; max 50,000,031 | NULL if <0 or >=999; keep 100-998 | Placeholders/garbage vs plausible high DTI |
| 24-10-2026 | 4 | Rejected Risk_Score range 0-990; blank 82/79/46/93% in 2015-2018 | Valid 300-850 else NULL; use for application years 2007-2014 only | FICO range; field dropped after 2014 |
| 24-10-2026 | 4 | Rejected Employment_Length "< 1 year" 73-91% most years | Keep column but exclude from approval analysis; list in README limitations | Placeholder-like |
| 24-10-2026 | 4 | 22 rejected rows with NULL state (Mar 2008); 918 blank policy codes; 1 bad zip | Keep rows; unused fields ignored | Immaterial |
| 24-10-2026 | 4 | Approval rate 4.96-15.05% by year, ~7.6% overall | Accept as approximate (issue vs application date) | Plausible |
| 24-10-2026 | 4 | Duplicate pair ids 470612 / 470026 identical on all attributes; total_pymnt differs by $0.01 | Keep both, flag Is_Possible_Duplicate | Different ids; 2 of 2.26M rows |
| 24-10-2026 | 4 | F2 returned 0 rows although 108 loans failed the component-sum check | Cause: NULL (unparseable) components, to be resolved with F2b | NULL comparisons are silently skipped |
| 24-10-2026 | 4 | Rejected DTI >= 999: 169,258; 100-998: 2,001,269; Risk_Score outside 300-850: 115,755 (86,754 are 0) | Apply rules as planned | |
| 24-10-2026 | 4 | ~1.36M rejected rows appear to have DTI exactly 100 (pending F4) | Use rejected DTI by band only, never AVG | Likely cap/placeholder |
| 24-10-2026 | 4 | F2/F2b: 108 loans failed the component-sum check because total_rec_late_fee holds scientific-notation noise (e.g. -2e-10, 2.4e-09); total_pymnt itself converts fine | Clean layer converts all money columns with ROUND(TRY_CAST(col AS FLOAT), 2). Verified by F2c: 2,260,668 of 2,260,668 loans match (previously 2,260,560) | Values are floating-point residue (about $0.00); a DECIMAL cast rejects scientific notation and silently returns NULL |
| 24-10-2026 | 4 | Rejected DTI >= 999: 169,258; 100-998: 2,001,269; Risk_Score outside 300-850: 115,755 (86,754 are 0) | NULL DTI if < 0 or >= 999; NULL Risk_Score outside 300-850; keep all other values | Separates placeholders from plausible high values |
| 24-10-2026 | 4 | Rejected DTI exactly 100: 1,362,556 rows (0.7% of 2016, 5.4% of 2017, 10.0% of 2018; about 0% before 2014); values 101-998 appear in every year (638,713 rows) | Keep the value; use rejected DTI by band only, never AVG or a yearly mean; list in README limitations | Looks like a cap or placeholder introduced in recent data, which makes yearly averages non-comparable. The "40+" band is unaffected |
| 24-10-2026 | 5 | Snapshot date = 2019-03-01 (latest last_pymnt_d); 0 unmapped statuses; class split Good 1,957,056 (86.57%) / At Risk 34,252 (1.52%) / Bad 269,360 (11.92%) | Rule table ref.Loan_Status_Map adopted as final | Every loan classified; legacy statuses folded into Fully Paid / Charged Off |
| 24-10-2026 | 5 | Repayment ratio by class: Good 0.847, At Risk 0.548, Bad 0.533 | Class-level ratio is reported but flagged as incomplete for Good (878K Current loans still repaying). Fair repayment ratio = resolved loans only (Fully Paid vs Charged Off), built in Phase 8 | Earlier assumption that Good > 1.0 was wrong; Current loans have not finished repaying |
| 24-10-2026 | 5 | Charge-off % by issue year: all loans 8.83% (2017), 1.79% (2018); resolved-only 23.3% (2016), 23.1% (2017), 15.8% (2018); matured-only 14.6-16.2% for 2009-2016, NULL for 2017-2018 | Primary risk measure = matured-only charge-off rate. All-loans and resolved-only rates are not used for vintage comparison. 2017-2018 displayed as "not matured", never as 0% | Recent vintages are immature; resolved-only is biased because charge-offs resolve before good loans finish |
| 24-10-2026 | 5 | From 2014 onwards the matured pool is almost entirely 36-month loans (matured share: 2014 74.7%, 2015 67.2%, 2016 22.1%) | Compare matured charge-off by term (36-month only) in Phase 8; store Is_Matured in the fact table | 60-month loans have not reached maturity; term mix would bias comparisons |
| 24-10-2026 | 6 | Clean dimensions built and validated: Loan_Status (7), Grade (35), Purpose (14), Home_Ownership (4; ANY/OTHER/NONE merged into Other, 1,232 loans), Term (2), Verification_Status (3), Application_Type (2), Employment_Length (12 incl. Unknown), Geography (52 incl. Unknown). D2/D3 coverage checks: 0 unmatched values in 2,260,668 accepted loans and 27,648,741 rejected applications | Accept. Band tables (DTI, income, loan amount, risk) stay in ref and are imported to Power BI as dimensions | No row will be orphaned in the fact tables |
| 24-10-2026 | 6 | dim.Date built: 4,748 daily rows, 2007-01-01 to 2019-12-31, no gaps. Weekend flag verified (2007-01-06 = Saturday; 1,356 weekend days = 28.56%). All 2,260,668 loan issue months and all 4,238 distinct rejected application dates matched | Accept. Accepted loans link to the first day of their issue month (source only has month precision); rejected applications link to their exact day | One shared calendar lets a single Year/Month slicer filter both loans and rejections |
| 24-10-2026 | 7a | fact.Loans built: 2,260,668 rows, PK Loan_ID, 14 FKs validated. Funded total 34,004,208,600.00 = staging; received 27,314,649,581.58 vs unrounded staging 27,314,649,581.5753. Class counts and funded amounts match Phase 5. Component check 2,260,668/2,260,668. Matured-only charge-off by year reproduces V4 | Accept. fact.Loans is the single source for all KPIs and for the Phase 8 answer key | Reconciled to the source to the cent |
| 24-10-2026 | 7a | FL3 Good-class received = 24,761,333,778.88 vs V3 24,761,333,780.23 ($1.35) | Use fact-table values from now on; V3's Good received figure is superseded | Fact total is within $0.005 of the unrounded source; V3's decimal cast drifted |
| 24-10-2026 | 7a | Null rules applied: Annual_Income NULL 1,671; DTI NULL 1,848; income outliers 583; possible duplicates 2; matured loans 785,915 | As designed in Phase 4 and 5 | Counts equal the Phase 4 predictions exactly |
| 24-10-2026 | 7a | Risk bands of accepted loans: 600-649: 231, 650-699: 1,304,571, 700-749: 748,396, 750+: 207,470; none below 600 | Keep all bands; approval-by-risk analysis restricted to application years 2007-2014 | Accepted loans almost never score below 650, so approval is strongly score-driven |
| 24-10-2026 | 7b | fact.Rejected_Applications built: 27,648,741 rows; per-year counts equal staging for all 12 years; 6 FKs validated | Accept | Orphan check 0 on all keys |
| 24-10-2026 | 7b | Cleaning counts tie out exactly: amount NULL 1,288; DTI NULL 1,372,321 (= 1,203,063 negative + 169,258 >= 999); Risk NULL 18,613,385 (= 18,497,630 blank + 115,755 out of range); DTI exactly 100: 1,362,556; state Unknown 22; employment Unknown 951,355 | Accept; rules from Phase 4 applied as designed | Counts reconcile to the Phase 4 findings |
| 24-10-2026 | 7b | fact.Rejected_Monthly built: 702,577 rows (month x state x DTI band x amount band x risk band). Count 27,648,741 and amount 363,117,559,783.53 equal the detail table | Accept; this is what Power BI imports (detail table stays in SQL as audit trail) | 27.6M rows are too heavy for Power BI Import; aggregate shares the grain of fact.Loans |
| 24-10-2026 | 7b | Approval rate by year from fact tables reproduces the Phase 4 preview exactly (4.96% in 2018 to 15.05% in 2013) | Accept | |
| 24-10-2026 | 7b | Approval by risk band, 2007-2014: Under 600 = 0%, 600-649 = 0.03%, 650-699 = 23.37%, 700-749 = 28.69%, 750+ = 26.11%. Accepted side uses fico_range_low, rejected side Risk_Score | Report as the dominant approval factor; state the measurement caveat in the README | Near-total cutoff below 650; the two scores may not be identical |
| 24-10-2026 | 7b | Approval by DTI band (all years): 0-9.99 = 5.69%, 10-19.99 = 13.58%, 20-29.99 = 12.76%, 30-39.99 = 6.48%, 40+ = 0.46%, Unknown = 0.13%. Low-DTI band has unexpectedly low approval | Investigate with query C4 (DTI = 0 rows, approval by era) before reporting | Possible placeholder zeros or year-mix effect; not yet explained |
| 24-10-2026 | 7b | Database 8,080 MB (data about 5.8 GB, page-compressed) of the 50 GB limit | OK | |
| 25-10-2026 | 8 | Queries A-E run on fact tables. Totals reconcile: 2,260,668 loans, funded 34,004,208,600.00, received 27,314,649,581.58. audit.Factor_Profile (12 factors, 118 levels) totals 2,260,668 loans and 34,004,208,600.00 per factor | Accept; Factor_Profile is the answer key for factor visuals | Self-check C2 passed |
| 25-10-2026 | 8 | Latest issue month 2018-12-01. MTD vs PMTD: loans 40,134 vs 41,973 (-4.38%); funded 637,843,075 vs 666,934,725 (-4.36%); avg rate 12.98 vs 13.08; avg DTI 19.64 vs 19.89 (MoM for rate/DTI is relative change, not points) | KPI cards use these values | |
| 25-10-2026 | 8 | MTD received 72,758,316.53 vs 98,907,996.88 (-26.44%); received/funded is 0.114 for Dec 2018 vs about 1.13 for early-2013 and 2014 months | Show but label "not like-for-like"; never present MoM received as performance | Recent cohorts have had little time to repay |
| 25-10-2026 | 8 | Monthly issuance is lumpy in 2014-2015 (Sep 2014: 10,606; Oct 2014: 38,783; Dec 2014: 10,307; Jan 2015: 35,107); cause not determined | Base trend conclusions on quarters/years; list in README limitations | MoM is noisy |
| 25-10-2026 | 8 | YoY loans: 2016 +3.16%, 2017 +2.11%, 2018 +11.65%; funded 2016 -0.27%, 2017 +2.88%, 2018 +20.52% (avg loan about $14.8K to $16.0K, +8%). 2007 is a partial year (from June), so 2008 growth (+296.85%) is inflated. Avg rate steps from 12.51 (Jun 2016) to 13.69 (Jul 2016); cause not determined | Note in README | |
| 25-10-2026 | 8 | Net return by status: Fully Paid +2,509,722,041.07 on 15.2B funded (about +16.5%); Charged Off -1,954,713,714.38 on 4.19B (about -46.7%) | Report as descriptive, gross of fees | |
| 25-10-2026 | 8 | Matured charge-off by grade: A 5.45, B 11.47, C 18.54, D 24.31, E 30.18, F 35.01, G 38.50 (%). Interest rate rises 7.14 to 24.83 | Grade is the dominant repayment factor | Monotonic across all 7 grades |
| 25-10-2026 | 8 | C3 net return rises with grade (A 7.15% to F 14.86%, G 14.51%) but is simple, unannualized, and term mix differs (60-month share of matured loans: A 0.7%, B 3.6%, C 10.7%, D 14.9%, E 33.3%, F 55.1%, G 63.5%) | Do NOT present as "riskier grades earn more"; use C5 (grade x term) | Confounded by term |
| 25-10-2026 | 8 | Within grade, 60-month charge-off exceeds 36-month by 1.9-3.9 pts (A +2.86, B +3.94, C +3.19, D +3.18, E +2.16, F +1.90); G reverses (-2.94) on small counts | The raw term gap (14.09 vs 25.22) is mostly grade mix | |
| 25-10-2026 | 8 | Spread of matured charge-off between best and worst level (levels with >= 1,000 matured loans): Grade 33.1; Purpose 12.4; Credit score 11.9; DTI 11.7; Term 11.1 (raw); Income 10.4; State 9.5; Verification 6.4; Home ownership 4.6; Loan amount 2.1; Employment length 1.4 | Univariate, descriptive; README says "associated with", never "causes" | Not controlled for other factors or vintage |
| 25-10-2026 | 8 | Verified loans charge off more (18.14%) than Not Verified (11.71%) and carry higher rates (14.69% vs 11.62%); Unknown employment length (146,907 loans) charges off at 21.12% | Report as selection-like patterns; cause unknown | |
| 25-10-2026 | 8 | Small samples excluded from conclusions: credit score 600-649 (231 loans), educational (423 matured), renewable energy (584), home ownership Other (234), IA (14 loans), Joint App (1,767 matured), DTI 40+ (1,290 matured) | Dashboard shows loan counts; apply a minimum-volume threshold on rate visuals | |
| 25-10-2026 | 8 | Approval by requested amount: Under 5K 3.01%, 5K-9.99K 7.75%, 10K-14.99K 9.34%, 15K-19.99K 12.47%, 20K-29.99K 10.46%, 30K+ 6.23% | Report as is | |
| 25-10-2026 | 8 | Approval by DTI band, by era: 0-9.99 below 10-29.99 in every era (2007-12: 9.25 vs 21.15/15.52; 2013-14: 8.30 vs 22.23/21.63; 2015-16: 6.94 vs 17.64/17.58; 2017-18: 4.34 vs 9.51/8.74). 30-39.99: 2.77, 7.60, 9.68, 4.79; accepted loans with DTI 40+ exist only from 2015 | Not a year-mix effect; analyse approval by era | |
| 25-10-2026 | 8 | Rejected rows with DTI exactly 0: 1,044,510 (2008-2018; 2007 not pasted), about 15.5% of rejected rows in the 0-9.99 band, vs 1,732 accepted loans (0.08%). Approval for DTI = 0 about 0.17%; excluding zeros the rest of the band is about 6.6%, still well below 13.58% (10-19.99) | Keep values; split into band "Zero (0)" (08b); remaining gap unexplained | The asymmetry suggests 0 is not a normal low DTI; cannot prove it is a placeholder |
| 25-10-2026 | 8 | Accepted loans grew 3.7x (2013 to 2018) while rejected applications grew 12.5x; approval fell 15.05% to 4.96% | Report | |
| 25-10-2026 | 8 | Dashboard filter test: Grade A + CA = 62,451 loans, funded 940,682,700.00, received 704,839,842.26 | Power BI with these two slicers must match | | 
| 25-10-2026 | 8 | Rejected rows with DTI exactly 0: 1,045,102 (all years, 2007 = 592); about 15.5% of rejected rows in the former 0-9.99 band; accepted loans with DTI 0: 1,732 (0.08%). Approval for DTI = 0: 0.17% | Keep values; isolated as band "Zero (0)" (08b); remaining gap in the 0.01-9.99 band (6.63% vs 13.58% for 10-19.99) unexplained | Zero is treated differently in the rejected file; cannot prove it is a placeholder |
| 25-10-2026 | 8b | DTI zero band applied. Z1: Zero (0) 1,732 / 0.01-9.99 406,116 / 10-19.99 922,306 / 20-29.99 682,770 / 30-39.99 218,834 / 40+ 27,062 / Unknown 1,848. Z2: 778,276 aggregate rows; count 27,648,741 and amount 363,117,559,783.53 unchanged. Z3: approval Zero 0.17%, 0.01-9.99 6.63%, 10-19.99 13.58%, 20-29.99 12.76%, 30-39.99 6.48%, 40+ 0.46%, Unknown 0.13%. Z4: 0 inconsistencies | Accept. ref.DTI_Band has Sort_Order; 04_business_rules.sql updated for rebuilds (do not run on live DB: FKs reference ref.DTI_Band); 08b kept as migration record | Rebuild reproduces the same keys because source views read the band bounds |
| 25-10-2026 | 8 | C5 (matured loans, grade x term): 36-month net return per year A 2.37, B 2.88, C 2.72, D 2.49, E 1.83, F 1.32, G 0.23 (%); 60-month A 2.62, B 3.21, C 3.81, D 3.81, E 3.98, F 3.83, G 3.76 | Within 36-month, return peaks at grade B and falls to near zero at G; compare grades only within a term. Per-year figure is total return divided by term in years (not an IRR) | 36-month and 60-month matured pools cover different vintages (issued by about early 2016 vs early 2014); returns are gross of servicing and collection fees; early repayment makes the per-year figure conservative |