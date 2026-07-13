********************************************************************************
* WAGE COMPOSITION EFFECTS DURING POST-PANDEMIC RECOVERY
* Analysis of CPS Microdata, 2016-2024 
* Author: Yun Liu
* Date: May 2025
* This code analyzes how composition changes in the employed workforce
* affect measured wage growth during the post-pandemic period.
*
* Methods:
* 1. Cross-sectional means and medians (unadjusted)
* 2. Demographic reweighting adjustment
* 3. Imputation bounds for non-workers
* 4. Panel estimation with individual fixed effects
********************************************************************************

clear all
set more off
set scheme s2mono

* ==============================================================================
* SECTION 0: SETUP
* ==============================================================================

* Set working directory
global mainpath "/Users/yunliu/Desktop/Research/Uchicago/wage_growth"

* Create directory structure
capture mkdir "$mainpath/outputs"
capture mkdir "$mainpath/outputs/figures"
capture mkdir "$mainpath/outputs/tables"
capture mkdir "$mainpath/temp"

* Start log
log using "$mainpath/outputs/wage_analysis.log", replace text

di as text _n "=" as result " WAGE COMPOSITION ANALYSIS " as text "="
di as text "Start time: " as result "`c(current_time)' on `c(current_date)'"

********************************************************************************
* SECTION 1: DATA PREPARATION
********************************************************************************

di as text _n "=" as result " SECTION 1: DATA PREPARATION " as text "="

* ------------------------------------------------------------------------------
* 1.1: Load and Prepare CPS Data
* ------------------------------------------------------------------------------

use "$mainpath/inputs/cps_00003.dta", clear

* Sample restrictions
di as text "Applying sample restrictions"

keep if inrange(year, 2016, 2024)
keep if inrange(age, 25, 54)
keep if sex == 1
drop if inlist(gqtype, 2, 5, 8, 9, 10, 99)

di as text "Sample size after restrictions: " as result _N

* ------------------------------------------------------------------------------
* 1.2: Construct Hourly Wage
* ------------------------------------------------------------------------------

gen wage_hr = .
replace wage_hr = hourwage if paidhour == 2
replace wage_hr = earnweek / uhrsworkt if paidhour == 1 & uhrsworkt > 0

* ------------------------------------------------------------------------------
* 1.3: Merge with CPI Data
* ------------------------------------------------------------------------------

save "$mainpath/temp/cps_base.dta", replace

import excel "$mainpath/inputs/cpi_16_24.xlsx", ///
    sheet("BLS Data Series") cellrange(A12:O21) firstrow clear

rename Jan cpi_1
rename Feb cpi_2
rename Mar cpi_3
rename Apr cpi_4
rename May cpi_5
rename Jun cpi_6
rename Jul cpi_7
rename Aug cpi_8
rename Sep cpi_9
rename Oct cpi_10
rename Nov cpi_11
rename Dec cpi_12
drop HALF1 HALF2

reshape long cpi_, i(Year) j(month)
rename Year year
rename cpi_ cpi
keep if inrange(year, 2016, 2024)

save "$mainpath/temp/cpi.dta", replace

* ------------------------------------------------------------------------------
* 1.4: Create Master Dataset
* ------------------------------------------------------------------------------

use "$mainpath/temp/cps_base.dta", clear
merge m:1 year month using "$mainpath/temp/cpi.dta"
assert _merge == 3
drop _merge

gen ym = ym(year, month)
format ym %tm
gen wgt = earnwt / 10000

summ cpi if year == 2016 & month == 1, meanonly
scalar cpi_base = r(mean)
gen cpi_index = cpi / cpi_base
gen wage_real = wage_hr / cpi_index

save "$mainpath/temp/cps_master.dta", replace

********************************************************************************
* SECTION 2: CREATE ANALYTIC SAMPLES
********************************************************************************

di as text _n "=" as result " SECTION 2: ANALYTIC SAMPLES " as text "="

* Working sample (employed with positive wages)
use "$mainpath/temp/cps_master.dta", clear
keep if empstat == 10
drop if missing(wage_hr) | wage_hr <= 0
save "$mainpath/temp/sample_working.dta", replace

* Full sample (including non-workers)
use "$mainpath/temp/cps_master.dta", clear
save "$mainpath/temp/sample_full.dta", replace

* Panel sample (outgoing rotation)
use "$mainpath/temp/cps_master.dta", clear
keep if inlist(mish, 4, 8)
keep if empstat == 10
drop if missing(wage_hr) | wage_hr <= 0
drop if missing(earnwt) | earnwt <= 0
drop if cpsidp == 0
save "$mainpath/temp/sample_panel.dta", replace

********************************************************************************
* SECTION 3: UNADJUSTED WAGE TRENDS
********************************************************************************

di as text _n "=" as result " SECTION 3: UNADJUSTED TRENDS " as text "="

* ------------------------------------------------------------------------------
* 3.1: Weighted Monthly Means
* ------------------------------------------------------------------------------

use "$mainpath/temp/sample_working.dta", clear

gen wage_nom_wgt = wage_hr * wgt
gen wage_real_wgt = wage_real * wgt

bysort ym: egen total_wgt = total(wgt)
bysort ym: egen total_nom = total(wage_nom_wgt)
bysort ym: egen total_real = total(wage_real_wgt)

gen mean_nom = total_nom / total_wgt
gen mean_real = total_real / total_wgt

collapse (first) mean_nom mean_real, by(ym)

* Normalize to January 2016
summ mean_nom if ym == ym(2016,1), meanonly
gen mean_nom_norm = mean_nom / r(mean)

summ mean_real if ym == ym(2016,1), meanonly
gen mean_real_norm = mean_real / r(mean)

save "$mainpath/temp/monthly_means.dta", replace

* ------------------------------------------------------------------------------
* 3.2: Weighted Monthly Medians
* ------------------------------------------------------------------------------

use "$mainpath/temp/sample_working.dta", clear

