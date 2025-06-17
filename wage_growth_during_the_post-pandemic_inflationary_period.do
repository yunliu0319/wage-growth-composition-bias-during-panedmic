//project: Wage Growth during the Post-Pandemic Inflationary Period 
//data: Monthly CPS Basic Samples (2016–2024) with wage, employment, and demographic variables
//source: IPUMS CPS (Link: https://cps.ipums.org/cps/)
//Yun Liu

capture log close
log using "$mainpath/outputs/wage_growth.log", text replace
set more off
clear all
************************************************** Part 1 Data Preparation **************************************************
*========================================================
*  Part 1 - Data Preparation and CPI Merge
*========================================================
* 1. set scheme and paths
set scheme AC, permanently
global mainpath "/Users/yunliu/Desktop/Macroeconomics/"

* 2. load raw CPS
use "$mainpath/inputs/cps_00001.dta", clear

* 3. Year and demographic filters (year/age/sex/group quarters/vet)
drop if year==2010 | year==2012
keep if inrange(age,25,54)
keep if sex==1
drop if inlist(gqtype,2,5,8,9,10,99)
drop if vetstat==2           // active duty

* 4 Drop missing empstat & wage variables 
drop if missing(paidhour) & missing(earnweek) 
 
* 5. Construct hourly wage
gen wage_hr = .
replace wage_hr = hourwage if paidhour==2
replace wage_hr = earnweek / uhrsworkt if paidhour==1 & uhrsworkt>0
//drop if missing(wage_hr) | wage_hr<=0

* Quick checks 
* summarize wage_hr if year==2024
* bysort year: summarize wage_hr
* count if year==2024 & wage_hr>0
* describe empstat
* label list EMPSTAT // value label (Alternatively, use code: codebook empstat)

* 6. Save cleaned worker sample
save "$mainpath/inputs/cps_base.dta", replace

* 8. Build CPI-U series, 01/2016 to 12/2024
import excel "$mainpath/inputs/SeriesReport-20250508005428_c629d6.xlsx", ///
    sheet("BLS Data Series") cellrange(A12:O10000) firstrow clear

rename Jan  cpi_1
rename Feb  cpi_2
rename Mar  cpi_3
rename Apr  cpi_4
rename May  cpi_5
rename Jun  cpi_6
rename Jul  cpi_7
rename Aug  cpi_8
rename Sep  cpi_9
rename Oct cpi_10
rename Nov cpi_11
rename Dec cpi_12

drop if Year==2015 | Year==2025 | missing(Year)
reshape long cpi_, i(Year) j(month)   // turn wide → long
rename Year year
rename cpi_  cpi
drop if missing(cpi)
format cpi %9.3f

save "$mainpath/inputs/cpi.dta", replace

* 9. Merge CPS × CPI and save master series
use "$mainpath/inputs/cps_base.dta", clear
merge m:1 year month using "$mainpath/inputs/cpi.dta"
drop _merge

save "$mainpath/inputs/cps_cpi_base.dta", replace

*========================================================
*  Part 2 - Branch off into the three CPS subsamples
*========================================================
// Subsample 1 - working-only positive wage sample (used in Q1–3 & Q5 on means, medians, growth)
use "$mainpath/inputs/cps_cpi_base.dta", clear

* keep only employed-at-work
keep if empstat==10

* drop zero/negative or missing wages
drop if missing(wage_hr) | wage_hr<=0

* generate weight & time
gen wgt  = earnwt/10000
gen ym   = ym(year,month)
format ym %tm

* save for Parts 1-3 & 5
save "$mainpath/inputs/cps_cpi_working_wages.dta", replace

// Subsample 2 - full wage sample (used for Q4 to impute a wage for missings by cell)
use "$mainpath/inputs/cps_cpi_base.dta", clear

gen wgt  = earnwt/10000
gen ym   = ym(year,month)
format ym %tm

save "$mainpath/inputs/cps_cpi_full_sample.dta", replace

********************** Part 2 Mean and Median of Nominal and Real Wages (working sample) ***************************************

// Aggregate monthly individual wages to monthly mean wages 
use "$mainpath/inputs/cps_cpi_working_wages.dta", clear 

* --------------------------------------------------------------
* Step 1: Compute weighted monthly means of nominal & real wages 
* --------------------------------------------------------------
* Generate real-wage variable 
summarize cpi
tab cpi if year == 2016 & month == 1
gen cpi_index = cpi / 236.916   // cpi in Jan 2016
gen wage_real = wage_hr / cpi_index //real wage  

gen wage_nominal_wgt = wage_hr * wgt // weighted nominal wages
gen wage_real_wgt    = wage_real * wgt // weighted real wages

bysort year month (ym): gen total_wgt = sum(wgt) // total weights by year and month
bysort year month (ym): gen total_nom = sum(wage_nominal_wgt) // total weighted nominal wages by year and month
bysort year month (ym): gen total_real = sum(wage_real_wgt) // total weighted real wages by year and month

gen mean_nom = total_nom / total_wgt // monthly weighted mean
gen mean_real = total_real / total_wgt

bysort year month (ym): replace mean_nom = mean_nom[_n-1] if missing(mean_nom)
bysort year month (ym): replace mean_real = mean_real[_n-1] if missing(mean_real)

// Normalize nominal and real wages to 2016=1
collapse (mean) mean_nom mean_real, by(ym)

summarize mean_nom if ym == ym(2016, 1), meanonly
scalar base_nom = r(mean)

summarize mean_real if ym == ym(2016, 1), meanonly
scalar base_real = r(mean)

gen mean_nom_norm  = mean_nom / base_nom
gen mean_real_norm = mean_real / base_real

save "$mainpath/inputs/wage_mean.dta", replace

* ------------------------------------------------------------------
* Step 2: Compute weighted monthly medians of nominal and real wages 
* ------------------------------------------------------------------
use "$mainpath/inputs/cps_cpi_working_wages.dta", clear 

gen cpi_index = cpi / 236.916   // cpi in Jan 2016
gen wage_real = wage_hr / cpi_index //real wage  

preserve
sort ym wage_hr
bysort ym (wage_hr): gen cumw = sum(wgt)
bysort ym: gen totalw = sum(wgt)

gen tag = .
bysort ym (wage_hr): replace tag = 1 if missing(tag) & ///
    cumw >= totalw/2 & (cumw - wgt < totalw/2)

gen median_nom = .
replace median_nom = wage_hr if tag == 1
bysort ym: replace median_nom = median_nom[_n-1] if missing(median_nom)

collapse (mean) median_nom, by(ym)
keep ym median_nom
duplicates drop
save "$mainpath/inputs/monthly_nominal_medians.dta", replace
restore

preserve
sort ym wage_real
bysort ym (wage_real): gen cumw = sum(wgt)
bysort ym: gen totalw = sum(wgt)

gen tag = .
bysort ym (wage_real): replace tag = 1 if missing(tag) & ///
    cumw >= totalw/2 & (cumw - wgt < totalw/2)

gen median_real = .
replace median_real = wage_real if tag == 1
bysort ym: replace median_real = median_real[_n-1] if missing(median_real)

collapse (mean) median_real, by(ym)
keep ym median_real
duplicates drop
save "$mainpath/inputs/monthly_real_medians.dta", replace
restore

* Merge monthly medians
merge m:1 ym using "$mainpath/inputs/monthly_nominal_medians.dta"
drop _merge
merge m:1 ym using "$mainpath/inputs/monthly_real_medians.dta"
drop _merge

* Normalize to Jan 2016 = 1
summarize median_nom if ym == ym(2016,1), meanonly
scalar base_median_nom = r(mean)
gen median_nom_norm = median_nom / base_median_nom

summarize median_real if ym == ym(2016,1), meanonly
scalar base_median_real = r(mean)
gen median_real_norm = median_real / base_median_real

tabdisp year month, c(median_nom_norm)
tabdisp year month, c(median_real_norm)

save "$mainpath/inputs/wage_median.dta", replace

* ---------------------------------------
* Step 3: Apply 3-month moving averages
* ---------------------------------------
// Mean 
use "$mainpath/inputs/wage_mean.dta", clear

* Declare time series structure
tsset ym

* Compute 3-month moving average using lags and leads
gen mean_nom_3ma  = (L.mean_nom_norm  + mean_nom_norm  + F.mean_nom_norm)  / 3
gen mean_real_3ma = (L.mean_real_norm + mean_real_norm + F.mean_real_norm) / 3

* Remove artificial values at the boundaries if needed
replace mean_nom_3ma  = . if missing(L.mean_nom_norm, F.mean_nom_norm)
replace mean_real_3ma = . if missing(L.mean_real_norm, F.mean_real_norm)

save "$mainpath/inputs/wage_mean_3ma.dta", replace

// Median 
use "$mainpath/inputs/wage_mean_median.dta", clear
keep ym median_nom_norm median_real_norm
duplicates drop ym, force

duplicates report ym  // should return nothing

tsset ym

gen median_nom_3ma  = (L.median_nom_norm + median_nom_norm + F.median_nom_norm) / 3
gen median_real_3ma = (L.median_real_norm + median_real_norm + F.median_real_norm) / 3

tabdisp ym, c(median_nom_3ma)
tabdisp ym, c(median_real_3ma)

save "$mainpath/inputs/wage_median_3ma.dta", replace

* ---------------------------------------
* Step 4: Plotting
* ---------------------------------------
// Plot A 3-month moving average nomalized mean wages 
use "$mainpath/inputs/wage_mean_3ma.dta", clear
format ym %tm
keep if !missing(mean_nom_3ma)
duplicates drop ym, force	
summarize mean_nom_3ma mean_real_3ma
summarize ym if mean_nom_3ma ~= . , detail
summarize ym if mean_real_3ma ~= . , detail