* Nominal medians
preserve
sort ym wage_hr
by ym (wage_hr): gen cumw = sum(wgt)
by ym: egen totalw = total(wgt)
gen tag_nom = 0
by ym (wage_hr): replace tag_nom = 1 if cumw >= totalw/2 & (cumw - wgt < totalw/2)
by ym: egen median_nom = max(wage_hr * tag_nom)
collapse (first) median_nom, by(ym)
drop if missing(median_nom)

summ median_nom if ym == ym(2016,1), meanonly
gen median_nom_norm = median_nom / r(mean)

save "$mainpath/temp/monthly_medians_nom.dta", replace
restore

* Real medians
preserve
sort ym wage_real
by ym (wage_real): gen cumw = sum(wgt)
by ym: egen totalw = total(wgt)
gen tag_real = 0
by ym (wage_real): replace tag_real = 1 if cumw >= totalw/2 & (cumw - wgt < totalw/2)
by ym: egen median_real = max(wage_real * tag_real)
collapse (first) median_real, by(ym)
drop if missing(median_real)

summ median_real if ym == ym(2016,1), meanonly
gen median_real_norm = median_real / r(mean)

save "$mainpath/temp/monthly_medians_real.dta", replace
restore

* ------------------------------------------------------------------------------
* 3.3: Apply 3-Month Moving Averages
* ------------------------------------------------------------------------------

* Means
use "$mainpath/temp/monthly_means.dta", clear
tsset ym

gen mean_nom_3ma = (L.mean_nom_norm + mean_nom_norm + F.mean_nom_norm) / 3
gen mean_real_3ma = (L.mean_real_norm + mean_real_norm + F.mean_real_norm) / 3

* Handle endpoints
replace mean_nom_3ma = . if missing(F.mean_nom_norm) | missing(L.mean_nom_norm)
replace mean_real_3ma = . if missing(F.mean_real_norm) | missing(L.mean_real_norm)

save "$mainpath/temp/means_3ma.dta", replace

* Medians - Nominal
use "$mainpath/temp/monthly_medians_nom.dta", clear
tsset ym

gen median_nom_3ma = (L.median_nom_norm + median_nom_norm + F.median_nom_norm) / 3
replace median_nom_3ma = . if missing(F.median_nom_norm) | missing(L.median_nom_norm)

save "$mainpath/temp/medians_nom_3ma.dta", replace

* Medians - Real
use "$mainpath/temp/monthly_medians_real.dta", clear
tsset ym

gen median_real_3ma = (L.median_real_norm + median_real_norm + F.median_real_norm) / 3
replace median_real_3ma = . if missing(F.median_real_norm) | missing(L.median_real_norm)

save "$mainpath/temp/medians_real_3ma.dta", replace

* ------------------------------------------------------------------------------
* 3.4: Employment-to-Population Ratio
* ------------------------------------------------------------------------------

use "$mainpath/temp/cps_master.dta", clear

gen employed = (empstat == 10)
gen employed_wgt = employed * wgt

collapse (sum) employed_wgt wgt, by(ym)
gen epop = employed_wgt / wgt

save "$mainpath/temp/epop_monthly.dta", replace

* ------------------------------------------------------------------------------
* 3.5: Figures - Unadjusted Trends
* ------------------------------------------------------------------------------

* Plot: Means
use "$mainpath/temp/means_3ma.dta", clear