graph twoway (line mean_nom_3ma mean_real_3ma ym, /// 
    lcolor(red blue) ///
    lwidth(medium medium) ///
    lpattern(solid dash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Unadjsuted nominal mean" 2 "Unadjusted real mean") size(3) position(6) col(2)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023", format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly mean wage") ylab(0.9(0.1)1.5, nogrid) ///
	title(" Three-month moving average monthly mean wages of workers (CPS, 2016-2024)", size(medsmall)) ///
    subtitle("normalized to Jan 2016 = 1", size(small)) ///
)	   
graph export "$mainpath/outputs/plot_3ma_mean.pdf", as(pdf) name("Graph") replace
	   
// Plot B 3-month moving average nomalized median wages 
use "$mainpath/inputs/wage_median_3ma.dta", clear
summarize median_nom_3ma median_real_3ma
summarize ym if median_nom_3ma ~= . , detail
summarize ym if median_real_3ma ~= . , detail

graph twoway ///
    (line median_nom_3ma median_real_3ma ym, ///
        lcolor(red blue) ///
        lwidth(medium medium) ///
        lpattern(solid dash) ///
    xscale(range(673 757)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023", ///
           format(%tmCCYY) nogrid) ///
    ylab(0(0.5)3.5, nogrid) ///
    xtitle("year") ///
    ytitle("monthly median wage") ///
    title("Three-month moving average monthly median wages of workers (CPS, 2016-2024)", size(medsmall)) ///
    subtitle("normalized Jan 2016 = 1", size(small)) ///
    legend(order(1 "Unadjsuted nominal median" 2 "Unadjsuted real median") pos(6) cols(2) size(3)))
graph export "$mainpath/outputs/plot_3ma_median.pdf", as(pdf) name("Graph") replace

* ------------------------------------------------------------------------------------------------------------
* Step 5: Compute the correlation between monthly real wage growth and empoloyment-to-population ratio  
* ------------------------------------------------------------------------------------------------------------
// Compute real median wage growth from 3-month moving average (use median as a measure of the typical wage movement)
use "$mainpath/inputs/wage_median_3ma.dta", clear
gen dlog_median_real = log(median_real_3ma) - log(L.median_real_3ma) // take first-difference in logs
keep ym dlog_median_real
save "$mainpath/inputs/median_real_growth.dta", replace

// Compute EPOP from microdata (weighted)
use "$mainpath/inputs/cps_cpi_base.dta", clear
gen employed = (empstat == 10)
gen wgt = earnwt / 10000
gen ym = ym(year, month)

gen employed_wgt = employed * wgt // sample-weight for employed 
bysort ym: gen total_emp = sum(employed_wgt) // weighted number of employed 
bysort ym: gen pop_wgt = sum(wgt) // monthly total weighted population as wgt represents how many people in the population each sampled individual represents 

bysort ym (month): keep if _n == _N
gen epop = total_emp / pop_wgt
keep ym epop
duplicates drop
save "$mainpath/inputs/epop_monthly.dta", replace

// Merge and compute correlation
use "$mainpath/inputs/epop_monthly.dta", clear
merge 1:1 ym using "$mainpath/inputs/median_real_growth.dta"
drop if _merge != 3
drop _merge

// Correlation analysis 
corr dlog_median_real epop // 0.0128 
pwcorr dlog_median_real epop, sig // 0.9077 no significant correlation
 

*********************************************** Part 3 Demographical Adjustment **************************************************
* ---------------------------------------
* Step 1: Generate age x education groups 
* ---------------------------------------
use "$mainpath/inputs/cps_cpi_working_wages.dta", clear 

gen cpi_index   = cpi / 236.916        
gen wage_real   = wage_hr  / cpi_index 

* Create age-education groups 
gen age_group = .
replace age_group = 1 if age >= 25 & age <= 29
replace age_group = 2 if age >= 30 & age <= 34
replace age_group = 3 if age >= 35 & age <= 39
replace age_group = 4 if age >= 40 & age <= 44
replace age_group = 5 if age >= 45 & age <= 49
replace age_group = 6 if age >= 50 & age <= 54

gen edu_group = .
replace edu_group = 1 if educ <= 72           // less than high school
replace edu_group = 2 if educ == 73           // high school only
replace edu_group = 3 if inlist(educ, 80,81,90,91,92,100, 110)  // some college 
replace edu_group = 4 if inlist(educ,111)          // bachelor’s degree
replace edu_group = 5 if inlist(educ,120,121,122,123,124,125)         // more than bachelor’s degree
drop if edu_group == .

label define edu_group_lbl 1 "less than high school" 2 "high school only" ///
                  3 "some college " 4 "bachelor’s degree" 5 "more than bachelor’s degree"
label values edu_group edu_group_lbl 

* Define a single cell index = age_group × edu_group
egen cell = group(age_group edu_group)

* --------------------------------------------------------
* Step 2: Compute the population weights at the 2016 level 
* -------------------------------------------------------- 
preserve
  keep if year==2016
  bysort cell: egen pop2016_cell = total(wgt)
  egen pop2016_tot  = total(wgt)
  gen share2016 = pop2016_cell / pop2016_tot
  keep cell share2016
  duplicates drop cell, force
  egen totalshare = total (share2016)
  save "$mainpath/inputs/cellshares2016.dta", replace
restore

* ---------------------------------------------------------------------------------------
* Step 3: Compute weighted means by cell x month, three-month moving averages 
* ---------------------------------------------------------------------------------------
// Compute the mean nominal wages and mean real wages for each cell x month
gen w_nom    = wage_hr  * wgt
gen w_realw  = wage_real * wgt

bysort ym cell: egen sum_w_nom   = total(w_nom) // sum individual weighted wages in each cell x month
bysort ym cell: egen sum_w_real  = total(w_realw)
bysort ym cell: egen sum_w       = total(wgt)

gen mean_nom  = sum_w_nom  / sum_w
gen mean_real = sum_w_real / sum_w

collapse (mean) mean_nom mean_real, by(ym cell)

save "$mainpath/inputs/cellmeans_monthly.dta", replace

* Merge 2016 weights with means 
merge m:1 cell using "$mainpath/inputs/cellshares2016.dta"
drop _merge 

* Compute each cell’s contribution to the aggregate (monthly) nominal‐wage index
gen nom_comp  = mean_nom  * share2016
gen real_comp = mean_real * share2016
sort ym cell

* Sum across cells to get the demographically-adjusted (monthly) series 
bysort ym: egen adj_nom  = total(nom_comp)
bysort ym: egen adj_real = total(real_comp)

* Normalize both series so Jan 2016 = 1
summarize adj_nom  if ym==ym(2016,1), meanonly
scalar base_adj_nom  = r(mean)
gen adj_nom_norm  = adj_nom  / base_adj_nom

summarize adj_real if ym==ym(2016,1), meanonly
scalar base_adj_real = r(mean)
gen adj_real_norm = adj_real / base_adj_real

save "$mainpath/inputs/cellmeans_monthly_normalized.dta", replace 

// Smooth with a 3-month centered moving average of monthly means
use "$mainpath/inputs/cellmeans_monthly_normalied.dta", clear

keep ym adj_nom_norm adj_real_norm
duplicates drop 
tsset ym
gen adj_nom_3ma  = (L.adj_nom_norm  + adj_nom_norm  + F.adj_nom_norm)  / 3
gen adj_real_3ma = (L.adj_real_norm + adj_real_norm + F.adj_real_norm) / 3

* Drop the end-points where L. or F. is missing
replace adj_nom_3ma  = . if missing(L.adj_nom_norm,  F.adj_nom_norm)
replace adj_real_3ma = . if missing(L.adj_real_norm, F.adj_real_norm)

save "$mainpath/inputs/wage_demoadj_3ma.dta", replace

* ---------------------------------------------------------------------------------------
* Step 4: Compute weighted medians by cell x month, three-month moving averages 
* ---------------------------------------------------------------------------------------
// Compute the demographically-adjusted medians 
use "$mainpath/inputs/cps_cpi_working_wages.dta", clear

gen cpi_index = cpi/236.916
gen wage_real = wage_hr / cpi_index

* Create age-education groups 
gen age_group = .
replace age_group = 1 if age >= 25 & age <= 29
replace age_group = 2 if age >= 30 & age <= 34
replace age_group = 3 if age >= 35 & age <= 39
replace age_group = 4 if age >= 40 & age <= 44
replace age_group = 5 if age >= 45 & age <= 49
replace age_group = 6 if age >= 50 & age <= 54

gen edu_group = .
replace edu_group = 1 if educ <= 72           // less than high school
replace edu_group = 2 if educ == 73           // high school only
replace edu_group = 3 if inlist(educ, 80,81,90,91,92,100, 110)  // some college 
replace edu_group = 4 if inlist(educ,111)          // bachelor’s degree
replace edu_group = 5 if inlist(educ,120,121,122,123,124,125)         // more than bachelor’s degree
drop if edu_group == .

label define edu_group_lbl 1 "less than high school" 2 "high school only" ///
                  3 "some college " 4 "bachelor’s degree" 5 "more than bachelor’s degree"
label values edu_group edu_group_lbl 

egen cell = group(age_group edu_group)

* Compute each month’s actual cell shares
bysort ym cell: egen popcell   = total(wgt)
bysort ym: egen poptotal  = total(wgt)
gen share_time = popcell / poptotal // fraction of the workfore by cell x month 

* Merge with the 2016 shares
merge m:1 cell using "$mainpath/inputs/cellshares2016.dta"
drop _merge

* Reweight each person so the demographic composition is fixed 
gen demowgt = wgt * (share2016/ share_time)

// Compute the weighted nominal medians
sort ym wage_hr
bysort ym (wage_hr): gen cum_dw_nom  = sum(demowgt)    
bysort ym: egen tot_dw_nom  = total(demowgt)

* Tag the first obs where cum_dw crosses half the total
gen tag_nom = .
bysort ym (wage_hr): replace tag_nom = 1 if  ///
     missing(tag_nom)     & ///
     cum_dw_nom >= tot_dw_nom/2  & ///
     (cum_dw_nom - demowgt < tot_dw_nom/2)

* Pull out the hourly wage at that tags nominal median
gen median_nom_demo = .
replace median_nom_demo = wage_hr if tag_nom==1
bysort ym: replace median_nom_demo = median_nom_demo[_n-1] if missing(median_nom_demo)

// Compute the weighted real medians 
sort ym wage_real
bysort ym (wage_real): gen cum_dw_real = sum(demowgt)    
bysort ym: egen tot_dw_real = total(demowgt)

* Tag the 50% point
gen tag_real = .
bysort ym (wage_real): replace tag_real = 1 if  ///
     missing(tag_real)     & ///
     cum_dw_real >= tot_dw_real/2  & ///
     (cum_dw_real - demowgt < tot_dw_real/2)

* Extract the real wage at that tags real median
gen median_real_demo = .
replace median_real_demo = wage_real if tag_real==1
bysort ym: replace median_real_demo = median_real_demo[_n-1] if missing(median_real_demo) 

// Normalize adjsuted medians 
collapse (mean) median_nom_demo median_real_demo, by(ym)

* Find the Jan 2016 level of each series
summarize median_nom_demo if ym==ym(2016,1), meanonly
scalar base_nom = r(mean)

summarize median_real_demo if ym==ym(2016,1), meanonly
scalar base_real = r(mean)

* Generate normalized indices
gen median_nom_index  = median_nom_demo  / base_nom
gen median_real_index = median_real_demo / base_real

* Generate nomalized medians
tsset ym
gen med_nom_3ma  = (L.median_nom_index  + median_nom_index  + F.median_nom_index )  / 3
gen med_real_3ma = (L.median_real_index + median_real_index + F.median_real_index) / 3

replace med_nom_3ma  = . if missing(L.median_nom_index,  F.median_nom_index)
replace med_real_3ma = . if missing(L.median_real_index, F.median_real_index)
 
* Save final series
save "$mainpath/inputs/cellsmedians_demoadj_3ma.dta", replace

* --------------------------------------------------------------------
* Step 5: Plot to compare the adjusted wage series with the unadjusted 
* --------------------------------------------------------------------
use "$mainpath/inputs/wage_mean_3ma.dta", clear
merge 1:1 ym using "$mainpath/inputs/wage_demoadj_3ma.dta"

save "$mainpath/inputs/wage_mean_demoadj_3ma.dta", replace 

use "$mainpath/inputs/wage_mean_demoadj_3ma.dta", clear 
format ym %tm
summarize mean_nom_3ma  adj_nom_3ma
summarize ym if mean_nom_3ma ~= . , detail
summarize ym if mean_real_3ma ~= . , detail

summarize mean_real_3ma adj_real_3ma
summarize ym if adj_nom_3ma ~= . , detail
summarize ym if adj_real_3ma ~= . , detail

// Plot nominal means 
graph twoway (line mean_nom_3ma adj_nom_3ma ym, /// 
    lcolor(red blue) ///
    lwidth(medium medium ) ///
    lpattern(solid dash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Unadjusted nominal mean" 2 "Adjusted nominal mean") size(3) position(6) col(2)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023", format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly mean wage") ylab(1(0.1)1.4, nogrid) ///
	title("Normalized three-month moving average nominal mean wage of workers (CPS, 2016-2024)", size(medsmall)) ///
    subtitle("normalized to Jan 2016 = 1", size(small)) ///
)
graph export "$mainpath/outputs/plot_3ma_demoadj_nominal_mean.pdf", as(pdf) name("Graph") replace

// Plot real means
graph twoway (line  mean_real_3ma adj_real_3ma ym, /// 
    lcolor(red blue ) ///
    lwidth(medium medium ) ///
    lpattern(solid dash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Unadjusted real mean" 2 "Adjusted real mean") size(3) position(6) col(2)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023", format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly mean wage") ylab(0.9(0.1)1.2, nogrid) ///
	title("Normalized three-month moving average real mean wage of workers (CPS, 2016-2024)", size(medsmall)) ///
    subtitle("normalized to Jan 2016 = 1", size(small)) ///
)
graph export "$mainpath/outputs/plot_3ma_demoadj_real_mean.pdf", as(pdf) name("Graph") replace 

// Part 3 only 
graph twoway (line adj_nom_3ma adj_real_3ma ym if adj_nom_3ma ~=.& adj_real_3ma ~=. , /// 
    lcolor(red blue) ///
    lwidth(medium medium) ///
    lpattern(solid dash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Adjusted nominal mean" 2 "Adjusted real mean") size(3) position(6) col(2)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023" , format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly median wage") ylab(0.9(0.1)1.3, nogrid) ///
	title("Demographic‐adjusted three-month moving average median wages of workers (CPS, 2016-2024)", size(medsmall)) ///
    subtitle("normalized to Jan 2016 = 1", size(small)) ///
)
graph export "$mainpath/outputs/plot_3ma_demoadj_mean_only.pdf", as(pdf) name("Graph") replace


// Plot nominal medians 
use "$mainpath/inputs/wage_median_3ma.dta", clear
merge 1:1 ym using "$mainpath/inputs/cellsmedians_demoadj_3ma.dta"
drop _merge
save "$mainpath/inputs/wage_median_demoadj_3ma.dta", replace

use "$mainpath/inputs/wage_median_demoadj_3ma.dta", clear 
summarize median_nom_3ma med_nom_3ma 
summarize ym if med_nom_3ma ~= . , detail //adjusted 
summarize ym if median_nom_3ma ~= . , detail 

graph twoway (line median_nom_3ma med_nom_3ma ym, /// 
    lcolor(red blue) ///
    lwidth(medium medium) ///
    lpattern(solid dash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Unadjusted nominal median" 2 "Adjusted nominal median") size(3) position(6) col(2)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023", format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly median wage") ylab(0(1)3.3, nogrid) ///
	title("Normalized three-month moving average nominal median wage of workers (CPS, 2016-2024)", size(medsmall)) ///
    subtitle("normalized to Jan 2016 = 1", size(small)) ///
)
graph export "$mainpath/outputs/plot_3ma_demoadj_nominal_median.pdf", as(pdf) name("Graph") replace

// Plot real medians 
use "$mainpath/inputs/wage_median_demoadj_3ma.dta", clear 
summarize median_real_3ma med_real_3ma
summarize ym if median_real_3ma ~= . , detail 
summarize ym if med_real_3ma ~= . , detail //adjusted 

twoway (line med_nom_3ma ym )

graph twoway (line median_real_3ma med_real_3ma  ym, /// 
    lcolor(red blue) ///
    lwidth(medium medium) ///
    lpattern(solid dash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Unadjusted real median" 2 "Adjusted real median") size(3) position(6) col(2)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023" , format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly median wage") ylab(0(1)3.3, nogrid) ///
	title("Normalized three-month moving average real median wages of workers (CPS, 2016-2024)", size(medsmall)) ///
    subtitle("normalized to Jan 2016 = 1", size(small)) ///
)
graph export "$mainpath/outputs/plot_3ma_demoadj_real_median.pdf", as(pdf) name("Graph") replace

// Part 3 only 
graph twoway (line med_nom_3ma med_real_3ma ym if med_real_3ma ~=.& med_nom_3ma ~=. , /// 
    lcolor(red blue) ///
    lwidth(medium medium) ///
    lpattern(solid dash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Adjusted nominal median" 2 "Adjusted real median") size(3) position(6) col(2)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023" , format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly median wage") ylab(0.9(0.1)1.3, nogrid) ///
	title("Demographic‐adjusted three-month moving average median wages of workers (CPS, 2016-2024)", size(medsmall)) ///
    subtitle("normalized to Jan 2016 = 1", size(small)) ///
)
graph export "$mainpath/outputs/plot_3ma_demoadj_median_only.pdf", as(pdf) name("Graph") replace


// Give two series different y-axes 
graph twoway ///
  (line median_nom_3ma ym, yaxis(1) lcolor(red)) ///
  (line med_nom_3ma   ym, yaxis(2) lcolor(blue) lpattern(dash)), ///
  ytitle("monthly wage", axis(1)) ///
  ytitle("monthly wage",   axis(2)) ///
  xtitle("Year") ///
  legend(order(1 "Unadjusted nominal median" 2 "Adjusted nominal median")) ///
  title("Normalized three-month moving average real median wage 2016-2024")  
graph export "$mainpath/outputs/plot_3ma_demoadj_real_median_twoyaxes.pdf", as(pdf) name("Graph") replace

* -----------------------------------------
* Step 6: Compute the adjusted correlation 
* -----------------------------------------
use "$mainpath/inputs/wage_median_demoadj_3ma.dta", clear 

* Compute monthly log‐growth of the real adjusted median
tsset ym
gen dlog_med_real_adj = log(med_real_3ma) - log(L.med_real_3ma)

* Keep only the growth series
keep ym dlog_med_real_adj
save "$mainpath/inputs/median_real_demoadj_growth.dta", replace

* Merge with the weighted EPOP series
use "$mainpath/inputs/epop_monthly.dta", clear
merge 1:1 ym using "$mainpath/inputs/median_real_demoadj_growth.dta"
keep if _merge==3
drop _merge

* Compute the correlation
corr dlog_med_real_adj epop


************************Part 4 Mean and Median of Nominal and Real Wages (workers and non-workers) ******************************* 
* --------------------------------------------------------------------------
* Step 1: Compute the nomalized wage means imputed with the 33rd percentile 
* --------------------------------------------------------------------------
* Define demographic groups by age-skill for each year 
use "$mainpath/inputs/cps_cpi_full_sample.dta", clear 

gen cpi_index = cpi/236.916         
gen wage_real = wage_hr / cpi_index   

gen age_group = .
replace age_group = 1 if age >= 25 & age <= 29
replace age_group = 2 if age >= 30 & age <= 34
replace age_group = 3 if age >= 35 & age <= 39
replace age_group = 4 if age >= 40 & age <= 44
replace age_group = 5 if age >= 45 & age <= 49
replace age_group = 6 if age >= 50 & age <= 54

gen edu_group = .
replace edu_group = 1 if educ <= 72           
replace edu_group = 2 if educ == 73           
replace edu_group = 3 if inlist(educ, 80,81,90,91,92,100, 110)  
replace edu_group = 4 if inlist(educ,111)         
replace edu_group = 5 if inlist(educ,120,121,122,123,124,125)     
drop if edu_group == .

label define edu_group_lbl 1 "less than high school" 2 "high school only" ///
                  3 "some college " 4 "bachelor’s degree" 5 "more than bachelor’s degree"
label values edu_group edu_group_lbl 

egen cell = group(age_group edu_group)

* Impute missing wages with the 33rd percentile of the wages within that cell for that year  
bysort ym cell: egen pct33_nom  = pctile(wage_hr), p(33)
bysort ym cell: egen pct33_real = pctile(wage_real), p(33)

replace wage_hr   = pct33_nom  if missing(wage_hr)
replace wage_real = pct33_real if missing(wage_real)

* Adjust for the demographic composition 
merge m:1 cell using "$mainpath/inputs/cellshares2016.dta"
drop _merge
bysort ym cell: egen popcell = total(wgt)
bysort ym: egen poptotal = total(wgt)
gen share_time = popcell/ poptotal
gen demowgt = wgt * (share2016/ share_time)

save "$mainpath/inputs/cps_full_33th_impute.dta", replace 

* Compute the weighted monthly mean wages
gen w_nom   = wage_hr   * demowgt
gen w_real  = wage_real * demowgt

bysort ym: egen total_w_nom  = total(w_nom)
bysort ym: egen total_w_real = total(w_real)
bysort ym: egen total_w      = total(demowgt)

gen mean_nom_full = total_w_nom  / total_w
gen mean_real_full= total_w_real / total_w

* Collapse to one observation per month and nomalize
collapse (mean) mean_nom_full mean_real_full, by(ym)
summarize mean_nom_full if ym==tm(2016m1), meanonly
scalar base1 = r(mean)
summarize mean_real_full if ym==tm(2016m1), meanonly
scalar base2 = r(mean)

gen mean_nom_full_n = mean_nom_full / base1
gen mean_real_full_n= mean_real_full/ base2

replace mean_nom_full_n  = . if mean_nom_full_n  == 0
replace mean_real_full_n = . if mean_real_full_n == 0

drop if missing(mean_nom_full_n)
drop if missing(mean_real_full_n)

* Compute three-month moving average series and compare with part 2
tsset ym
gen nom_full_3ma  = (L.mean_nom_full_n  + mean_nom_full_n  + F.mean_nom_full_n )/3
gen real_full_3ma = (L.mean_real_full_n + mean_real_full_n + F.mean_real_full_n)/3
replace nom_full_3ma  = . if missing(L.mean_nom_full_n,  F.mean_nom_full_n)
replace real_full_3ma = . if missing(L.mean_real_full_n, F.mean_real_full_n)
drop if missing(nom_full_3ma)
drop if missing(real_full_3ma)

save "$mainpath/inputs/wagemean_full_33th_impute_3ma.dta", replace
 
* --------------------------------------------------------------------------
* Step 2: Compute the nomalized wage medians imputed with the 33rd percentile 
* --------------------------------------------------------------------------
use "$mainpath/inputs/cps_full_33th_impute.dta", clear

// Nominal medians
sort ym wage_hr
bysort ym (wage_hr): gen cum_dw_nom  = sum(demowgt)    
bysort ym: egen tot_dw_nom  = total(demowgt)
gen tag_nom = .
bysort ym (wage_hr): replace tag_nom = 1 if  ///
     missing(tag_nom)     & ///
     cum_dw_nom >= tot_dw_nom/2  & ///
     (cum_dw_nom - demowgt < tot_dw_nom/2)
gen median_nom_imp = .
replace median_nom_imp = wage_hr if tag_nom==1
bysort ym: replace median_nom_imp = median_nom_imp[_n-1] if missing(median_nom_imp)

// Real medians 
sort ym wage_real
bysort ym (wage_real): gen cum_dw_real = sum(demowgt)    
bysort ym: egen tot_dw_real = total(demowgt)
gen tag_real = .
bysort ym (wage_real): replace tag_real = 1 if  ///
     missing(tag_real)     & ///
     cum_dw_real >= tot_dw_real/2  & ///
     (cum_dw_real - demowgt < tot_dw_real/2)
gen median_real_imp = .
replace median_real_imp = wage_real if tag_real==1
bysort ym: replace median_real_imp = median_real_imp[_n-1] if missing(median_real_imp) 

// Normalize medians 
collapse (mean) median_nom_imp median_real_imp, by(ym)
summarize median_nom_imp if ym==ym(2016,1), meanonly
scalar base_nom = r(mean)
summarize median_real_imp if ym==ym(2016,1), meanonly
scalar base_real = r(mean)

gen median_nom_index  = median_nom_imp  / base_nom
gen median_real_index = median_real_imp / base_real

tsset ym
gen med_nom_imp_3ma  = (L.median_nom_index  + median_nom_index  + F.median_nom_index )  / 3
gen med_real_imp_3ma = (L.median_real_index + median_real_index + F.median_real_index) / 3

replace med_nom_imp_3ma  = . if missing(L.median_nom_index,  F.median_nom_index)
replace med_real_imp_3ma = . if missing(L.median_real_index, F.median_real_index)
drop if missing(med_nom_imp_3ma) 
drop if missing(med_real_imp_3ma) 

save "$mainpath/inputs/wagemedian_full_33th_impute_3ma.dta", replace

* --------------------------------------------------
* Step 3: Impute missing wages with 50th percentile 
* --------------------------------------------------
use "$mainpath/inputs/cps_cpi_full_sample.dta", clear 

gen cpi_index = cpi/236.916         
gen wage_real = wage_hr / cpi_index   

gen age_group = .
replace age_group = 1 if age >= 25 & age <= 29
replace age_group = 2 if age >= 30 & age <= 34
replace age_group = 3 if age >= 35 & age <= 39
replace age_group = 4 if age >= 40 & age <= 44
replace age_group = 5 if age >= 45 & age <= 49
replace age_group = 6 if age >= 50 & age <= 54

gen edu_group = .
replace edu_group = 1 if educ <= 72           
replace edu_group = 2 if educ == 73           
replace edu_group = 3 if inlist(educ, 80,81,90,91,92,100, 110)  
replace edu_group = 4 if inlist(educ,111)         
replace edu_group = 5 if inlist(educ,120,121,122,123,124,125)     
drop if edu_group == .

label define edu_group_lbl 1 "less than high school" 2 "high school only" ///
                  3 "some college " 4 "bachelor’s degree" 5 "more than bachelor’s degree"
label values edu_group edu_group_lbl 

egen cell = group(age_group edu_group)

* Impute missing wages with the 33rd percentile of the wages within that cell for that year  
bysort ym cell: egen pct50_nom  = pctile(wage_hr), p(50)
bysort ym cell: egen pct50_real = pctile(wage_real), p(50)

replace wage_hr   = pct50_nom  if missing(wage_hr)
replace wage_real = pct50_real if missing(wage_real)

* Adjust for the demographic composition 
merge m:1 cell using "$mainpath/inputs/cellshares2016.dta"
drop _merge
bysort ym cell: egen popcell = total(wgt)
bysort ym: egen poptotal = total(wgt)
gen share_time = popcell/ poptotal
gen demowgt = wgt * (share2016/ share_time)

save "$mainpath/inputs/cps_full_50th_impute.dta", replace 

* -------------------------------------------------------------------------------------
* Step 4: Compute the nomalized wage means and medians imputed with the 50th percentile 
* -------------------------------------------------------------------------------------
// Means
* Compute the weighted monthly mean wages
gen w_nom   = wage_hr   * demowgt
gen w_real  = wage_real * demowgt

bysort ym: egen total_w_nom  = total(w_nom)
bysort ym: egen total_w_real = total(w_real)
bysort ym: egen total_w      = total(demowgt)

gen mean_nom_full = total_w_nom  / total_w
gen mean_real_full= total_w_real / total_w

* Collapse to one observation per month and nomalize
collapse (mean) mean_nom_full mean_real_full, by(ym)
summarize mean_nom_full if ym==tm(2016m1), meanonly
scalar base1 = r(mean)
summarize mean_real_full if ym==tm(2016m1), meanonly
scalar base2 = r(mean)

gen mean_nom_full_n = mean_nom_full / base1
gen mean_real_full_n= mean_real_full/ base2
replace mean_nom_full_n = . if mean_nom_full == 0
replace mean_real_full_n = . if mean_real_full == 0

* Compute three-month moving average series 
tsset ym
gen nom_full5_3ma  = (L.mean_nom_full_n  + mean_nom_full_n  + F.mean_nom_full_n )/3
gen real_full5_3ma = (L.mean_real_full_n + mean_real_full_n + F.mean_real_full_n)/3
replace nom_full5_3ma  = . if missing(L.mean_nom_full_n,  F.mean_nom_full_n)
replace real_full5_3ma = . if missing(L.mean_real_full_n, F.mean_real_full_n)
drop if missing(nom_full5_3ma)
drop if missing(real_full5_3ma)
save "$mainpath/inputs/wagemean_50th_impute_3ma.dta", replace
 
// Nominal medians
use "$mainpath/inputs/cps_full_50th_impute.dta", clear
sort ym wage_hr
bysort ym (wage_hr): gen cum_dw_nom  = sum(demowgt)    
bysort ym: egen tot_dw_nom  = total(demowgt)
gen tag_nom = .
bysort ym (wage_hr): replace tag_nom = 1 if  ///
     missing(tag_nom)     & ///
     cum_dw_nom >= tot_dw_nom/2  & ///
     (cum_dw_nom - demowgt < tot_dw_nom/2)
gen median_nom_imp = .
replace median_nom_imp = wage_hr if tag_nom==1
bysort ym: replace median_nom_imp = median_nom_imp[_n-1] if missing(median_nom_imp)

// Real medians 
sort ym wage_real
bysort ym (wage_real): gen cum_dw_real = sum(demowgt)    
bysort ym: egen tot_dw_real = total(demowgt)
gen tag_real = .
bysort ym (wage_real): replace tag_real = 1 if  ///
     missing(tag_real)     & ///
     cum_dw_real >= tot_dw_real/2  & ///
     (cum_dw_real - demowgt < tot_dw_real/2)
gen median_real_imp = .
replace median_real_imp = wage_real if tag_real==1
bysort ym: replace median_real_imp = median_real_imp[_n-1] if missing(median_real_imp) 

// Normalize medians 
collapse (mean) median_nom_imp median_real_imp, by(ym)
summarize median_nom_imp if ym==ym(2016,1), meanonly
scalar base_nom = r(mean)
summarize median_real_imp if ym==ym(2016,1), meanonly
scalar base_real = r(mean)

gen median_nom_index  = median_nom_imp  / base_nom
gen median_real_index = median_real_imp / base_real
drop if missing(median_nom_index)
drop if missing(median_real_index)

tsset ym
gen med_nom_imp5_3ma  = (L.median_nom_index  + median_nom_index  + F.median_nom_index )  / 3
gen med_real_imp5_3ma = (L.median_real_index + median_real_index + F.median_real_index) / 3
replace med_nom_imp5_3ma  = . if missing(L.median_nom_index,  F.median_nom_index)
replace med_real_imp5_3ma = . if missing(L.median_real_index, F.median_real_index)

drop if missing(med_nom_imp5_3ma)
drop if missing(med_real_imp5_3ma)
save "$mainpath/inputs/wagemedian_50th_impute_3ma.dta", replace


* ---------------------------------------------------------
* Step 5: Plotting wage series imputed with 33th percentile
* ---------------------------------------------------------
// Plot A 3-month moving average nomalized mean wages 
use "$mainpath/inputs/wage_mean_3ma.dta", clear
merge 1:1 ym using "$mainpath/inputs/wagemean_full_33th_impute_3ma.dta"
keep if _merge == 3
drop _merge

summarize mean_nom_3ma nom_full_3ma
summarize ym if mean_nom_3ma ~= . , detail
summarize ym if nom_full_3ma ~= . , detail

// Plot nominal means 
graph twoway (line mean_nom_3ma nom_full_3ma ym, /// 
    lcolor(red blue) ///
    lwidth(medium medium ) ///
    lpattern(solid dash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Unadjusted nominal mean" 2 "Adjusted nominal mean (33rd percentile imputation)") size(3) position(6) col(2)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023", format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly mean wage") ylab(1(0.1)1.4, nogrid) ///
	title("Normalized three-month moving average nominal mean wages (CPS full sample, 2016-2024)", size(medsmall)) ///
    subtitle("Normalized to Jan 2016 = 1. The missing wages are imputed by ssigning the 33rd percentile of each demographic cell.", size(small)) ///
)
graph export "$mainpath/outputs/plot_3ma_33rdimp_nominal_mean.pdf", as(pdf) name("Graph") replace

// Plot real means 
summarize mean_real_3ma real_full_3ma
summarize ym if mean_real_3ma ~= . , detail
summarize ym if real_full_3ma ~= . , detail

graph twoway (line  mean_real_3ma real_full_3ma ym, /// 
    lcolor(red blue ) ///
    lwidth(medium medium ) ///
    lpattern(solid dash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Unadjusted real mean" 2 "Adjusted real mean (33rd percentile imputation)") size(3) position(6) col(2)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023", format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly mean wage") ylab(0.9(0.1)1.2, nogrid) ///
	title("Normalized three-month moving average real mean wages (CPS full sample, 2016-2024)", size(medsmall)) ///
    subtitle("Normalized to Jan 2016 = 1. The missing wages are imputed by ssigning the 33rd percentile of each demographic cell.", size(small)) ///
)
graph export "$mainpath/outputs/plot_3ma_33rdimp_real_mean.pdf", as(pdf) name("Graph") replace

// Plot B 3-month moving average nomalized median wages 
use "$mainpath/inputs/wage_median_3ma.dta", clear
merge 1:1 ym using "$mainpath/inputs/wagemedian_full_33th_impute_3ma.dta"
keep if _merge == 3
drop _merge
 
summarize median_nom_3ma med_nom_imp_3ma
summarize ym if median_nom_3ma ~= . , detail // unadjusted 
summarize ym if med_nom_imp_3ma ~= . , detail 

graph twoway (line median_nom_3ma med_nom_imp_3ma ym, /// 
    lcolor(red blue) ///
    lwidth(medium medium) ///
    lpattern(solid dash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Unadjusted nominal median" 2 "Adjusted nominal median (33rd percentile imputation)") size(3) position(6) col(2)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023", format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly median wage") ylab(0(1)3.3, nogrid) ///
	title("Normalized three-month moving average nominal median wages (CPS full sample, 2016-2024)", size(medsmall)) ///
    subtitle("Normalized to Jan 2016 = 1. The missing wages are imputed by ssigning the 33rd percentile of each demographic cell.", size(small)) ///
)
graph export "$mainpath/outputs/plot_3ma_33rdimp_nominal_median.pdf", as(pdf) name("Graph") replace

// Plot real medians 
summarize median_real_3ma med_real_imp_3ma
summarize ym if median_real_3ma ~= . , detail 
summarize ym if med_real_imp_3ma ~= . , detail //adjusted 

graph twoway (line median_real_3ma med_real_imp_3ma ym, /// 
    lcolor(red blue) ///
    lwidth(medium medium) ///
    lpattern(solid dash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Unadjusted real median" 2 "Adjusted real median (33rd percentile imputation)") size(3) position(6) col(2)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023" , format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly median wage") ylab(0(1)3.3, nogrid) ///
	title("Normalized three-month moving average real median wages (CPS full sample, 2016-2024)", size(medsmall)) ///
    subtitle("Normalized to Jan 2016 = 1. The missing wages are imputed by ssigning the 33rd percentile of each demographic cell.", size(small)) ///
)
graph export "$mainpath/outputs/plot_3ma_33rdimp_real_median.pdf", as(pdf) name("Graph") replace

// Part 4 only 
summarize med_nom_imp_3ma med_real_imp_3ma
summarize ym if med_nom_imp_3ma ~= . , detail 
summarize ym if med_real_imp_3ma ~= . , detail 

graph twoway (line med_nom_imp_3ma med_real_imp_3ma ym, /// 
    lcolor(red blue) ///
    lwidth(medium medium) ///
    lpattern(solid dash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Adjusted nominal median" 2 "Adjusted real median") size(3) position(6) col(2)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023", format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly median wage") ylab(0.9 (1)1.4, nogrid) ///
	title("Normalized three-month moving average median wages (CPS full sample, 2016-2024)", size(medsmall)) ///
    subtitle("Normalized to Jan 2016 = 1. The missing wages are imputed by ssigning the 33rd percentile of each demographic cell.", size(small)) ///
)
graph export "$mainpath/outputs/plot_3ma_33rdimp_median_only.pdf", as(pdf) name("Graph") replace


* ---------------------------------------------------------
* Step 6: Plotting wage series imputed with 50th percentile
* ---------------------------------------------------------
// Plot A 3-month moving average nomalized mean wages 
use "$mainpath/inputs/wage_mean_3ma.dta", clear
merge 1:1 ym using "$mainpath/inputs/wagemean_50th_impute_3ma.dta"
keep if _merge == 3
drop _merge

summarize mean_nom_3ma nom_full5_3ma
summarize ym if mean_nom_3ma ~= . , detail
summarize ym if nom_full5_3ma ~= . , detail

// Plot nominal means 
graph twoway (line mean_nom_3ma nom_full5_3ma ym, /// 
    lcolor(red blue) ///
    lwidth(medium medium ) ///
    lpattern(solid dash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Unadjusted nominal mean" 2 "Adjusted nominal mean (50th percentile imputation)") size(3) position(6) col(2)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023", format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly mean wage") ylab(1(0.1)1.4, nogrid) ///
	title("Normalized three-month moving average nominal mean wages (CPS full sample, 2016-2024)", size(medsmall)) ///
    subtitle("Normalized to Jan 2016 = 1. The missing wages are imputed by ssigning the 50th percentile of each demographic cell.", size(small)) ///
)
graph export "$mainpath/outputs/plot_3ma_50thimp_nominal_mean.pdf", as(pdf) name("Graph") replace

// Plot real means 
summarize mean_real_3ma real_full5_3ma
summarize ym if mean_real_3ma ~= . , detail
summarize ym if real_full5_3ma ~= . , detail

graph twoway (line  mean_real_3ma real_full5_3ma ym, /// 
    lcolor(red blue ) ///
    lwidth(medium medium ) ///
    lpattern(solid dash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Unadjusted real mean" 2 "Adjusted real mean (50th percentile imputation)") size(3) position(6) col(2)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023", format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly mean wage") ylab(0.9(0.1)1.2, nogrid) ///
	title("Normalized three-month moving average real mean wages (CPS full sample, 2016-2024)", size(medsmall)) ///
    subtitle("Normalized to Jan 2016 = 1. The missing wages are imputed by ssigning the 50th percentile of each demographic cell.", size(small)) ///
)
graph export "$mainpath/outputs/plot_3ma_50thimp_real_mean.pdf", as(pdf) name("Graph") replace


// Plot B 3-month moving average nomalized median wages 
use "$mainpath/inputs/wage_median_3ma.dta", clear
merge 1:1 ym using "$mainpath/inputs/wagemedian_50th_impute_3ma.dta"
keep if _merge == 3
drop _merge
 
summarize median_nom_3ma med_nom_imp5_3ma
summarize ym if median_nom_3ma ~= . , detail // unadjusted 
summarize ym if med_nom_imp5_3ma ~= . , detail 

graph twoway (line median_nom_3ma med_nom_imp5_3ma ym, /// 
    lcolor(red blue) ///
    lwidth(medium medium) ///
    lpattern(solid dash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Unadjusted nominal median" 2 "Adjusted nominal median (50th percentile imputation)") size(3) position(6) col(2)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023", format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly median wage") ylab(0(1)3.3, nogrid) ///
	title("Normalized three-month moving average nominal median wages (CPS full sample, 2016-2024)", size(medsmall)) ///
    subtitle("Normalized to Jan 2016 = 1. The missing wages are imputed by ssigning the 50th percentile of each demographic cell.", size(small)) ///
)
graph export "$mainpath/outputs/plot_3ma_50thimp_nominal_median.pdf", as(pdf) name("Graph") replace

// Plot real medians 
summarize median_real_3ma med_real_imp5_3ma
summarize ym if median_real_3ma ~= . , detail 
summarize ym if med_real_imp5_3ma ~= . , detail //adjusted 

graph twoway (line median_real_3ma med_real_imp5_3ma ym, /// 
    lcolor(red blue) ///
    lwidth(medium medium) ///
    lpattern(solid dash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Unadjusted real median" 2 "Adjusted real median (50th percentile imputation)") size(3) position(6) col(2)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023" , format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly median wage") ylab(0(1)3.3, nogrid) ///
	title("Normalized three-month moving average real median wages (CPS full sample, 2016-2024)", size(medsmall)) ///
    subtitle("Normalized to Jan 2016 = 1. The missing wages are imputed by ssigning the 50th percentile of each demographic cell.", size(small)) ///
)
graph export "$mainpath/outputs/plot_3ma_50thimp_real_median.pdf", as(pdf) name("Graph") replace

// Part4 only
summarize med_nom_imp5_3ma med_real_imp5_3ma
graph twoway (line med_nom_imp5_3ma med_real_imp5_3ma ym, /// 
    lcolor(red blue) ///
    lwidth(medium medium) ///
    lpattern(solid dash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Adjusted nominal median" 2 "Adjusted real median") size(3) position(6) col(2)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023" , format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly median wage") ylab(0.9(0.1)1.3, nogrid) ///
	title("Normalized three-month moving average median wages (CPS full sample, 2016-2024)", size(medsmall)) ///
    subtitle("Normalized to Jan 2016 = 1. The missing wages are imputed by ssigning the 50th percentile of each demographic cell.", size(small)) ///
)
graph export "$mainpath/outputs/plot_3ma_50thimp_median_only.pdf", as(pdf) name("Graph") replace


************************************ Part 5 Demographical Adjustment Method 2 (working only) ************************************
* Steps 
// 1) create one-year panel to measure within-person one year wage growth 
// 2) aggregating person-by-person growth rates back to the calendar month yields a smooth index of wage growth that’s orthogonal to any changes in who’s employed. 

* --------------------------------------------------------------------------
* Step 1: Compute cross-sectional, CPS-weighted average monthly wage indices
* --------------------------------------------------------------------------
// Rotation panel sample (used in Q5 to compute one‐year‐apart wage changes controlling for individual FE via cpsidp)
use "$mainpath/inputs/cps_cpi_base.dta", clear
* keep outgoing rotation months 
// outgoing rotation month - the fourth interview in each block (four consecutive months + out of eight months + four more months )
keep if inlist(mish,4,8)

drop if missing(wage_hr) | wage_hr<=0
drop if missing(earnwt)    | earnwt    <= 0
drop if cpsidp==0

gen wgt  = earnwt/10000
gen ym   = ym(year,month)
format ym %tm

* Generate real wage 
quietly su cpi if year==2016 & month==1, meanonly
scalar cpi16 = r(mean)
gen cpi_index = cpi / cpi16
gen wage_real = wage_hr / cpi_index

* Sort and build one-year-ahead lags (mish4 to mish8 for each person)
sort cpsidp ym
by cpsidp: gen lag_wage_hr   = wage_hr[_n-1]
by cpsidp: gen lag_wage_real = wage_real[_n-1] 

* Restrict to the second observation (mis8) so lag is the mis4 value
keep if mish==8 & !missing(lag_wage_hr)

* Compute log-changes
gen dlog_nom  = log(wage_hr)  - log(lag_wage_hr)
gen dlog_real = log(wage_real) - log(lag_wage_real)

* Apply weights
gen wdlog_nom  = dlog_nom  * wgt
gen wdlog_real = dlog_real * wgt

* Tag each growth with the 4th-interview month
gen tm4 = ym - 12
format tm4 %tm
keep if inrange(tm4, tm(2016m1), tm(2024m12))  

* Collapse to weighted mean log‐changes by tm4 (the 4th‐interview month)
collapse (sum) wdlog_nom wdlog_real wgt, by(tm4)
gen mean_dlog_nom  = wdlog_nom  / wgt
gen mean_dlog_real = wdlog_real / wgt

* Year-over-year growth factors 
gen index_nom  = exp(mean_dlog_nom)
gen index_real = exp(mean_dlog_real)

* Normalize so January 2016 = 1
quietly summarize index_nom  if tm4==tm(2016m1), meanonly
scalar base_nom  = r(mean)
quietly summarize index_real if tm4==tm(2016m1), meanonly
scalar base_real = r(mean)
replace index_nom  = index_nom  / base_nom
replace index_real = index_real / base_real

rename tm4 ym
tsset ym

* Take centered 3-month moving averages
gen index_nom_3ma  = (L1.index_nom  + index_nom  + F1.index_nom )/3
gen index_real_3ma = (L1.index_real + index_real + F1.index_real)/3
drop if missing(index_nom_3ma)   
drop if missing(index_real_3ma) 

save "$mainpath/inputs/cps_cpi_panel_growth.dta", replace

* -----------------
* Step 2: Plotting 
* -----------------
// Nominal mean wage growth index (part 5 vs. part 2.3.4)
* Merge all nominal indices into one dataset
use "$mainpath/inputs/wage_mean_3ma.dta", clear
merge 1:1 ym using "$mainpath/inputs/wage_mean_demoadj_3ma.dta", keep(match) nogenerate  
merge 1:1 ym using "$mainpath/inputs/wagemean_full_33th_impute_3ma.dta", keep(match) nogenerate  
merge 1:1 ym using "$mainpath/inputs/wagemean_50th_impute_3ma.dta", keep(match) nogenerate  
merge 1:1 ym using "$mainpath/inputs/cps_cpi_panel_growth.dta", keep(match) nogenerate  

save "$mainpath/inputs/mean_indices_allparts.dta", replace

// Plot nominal series 
use "$mainpath/inputs/mean_indices_allparts.dta", clear
summarize mean_nom_3ma adj_nom_3ma nom_full_3ma nom_full5_3ma index_nom

graph twoway (line mean_nom_3ma adj_nom_3ma nom_full_3ma nom_full5_3ma index_nom ym, /// 
    lcolor(red blue green orange black) ///
    lwidth(medium medium medium medium medium) ///
    lpattern(solid dash dash_dot longdash twodash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Unadjusted mean"      ///
                 2 "Demographic‐adjusted mean"        ///
                 3 "33rd-percentile imputed mean"    ///
                 4 "50th‐percentile imputed mean"    ///
                 5 "Panel index") size(small) position(6) row(2) col(3) rowgap(5)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023", format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly mean wage index") ylab(0.9(0.1)1.3, nogrid) ///
	title("Normalized three-month moving average nominal mean indices (CPS workers only, 2016-2024)", size(medsmall)) ///
    subtitle("Normalized to Jan 2016 = 1. Panel index measures one‐year‐apart wage changes controlling for individual fixed effect.", size(small)) ///
)
graph export "$mainpath/outputs/plot_3ma_allparts_nominal_mean.pdf", as(pdf) name("Graph") replace

// Plot real series 
use "$mainpath/inputs/mean_indices_allparts.dta", clear
summarize mean_real_3ma adj_real_3ma real_full_3ma real_full5_3ma index_real

graph twoway (line mean_real_3ma adj_real_3ma real_full_3ma real_full5_3ma index_real ym, /// 
    lcolor(red blue green orange black) ///
    lwidth(medium medium medium medium medium) ///
    lpattern(solid dash dash_dot longdash twodash) ///
    xscale(range(672 758)) ///  
    legend(order (1 "Unadjusted mean"      ///
                 2 "Demographic‐adjusted mean"        ///
                 3 "33rd-percentile imputed mean"    ///
                 4 "50th‐percentile imputed mean"    ///
                 5 "Panel index") size(small) position(6) row(2) col(3) rowgap(5)) ///
    xlabel(672 "2016" 684 "2017" 696 "2018" 708 "2019" 720 "2020" ///
           732 "2021" 744 "2022" 756 "2023", format(%tdCCYY) nogrid) ///  
    xtitle("year") ytitle("monthly mean wage index") ylab(0.8(0.1)1.2, nogrid) ///
	title("Normalized three-month moving average real mean indices (CPS workers only, 2016-2024)", size(medsmall)) ///
    subtitle("Normalized to Jan 2016 = 1. Panel index measures one‐year‐apart wage changes controlling for individual fixed effect.", size(small)) ///
)
graph export "$mainpath/outputs/plot_3ma_allparts_real_mean.pdf", as(pdf) name("Graph") replace

***********************************************************************************************************************************

log close