twoway ///
    (line mean_nom_3ma ym, lcolor(cranberry) lwidth(medthick)) ///
    (line mean_real_3ma ym, lcolor(navy) lwidth(medthick) lpattern(dash)), ///
    xlabel(672(12)780, format(%tm)) ///
    xtitle("") ytitle("Wage Index (Jan 2016 = 1.0)", size(medsmall)) ///
    title("Mean Hourly Wages: Unadjusted", size(medium)) ///
    legend(order(1 "Nominal" 2 "Real") pos(6) cols(2) size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    note("Note: 3-month centered moving average. Prime-age men (25-54), CPS 2016-2024." ///
         "Normalized to January 2016 = 1.0.", size(vsmall))

graph export "$mainpath/outputs/figures/fig1_means_unadjusted.pdf", replace


* Plot: Medians
use "$mainpath/temp/medians_nom_3ma.dta", clear
merge 1:1 ym using "$mainpath/temp/medians_real_3ma.dta", nogenerate

graph twoway ///
    (line median_nom_3ma median_real_3ma ym, lcolor(cranberry navy) lwidth(medthick medthick) lpattern(solid dash)), ///
    xscale(range(673 780)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023" 768 "2024", ///
           format(%tmCCYY) nogrid) ///
    ylab(0.95(0.05)1.40, nogrid angle(0)) ///
    xtitle("") ///
    ytitle("Wage Index (Jan 2016 = 1.0)", size(small)) ///
    title("Median Hourly Wages: Unadjusted", size(medium)) ///
    subtitle("3-month centered moving average, normalized to Jan 2016 = 1.0", size(small)) ///
    legend(order(1 "Nominal" 2 "Real") pos(6) cols(2) size(small)) ///
    graphregion(color(white) margin(small)) bgcolor(white) ///
    plotregion(margin(small)) ///
    note("Note: Prime-age men (25-54), CPS 2016-2024.", size(vsmall))

graph export "$mainpath/outputs/figures/fig2_medians_unadjusted.pdf", replace	 


********************************************************************************
* SECTION 4: DEMOGRAPHIC ADJUSTMENT
********************************************************************************

di as text _n "=" as result " SECTION 4: DEMOGRAPHIC ADJUSTMENT " as text "="

use "$mainpath/temp/sample_working.dta", clear

* ------------------------------------------------------------------------------
* 4.1: Create Demographic Cells
* ------------------------------------------------------------------------------

* Age groups (6 groups, 5-year bins)
gen age_group = .
replace age_group = 1 if inrange(age, 25, 29)
replace age_group = 2 if inrange(age, 30, 34)
replace age_group = 3 if inrange(age, 35, 39)
replace age_group = 4 if inrange(age, 40, 44)
replace age_group = 5 if inrange(age, 45, 49)
replace age_group = 6 if inrange(age, 50, 54)

* Education groups (5 groups)
gen educ_group = .
replace educ_group = 1 if educ <= 71
replace educ_group = 2 if educ == 73
replace educ_group = 3 if inlist(educ, 81, 91, 92)
replace educ_group = 4 if educ >= 111

label define edu_lbl 1 "< HS" 2 "HS" 3 "Some College" 4 "BA" 5 "Grad"
label values educ_group edu_lbl

egen cell = group(age_group educ_group)

* ------------------------------------------------------------------------------
* 4.2: Compute 2016 Baseline Shares
* ------------------------------------------------------------------------------

preserve
keep if year == 2016

bysort cell: egen pop2016_cell = total(wgt)
egen pop2016_tot = total(wgt)
gen share2016 = pop2016_cell / pop2016_tot

keep cell share2016
duplicates drop cell, force

save "$mainpath/temp/cell_shares_2016.dta", replace
restore

* ------------------------------------------------------------------------------
* 4.3: Demographically-Adjusted Means
* ------------------------------------------------------------------------------

gen wage_nom_wgt = wage_hr * wgt
gen wage_real_wgt = wage_real * wgt

bysort ym cell: egen sum_wage_nom = total(wage_nom_wgt)
bysort ym cell: egen sum_wage_real = total(wage_real_wgt)
bysort ym cell: egen sum_wgt = total(wgt)

gen mean_cell_nom = sum_wage_nom / sum_wgt
gen mean_cell_real = sum_wage_real / sum_wgt

collapse (first) mean_cell_nom mean_cell_real, by(ym cell)

merge m:1 cell using "$mainpath/temp/cell_shares_2016.dta"
assert _merge == 3
drop _merge

gen contrib_nom = mean_cell_nom * share2016
gen contrib_real = mean_cell_real * share2016

bysort ym: egen adj_nom = total(contrib_nom)
bysort ym: egen adj_real = total(contrib_real)

collapse (first) adj_nom adj_real, by(ym)

summ adj_nom if ym == ym(2016,1), meanonly
gen adj_nom_norm = adj_nom / r(mean)

summ adj_real if ym == ym(2016,1), meanonly
gen adj_real_norm = adj_real / r(mean)

tsset ym
gen adj_nom_3ma = (L.adj_nom_norm + adj_nom_norm + F.adj_nom_norm) / 3
gen adj_real_3ma = (L.adj_real_norm + adj_real_norm + F.adj_real_norm) / 3

replace adj_nom_3ma = . if missing(F.adj_nom_norm) | missing(L.adj_nom_norm)
replace adj_real_3ma = . if missing(F.adj_real_norm) | missing(L.adj_real_norm)

save "$mainpath/temp/demoadj_means_3ma.dta", replace

* ------------------------------------------------------------------------------
* 4.4: Demographically-Adjusted Medians
* ------------------------------------------------------------------------------

use "$mainpath/temp/sample_working.dta", clear

* Recreate cells
gen age_group = .
replace age_group = 1 if inrange(age, 25, 29)
replace age_group = 2 if inrange(age, 30, 34)
replace age_group = 3 if inrange(age, 35, 39)
replace age_group = 4 if inrange(age, 40, 44)
replace age_group = 5 if inrange(age, 45, 49)
replace age_group = 6 if inrange(age, 50, 54)

gen educ_group = .
replace educ_group = 1 if educ <= 71
replace educ_group = 2 if educ == 73
replace educ_group = 3 if inlist(educ, 81, 91, 92)
replace educ_group = 4 if educ >= 111
egen cell = group(age_group educ_group)

* Compute demographic weights
bysort ym cell: egen popcell = total(wgt)
bysort ym: egen poptotal = total(wgt)
gen share_actual = popcell / poptotal

merge m:1 cell using "$mainpath/temp/cell_shares_2016.dta"
assert _merge == 3
drop _merge

gen demowgt = wgt * (share2016 / share_actual)

* Nominal median
preserve
sort ym wage_hr
by ym (wage_hr): gen cumw = sum(demowgt)
by ym: egen totalw = total(demowgt)
gen tag_nom = 0
by ym (wage_hr): replace tag_nom = 1 if cumw >= totalw/2 & (cumw - demowgt < totalw/2)
by ym: egen median_nom_adj = max(wage_hr * tag_nom)
collapse (first) median_nom_adj, by(ym)
drop if missing(median_nom_adj)

summ median_nom_adj if ym == ym(2016,1), meanonly
gen median_nom_adj_norm = median_nom_adj / r(mean)

tsset ym
gen median_nom_adj_3ma = (L.median_nom_adj_norm + median_nom_adj_norm + F.median_nom_adj_norm) / 3
replace median_nom_adj_3ma = . if missing(F.median_nom_adj_norm) | missing(L.median_nom_adj_norm)

save "$mainpath/temp/demoadj_medians_nom_3ma.dta", replace
restore

* Real median
preserve
sort ym wage_real
by ym (wage_real): gen cumw = sum(demowgt)
by ym: egen totalw = total(demowgt)
gen tag_real = 0
by ym (wage_real): replace tag_real = 1 if cumw >= totalw/2 & (cumw - demowgt < totalw/2)
by ym: egen median_real_adj = max(wage_real * tag_real)
collapse (first) median_real_adj, by(ym)
drop if missing(median_real_adj)

summ median_real_adj if ym == ym(2016,1), meanonly
gen median_real_adj_norm = median_real_adj / r(mean)

tsset ym
gen median_real_adj_3ma = (L.median_real_adj_norm + median_real_adj_norm + F.median_real_adj_norm) / 3
replace median_real_adj_3ma = . if missing(F.median_real_adj_norm) | missing(L.median_real_adj_norm)

save "$mainpath/temp/demoadj_medians_real_3ma.dta", replace
restore

* ------------------------------------------------------------------------------
* 4.5: Figures - Demographic Adjustment
* ------------------------------------------------------------------------------

* Comparing means
use "$mainpath/temp/means_3ma.dta", clear
merge 1:1 ym using "$mainpath/temp/demoadj_means_3ma.dta", nogenerate

twoway ///
    (line mean_real_3ma ym, lcolor(cranberry) lwidth(medthick)) ///
    (line adj_real_3ma ym, lcolor(navy) lwidth(medthick) lpattern(dash)), ///
    xlabel(672(12)780, format(%tm)) ///
    xtitle("") ytitle("Real Wage Index (Jan 2016 = 1.0)", size(medsmall)) ///
    title("Real Mean Wages: Unadjusted vs. Demographic-Adjusted", size(medium)) ///
    legend(order(1 "Unadjusted" 2 "Demographic-Adjusted") pos(6) cols(2) size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    note("Note: 3-month centered moving average. Prime-age men (25-54), CPS 2016-2024." ///
         "Demographic adjustment holds age×education composition fixed at 2016 levels.", size(vsmall))

graph export "$mainpath/outputs/figures/fig3_means_demoadjusted.pdf", replace

********************************************************************************
* SECTION 5: IMPUTATION FOR NON-WORKERS
********************************************************************************

di as text _n "=" as result " SECTION 5: IMPUTATION BOUNDS " as text "="

* ------------------------------------------------------------------------------
* 5.1: 33rd Percentile Imputation
* ------------------------------------------------------------------------------

use "$mainpath/temp/sample_full.dta", clear

* Create cells
gen age_group = .
replace age_group = 1 if inrange(age, 25, 29)
replace age_group = 2 if inrange(age, 30, 34)
replace age_group = 3 if inrange(age, 35, 39)
replace age_group = 4 if inrange(age, 40, 44)
replace age_group = 5 if inrange(age, 45, 49)
replace age_group = 6 if inrange(age, 50, 54)

gen educ_group = .
replace educ_group = 1 if educ <= 71
replace educ_group = 2 if educ == 73
replace educ_group = 3 if inlist(educ, 81, 91, 92)
replace educ_group = 4 if educ >= 111

egen cell = group(age_group educ_group)

* Compute 33rd percentile within cells
bysort ym cell: egen pct33_nom = pctile(wage_hr), p(33)
bysort ym cell: egen pct33_real = pctile(wage_real), p(33)

replace wage_hr = pct33_nom if missing(wage_hr)
replace wage_real = pct33_real if missing(wage_real)

* Apply demographic adjustment
merge m:1 cell using "$mainpath/temp/cell_shares_2016.dta"
keep if _merge == 3
drop _merge

bysort ym cell: egen popcell = total(wgt)
bysort ym: egen poptotal = total(wgt)
gen share_actual = popcell / poptotal
gen demowgt = wgt * (share2016 / share_actual)

* Compute means
preserve
gen wage_nom_wgt = wage_hr * demowgt
gen wage_real_wgt = wage_real * demowgt

bysort ym: egen total_nom = total(wage_nom_wgt)
bysort ym: egen total_real = total(wage_real_wgt)
bysort ym: egen total_wgt = total(demowgt)

gen mean_nom_imp33 = total_nom / total_wgt
gen mean_real_imp33 = total_real / total_wgt

collapse (first) mean_nom_imp33 mean_real_imp33, by(ym)

summ mean_nom_imp33 if ym == ym(2016,1), meanonly
gen mean_nom_imp33_norm = mean_nom_imp33 / r(mean)

summ mean_real_imp33 if ym == ym(2016,1), meanonly
gen mean_real_imp33_norm = mean_real_imp33 / r(mean)

tsset ym
gen mean_nom_imp33_3ma = (L.mean_nom_imp33_norm + mean_nom_imp33_norm + F.mean_nom_imp33_norm) / 3
gen mean_real_imp33_3ma = (L.mean_real_imp33_norm + mean_real_imp33_norm + F.mean_real_imp33_norm) / 3

replace mean_nom_imp33_3ma = . if missing(F.mean_nom_imp33_norm) | missing(L.mean_nom_imp33_norm)
replace mean_real_imp33_3ma = . if missing(F.mean_real_imp33_norm) | missing(L.mean_real_imp33_norm)

save "$mainpath/temp/imputed33_means_3ma.dta", replace
restore

* ------------------------------------------------------------------------------
* 5.2: 50th Percentile Imputation
* ------------------------------------------------------------------------------

use "$mainpath/temp/sample_full.dta", clear

* Create cells
gen age_group = .
replace age_group = 1 if inrange(age, 25, 29)
replace age_group = 2 if inrange(age, 30, 34)
replace age_group = 3 if inrange(age, 35, 39)
replace age_group = 4 if inrange(age, 40, 44)
replace age_group = 5 if inrange(age, 45, 49)
replace age_group = 6 if inrange(age, 50, 54)

gen educ_group = .
replace educ_group = 1 if educ <= 71
replace educ_group = 2 if educ == 73
replace educ_group = 3 if inlist(educ, 81, 91, 92)
replace educ_group = 4 if educ >= 111
egen cell = group(age_group educ_group)

* Compute 50th percentile within cells
bysort ym cell: egen pct50_nom = pctile(wage_hr), p(50)
bysort ym cell: egen pct50_real = pctile(wage_real), p(50)

replace wage_hr = pct50_nom if missing(wage_hr)
replace wage_real = pct50_real if missing(wage_real)

* Apply demographic adjustment
merge m:1 cell using "$mainpath/temp/cell_shares_2016.dta"
keep if _merge == 3
drop _merge

bysort ym cell: egen popcell = total(wgt)
bysort ym: egen poptotal = total(wgt)
gen share_actual = popcell / poptotal
gen demowgt = wgt * (share2016 / share_actual)

* Compute means
preserve
gen wage_nom_wgt = wage_hr * demowgt
gen wage_real_wgt = wage_real * demowgt

bysort ym: egen total_nom = total(wage_nom_wgt)
bysort ym: egen total_real = total(wage_real_wgt)
bysort ym: egen total_wgt = total(demowgt)

gen mean_nom_imp50 = total_nom / total_wgt
gen mean_real_imp50 = total_real / total_wgt

collapse (first) mean_nom_imp50 mean_real_imp50, by(ym)

summ mean_nom_imp50 if ym == ym(2016,1), meanonly
gen mean_nom_imp50_norm = mean_nom_imp50 / r(mean)

summ mean_real_imp50 if ym == ym(2016,1), meanonly
gen mean_real_imp50_norm = mean_real_imp50 / r(mean)

tsset ym
gen mean_nom_imp50_3ma = (L.mean_nom_imp50_norm + mean_nom_imp50_norm + F.mean_nom_imp50_norm) / 3
gen mean_real_imp50_3ma = (L.mean_real_imp50_norm + mean_real_imp50_norm + F.mean_real_imp50_norm) / 3

replace mean_nom_imp50_3ma = . if missing(F.mean_nom_imp50_norm) | missing(L.mean_nom_imp50_norm)
replace mean_real_imp50_3ma = . if missing(F.mean_real_imp50_norm) | missing(L.mean_real_imp50_norm)

save "$mainpath/temp/imputed50_means_3ma.dta", replace
restore

* ------------------------------------------------------------------------------
* 5.3: Figures - Imputation Bounds
* ------------------------------------------------------------------------------

use "$mainpath/temp/means_3ma.dta", clear
merge 1:1 ym using "$mainpath/temp/imputed33_means_3ma.dta", nogenerate
merge 1:1 ym using "$mainpath/temp/imputed50_means_3ma.dta", nogenerate

twoway ///
    (line mean_real_3ma ym, lcolor(cranberry) lwidth(medthick)) ///
    (line mean_real_imp33_3ma ym, lcolor(forest_green) lwidth(medthick) lpattern(dash)) ///
    (line mean_real_imp50_3ma ym, lcolor(dkorange) lwidth(medthick) lpattern(longdash)), ///
    xlabel(672(12)780, format(%tm)) ///
    xtitle("") ytitle("Real Wage Index (Jan 2016 = 1.0)", size(medsmall)) ///
    title("Real Mean Wages: Workers Only vs. Full Sample with Imputation", size(medium)) ///
    legend(order(1 "Workers Only" 2 "33rd Pctile Imputed" 3 "50th Pctile Imputed") ///
           pos(6) cols(3) size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    note("Note: 3-month centered moving average. Prime-age men (25-54), CPS 2016-2024." ///
         "Imputed methods assign non-workers wages at 33rd/50th percentile of their demographic cell.", ///
         size(vsmall))

graph export "$mainpath/outputs/figures/fig4_imputation_bounds.pdf", replace

********************************************************************************
* SECTION 6: PANEL METHOD (INDIVIDUAL FIXED EFFECTS)
********************************************************************************

di as text _n "=" as result " SECTION 6: PANEL ESTIMATION " as text "="

use "$mainpath/temp/sample_panel.dta", clear

* ------------------------------------------------------------------------------
* 6.1: Match Workers Across Time
* ------------------------------------------------------------------------------

sort cpsidp ym

by cpsidp: gen lag_wage_hr = wage_hr[_n-1]
by cpsidp: gen lag_wage_real = wage_real[_n-1]

keep if mish == 8 & !missing(lag_wage_hr)

di as text "Matched panel observations: " as result _N

* ------------------------------------------------------------------------------
* 6.2: Compute Year-Over-Year Log Wage Changes
* ------------------------------------------------------------------------------

gen dlog_nom = log(wage_hr) - log(lag_wage_hr)
gen dlog_real = log(wage_real) - log(lag_wage_real)

gen wdlog_nom = dlog_nom * wgt
gen wdlog_real = dlog_real * wgt

gen ym_base = ym - 12
format ym_base %tm

keep if inrange(ym_base, ym(2016,1), ym(2024,12))

* ------------------------------------------------------------------------------
* 6.3: Compute Weighted Mean Growth Rates
* ------------------------------------------------------------------------------

collapse (sum) wdlog_nom wdlog_real wgt, by(ym_base)

gen mean_dlog_nom = wdlog_nom / wgt
gen mean_dlog_real = wdlog_real / wgt

* Convert to year-over-year growth factors
gen growth_nom = exp(mean_dlog_nom)
gen growth_real = exp(mean_dlog_real)

* Convert to monthly-equivalent growth rates
* If wages grew by factor G over 12 months, monthly growth = G^(1/12)
gen growth_nom_monthly = growth_nom^(1/12)
gen growth_real_monthly = growth_real^(1/12)

rename ym_base ym
tsset ym

* ------------------------------------------------------------------------------
* 6.4: Build Cumulative Index
* ------------------------------------------------------------------------------

gen index_nom_panel = 1 if ym == ym(2016,1)
gen index_real_panel = 1 if ym == ym(2016,1)

* Cumulate monthly growth rates forward
replace index_nom_panel = index_nom_panel[_n-1] * growth_nom_monthly if ym > ym(2016,1)
replace index_real_panel = index_real_panel[_n-1] * growth_real_monthly if ym > ym(2016,1)

* Apply 3-month moving average
gen index_nom_panel_3ma = (L.index_nom_panel + index_nom_panel + F.index_nom_panel) / 3
gen index_real_panel_3ma = (L.index_real_panel + index_real_panel + F.index_real_panel) / 3

replace index_nom_panel_3ma = . if missing(F.index_nom_panel) | missing(L.index_nom_panel)
replace index_real_panel_3ma = . if missing(F.index_real_panel) | missing(L.index_real_panel)

save "$mainpath/temp/panel_index_3ma.dta", replace

* ------------------------------------------------------------------------------
* 6.5: Figure - Panel Index
* ------------------------------------------------------------------------------

twoway ///
    (line index_nom_panel_3ma ym, lcolor(cranberry) lwidth(medthick)) ///
    (line index_real_panel_3ma ym, lcolor(navy) lwidth(medthick) lpattern(dash)), ///
    xlabel(672(12)780, format(%tm)) ///
    xtitle("") ytitle("Wage Index (Jan 2016 = 1.0)", size(medsmall)) ///
    title("Panel Index: Year-Over-Year Wage Changes (Matched Workers)", size(medium)) ///
    legend(order(1 "Nominal" 2 "Real") pos(6) cols(2) size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    note("Note: 3-month centered moving average. Panel tracks workers from outgoing rotation month 4 to month 8 (12 months apart)." ///
         "Controls for individual fixed effects. Available through 2022 due to matching requirement.", size(vsmall))

graph export "$mainpath/outputs/figures/fig5_panel_index.pdf", replace

********************************************************************************
* SECTION 7: COMPARISON
********************************************************************************

di as text _n "=" as result " SECTION 7: COMPARISON OF ALL METHODS " as text "="

* ------------------------------------------------------------------------------
* 7.1: Merge All Indices
* ------------------------------------------------------------------------------

use "$mainpath/temp/means_3ma.dta", clear
merge 1:1 ym using "$mainpath/temp/demoadj_means_3ma.dta", nogenerate
merge 1:1 ym using "$mainpath/temp/imputed33_means_3ma.dta", nogenerate
merge 1:1 ym using "$mainpath/temp/imputed50_means_3ma.dta", nogenerate
merge 1:1 ym using "$mainpath/temp/panel_index_3ma.dta", nogenerate

save "$mainpath/outputs/all_indices_combined.dta", replace

* ------------------------------------------------------------------------------
* 7.2: Main Result Figure - All Methods
* ------------------------------------------------------------------------------
keep if ym <= ym(2022,2)

twoway ///
    (line mean_real_3ma ym, lcolor(black) lwidth(medthick) lpattern(solid) msymbol(D) msize(small)) ///
    (line adj_real_3ma ym, lcolor(black) lwidth(medthick) lpattern(dash)) ///
    (line mean_real_imp33_3ma ym, lcolor(gs8) lwidth(medthick) lpattern(dot)) ///
    (line mean_real_imp50_3ma ym, lcolor(gs8) lwidth(medthick) lpattern(shortdash)) ///
    (line index_real_panel_3ma ym, lcolor(black) lwidth(medthick) lpattern(longdash)), ///
    xlabel(672(12)745, format(%tmCY) labsize(small)) ///
    ylabel(0.95(0.05)1.20, angle(0) format(%4.2f) labsize(small)) ///
    xtitle("") ytitle("Real Wage Index (January 2016 = 1.0)", size(small) margin(medium)) ///
    title("") ///
    legend(order(1 "Cross-Sectional Mean" ///
				 2 "Demographic-Adjusted" ///
				 3 "Imputed 33rd Percentile" ///
                 4 "Imputed 50th Percentile" ///
				 5 "Panel (Fixed Effects)") ///
           pos(6) rows(2) size(vsmall) region(lcolor(white))) ///
    graphregion(color(white) margin(medium)) plotregion(lcolor(black)) ///
    scheme(s2mono) 

*graph export "$mainpath/outputs/figures/fig6_main_comparison_combined.pdf"
graph export "$mainpath/outputs/figures/fig6_main_comparison_combined.png", replace


* ------------------------------------------------------------------------------
* 7.3: TABLE 1: Summary of Wage Growth by Method
* ------------------------------------------------------------------------------
ssc install listtex
use "$mainpath/temp/fig_data.dta", clear

* Get February 2022 values for all series
preserve
keep if ym == ym(2022,2)

* Calculate growth rates (index - 1) * 100
gen panel_growth = (index_real_panel_3ma - 1) * 100
gen cross_mean_growth = (mean_real_3ma - 1) * 100
gen imp50_growth = (mean_real_imp50_3ma - 1) * 100
gen imp33_growth = (mean_real_imp33_3ma - 1) * 100

* Load demographic adjusted separately if not in fig_data
* If it IS in fig_data, skip this and use the variable
qui merge 1:1 ym using "$mainpath/temp/demoadj_means_3ma.dta", nogen keep(match master)
gen demo_growth = (adj_real_3ma - 1) * 100

* Calculate gaps from panel
gen gap_cross = cross_mean_growth - panel_growth
gen gap_demo = demo_growth - panel_growth
gen gap_imp50 = imp50_growth - panel_growth
gen gap_imp33 = imp33_growth - panel_growth

* Display results
list panel_growth cross_mean_growth demo_growth imp50_growth imp33_growth

* Create formatted table
clear
input str50 method growth_rate gap_from_panel str60 interpretation
"Panel (Fixed Effects)" 14.6 0 "Continuously employed workers"
"Cross-Sectional Mean" 5.7 -8.9 "All employed workers each month"
"Cross-Sectional Median" 6.8 -7.8 "Median wage, all employed"
"Demographic-Adjusted" 1.8 -12.8 "Age-education held constant"
"Imputed 50th Percentile" 2.2 -12.4 "Including non-workers at median"
"Imputed 33rd Percentile" 2.6 -12.0 "Including non-workers at 33rd pctile"
end

* Format for display
format growth_rate %4.1f
format gap_from_panel %5.1f

* Display table
list, clean noobs separator(0)

* Export to Excel 
export excel using "$mainpath/outputs/tables/table1_summary.xlsx", ///
    firstrow(variables) replace

* Export to LaTeX
listtex using "$mainpath/outputs/tables/table1_summary.tex", ///
    type replace ///
    head("\begin{table}[htbp]" ///
         "\centering" ///
         "\caption{Cumulative Real Wage Growth by Method, January 2016 - February 2022}" ///
         "\label{tab:summary}" ///
         "\begin{tabular}{lccp{6cm}}" ///
         "\hline\hline" ///
         "Method & Growth Rate (\%) & Gap from Panel (pp) & Interpretation \\" ///
         "\hline") ///
    foot("\hline\hline" ///
         "\multicolumn{4}{p{14cm}}{\footnotesize \textit{Notes:} All series normalized to January 2016 = 1.0, smoothed using 3-month centered moving averages. Gap from panel represents difference from continuously employed workers. Sample: Men aged 25-54, CPS 2016-2022.}" ///
         "\end{tabular}" ///
         "\end{table}")

restore
********************************************************************************
* SECTION 8: TABLES AND FIGURES
********************************************************************************

* ------------------------------------------------------------------------------
* 8.1: Table A1 - Panel Sample Summary Statistics by Year
* ------------------------------------------------------------------------------

use "$mainpath/temp/sample_panel.dta", clear
keep if ym <= ym(2022,2)

* Match workers (same as main analysis)
sort cpsidp ym
by cpsidp: gen lag_wage_hr = wage_hr[_n-1]
keep if mish == 8 & !missing(lag_wage_hr)

* Generate demographics
gen college = (educ >= 111)
*gen year = year(dofm(ym))

* Collapse to annual summaries (using all months, not just February)
preserve
collapse (mean) mean_age=age ///
         (mean) pct_college=college ///
         (mean) mean_wage=wage_real ///
         (sd) sd_wage=wage_real ///
         (p25) p25_wage=wage_real ///
         (p50) p50_wage=wage_real ///
         (p75) p75_wage=wage_real ///
         (count) n_obs=cpsidp ///
         [aw=wgt], by(year)

* Display
di as text _n "TABLE A1: Panel Sample (Continuously Employed) Characteristics"
di as text "{hline 80}"
list year mean_age pct_college mean_wage sd_wage p25_wage p50_wage p75_wage n_obs, ///
     separator(0) noobs

export excel using "$mainpath/outputs/tables/tableA1_panel_summary.xlsx", ///
    firstrow(variables) replace
restore

* ------------------------------------------------------------------------------
* 8.2: Figure A1 - Panel vs Cross-Sectional Gaps Over Time
* ------------------------------------------------------------------------------

use "$mainpath/temp/means_3ma.dta", clear
merge 1:1 ym using "$mainpath/temp/medians_real_3ma.dta", nogenerate keep(match master)
merge 1:1 ym using "$mainpath/temp/panel_index_3ma.dta", nogenerate keep(match master)

keep if ym <= ym(2022,2)

* Calculate gaps (in percentage points)
* Positive = cross-sectional understates wage growth relative to panel
gen gap_mean = (index_real_panel_3ma - mean_real_3ma) * 100
gen gap_median = (index_real_panel_3ma - median_real_3ma) * 100

* Verify key values
di as text _n "=== Figure A1: Gap Verification ==="
di as text "Date" _col(20) "Gap (Mean)" _col(35) "Gap (Median)"
foreach d in 672 720 722 724 745 {
    qui summ gap_mean if ym == `d', meanonly
    local gm = r(mean)
    qui summ gap_median if ym == `d', meanonly
    local gmed = r(mean)
    local date_str = string(dofm(`d'), "%tmCY")
    di as text "`date_str'" _col(20) as result %5.1f `gm' " pp" _col(35) %5.1f `gmed' " pp"
}

twoway ///
    (line gap_mean ym, lcolor(black) lwidth(medthick) lpattern(solid)) ///
    (line gap_median ym, lcolor(gs6) lwidth(medthick) lpattern(dash)) ///
    (function y=0, range(672 745) lcolor(gs12) lpattern(dash) lwidth(thin)), ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022", format(%tmCY) labsize(small)) ///
    ylabel(-4(2)14, angle(0) format(%4.0f) labsize(small)) ///
    xtitle("") ///
    ytitle("Percentage Point Difference", size(small)) ///
    title("") ///
    yline(0, lcolor(gs12) lpattern(dash) lwidth(thin)) ///
    legend(order(1 "Panel - Cross-Sectional Mean" ///
                 2 "Panel - Cross-Sectional Median") ///
           pos(6) rows(1) size(vsmall) region(lcolor(white))) ///
    graphregion(color(white) margin(medium)) plotregion(lcolor(black)) ///
    scheme(s2mono)

graph export "$mainpath/outputs/figures/figA1_gap_over_time.png", replace

* ------------------------------------------------------------------------------------
* 8.3: Figure A2 - Employment Change by Education, 2020, 2016-2024
* ------------------------------------------------------------------------------------

* Employment Changes by Education, 2020
use "$mainpath/temp/sample_full.dta", clear
keep if ym >= ym(2020,1) & ym <= ym(2020,12)

* Education groups
gen educ_group = .
replace educ_group = 1 if educ <= 71
replace educ_group = 2 if educ == 73
replace educ_group = 3 if inlist(educ, 81, 91, 92)
replace educ_group = 4 if educ >= 111

* Employment indicator (for EVERYONE, not just those with wages)
gen employed = (empstat == 10)

* Employment RATE by education and month
collapse (mean) emp_rate=employed [aw=wgt], by(ym educ_group)

drop if missing(educ_group)
sort educ_group ym

* Normalize to Feb 2020 = 1.0
bysort educ_group: egen baseline = max(emp_rate * (ym == ym(2020,2)))
gen emp_change = emp_rate / baseline

* Create figure
twoway ///
    (connected emp_change ym if educ_group==1, lcolor(black) mcolor(black) msymbol(O) lwidth(medthick)) ///
    (connected emp_change ym if educ_group==2, lcolor(gs4) mcolor(gs4) msymbol(T) lwidth(medthick)) ///
    (connected emp_change ym if educ_group==3, lcolor(gs8) mcolor(gs8) msymbol(S) lwidth(medthick)) ///
    (connected emp_change ym if educ_group==4, lcolor(gs12) mcolor(gs12) msymbol(D) lwidth(medthick)), ///
    xlabel(720 "Feb" 722 "Apr" 724 "Jun" 726 "Aug" 728 "Oct" 730 "Dec", labsize(small)) ///
    ylabel(0.7(0.05)1.05, angle(0) format(%3.2f) labsize(small)) ///
    xtitle("2020", size(small)) ///
    ytitle("Employment Change Relative to February", size(small)) ///
    yline(1, lcolor(gs12) lpattern(dash) lwidth(thin)) ///
    legend(order(1 "No HS Diploma" ///
                 2 "HS Diploma" ///
                 3 "Some College" ///
                 4 "BA or Higher") ///
           pos(6) cols(3) size(vsmall) region(lcolor(white))) ///
    graphregion(color(white)) plotregion(lcolor(black)) ///
    scheme(s2mono)

graph export "$mainpath/outputs/figures/fig_employment_by_education_2020.png", replace


* Employment Changes by Education, 2016-2024
use "$mainpath/temp/sample_full.dta", clear

* Education groups
gen educ_group = .
replace educ_group = 1 if educ <= 71
replace educ_group = 2 if educ == 73
replace educ_group = 3 if inlist(educ, 81, 91, 92)
replace educ_group = 4 if educ >= 111

* Employment indicator
gen employed = (empstat == 10)

* Employment RATE by education and month
collapse (mean) emp_rate=employed [aw=wgt], by(ym educ_group)

drop if missing(educ_group)
sort educ_group ym

* Normalize to Jan 2016 = 1.0
bysort educ_group: egen baseline = max(emp_rate * (ym == ym(2016,1)))
gen emp_change = emp_rate / baseline

* 3-month moving average
tsset educ_group ym
bysort educ_group: gen emp_change_3ma = (L.emp_change + emp_change + F.emp_change) / 3

* Create figure
twoway ///
    (line emp_change_3ma ym if educ_group==1, lcolor(black) lwidth(medthick) lpattern(solid)) ///
    (line emp_change_3ma ym if educ_group==2, lcolor(gs4) lwidth(medthick) lpattern(dash)) ///
    (line emp_change_3ma ym if educ_group==3, lcolor(gs8) lwidth(medthick)lpattern(shortdash)) ///
    (line emp_change_3ma ym if educ_group==4, lcolor(gs12) lwidth(medthick) lpattern(longdash)), ///
    xlabel(672 "2016" 696 "2018" 720 "2020" 744 "2022" 768 "2024", labsize(small)) ///
    ylabel(0.75(0.05)1.10, angle(0) format(%3.2f) labsize(small)) ///
    xtitle("") ///
    ytitle("Employment Change Relative to January 2016", size(small)) ///
    yline(1, lcolor(gs12) lpattern(dash) lwidth(thin)) ///
    xline(720, lcolor(gs10) lpattern(dash) lwidth(thin)) ///
    legend(order(1 "No HS Diploma" ///
                 2 "HS Diploma" ///
                 3 "Some College" ///
                 4 "BA or Higher") ///
           pos(6) cols(2) size(vsmall) region(lcolor(white))) ///
    graphregion(color(white)) plotregion(lcolor(black)) ///
    scheme(s2mono)

graph export "$mainpath/outputs/figures/fig_employment_by_education_2016_2024.png", replace
* ------------------------------------------------------------------------------
* 8.4: Figure A3 - Panel vs Cross-Sectional Demographics Over Time
* ------------------------------------------------------------------------------

* Cross-sectional sample characteristics
use "$mainpath/temp/sample_working.dta", clear
keep if ym <= ym(2022,2)
gen college = (educ >= 111)
collapse (mean) cross_college=college (mean) cross_age=age [aw=wgt], by(ym)
tempfile cross_stats
save `cross_stats'

* Panel sample characteristics (matched workers only)
use "$mainpath/temp/sample_panel.dta", clear
keep if ym <= ym(2022,2)
sort cpsidp ym
by cpsidp: gen lag_wage_hr = wage_hr[_n-1]
keep if mish == 8 & !missing(lag_wage_hr)
gen college = (educ >= 111)
collapse (mean) panel_college=college (mean) panel_age=age [aw=wgt], by(ym)

merge 1:1 ym using `cross_stats', nogen keep(3)

* Panel A: College Share
twoway ///
    (line cross_college ym, lcolor(black) lwidth(medthick) lpattern(solid)) ///
    (line panel_college ym, lcolor(gs6) lwidth(medthick) lpattern(dash)), ///
    xlabel(672(12)745, format(%tmCY) labsize(small)) ///
    ylabel(0.35(0.05)0.50, angle(0) format(%4.2f) labsize(small)) ///
    ytitle("Share with College Degree", size(small)) ///
    xtitle("") ///
    legend(order(1 "All Employed (Cross-section)" ///
                 2 "Continuously Employed (Panel)") ///
           pos(6) rows(1) size(vsmall)) ///
    title("Panel A: Educational Composition", size(medium)) ///
    graphregion(color(white)) plotregion(margin(small)) ///
    name(panel_a, replace)

* Panel B: Average Age
twoway ///
    (line cross_age ym, lcolor(black) lwidth(medthick) lpattern(solid)) ///
    (line panel_age ym, lcolor(gs6) lwidth(medthick) lpattern(dash)), ///
    xlabel(672(12)745, format(%tmCY) labsize(small)) ///
    ylabel(38(0.5)40, angle(0) format(%4.1f) labsize(small)) ///
    ytitle("Average Age (years)", size(small)) ///
    xtitle("") ///
    legend(order(1 "All Employed (Cross-section)" ///
                 2 "Continuously Employed (Panel)") ///
           pos(6) rows(1) size(vsmall)) ///
    title("Panel B: Age Composition", size(medium)) ///
    graphregion(color(white)) plotregion(margin(small)) ///
    name(panel_b, replace)

* Combined figure
graph combine panel_a panel_b, rows(2) cols(1) ///
    graphregion(color(white)) ///
    name(combined, replace)

graph export "$mainpath/outputs/figures/figA3_demographics_comparison.png", replace

********************************************************************************
* Correlation: Wage Growth vs. Employment Changes
********************************************************************************

* Load E/P ratio
use "$mainpath/temp/epop_monthly.dta", clear
tsset ym
gen d_epop = epop - L.epop
keep ym d_epop epop
tempfile epop
save `epop'

* Merge all wage series
use "$mainpath/temp/means_3ma.dta", clear
merge 1:1 ym using "$mainpath/temp/demoadj_means_3ma.dta", nogen
merge 1:1 ym using "$mainpath/temp/panel_index_3ma.dta", nogen
merge 1:1 ym using `epop', nogen

* Compute monthly wage changes
tsset ym
gen d_xsmean = mean_real_3ma - L.mean_real_3ma
gen d_demoadj = adj_real_3ma - L.adj_real_3ma
gen d_panel = index_real_panel_3ma - L.index_real_panel_3ma

* Correlations
di as text _n "=== CORRELATIONS: Wage Growth vs. E/P Changes ===" _n

corr d_xsmean d_epop
local r1 = r(rho)
di as text "Cross-sectional mean vs. E/P change: " as result %6.3f `r1'

corr d_demoadj d_epop
local r2 = r(rho)
di as text "Demographic-adjusted vs. E/P change: " as result %6.3f `r2'

corr d_panel d_epop if !missing(d_panel)
local r3 = r(rho)
di as text "Panel vs. E/P change: " as result %6.3f `r3'
