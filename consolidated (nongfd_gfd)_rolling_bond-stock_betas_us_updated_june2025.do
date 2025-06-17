// consolidate GFD and Non-GFD betas for US producing a combined dataset for each frequency (daily and quarterly)
set scheme AC, permanently
global mainpath "/Users/yunliu/Desktop/Research/Uchicago/Bond_Stock_Betas"
 

//load non-gfd betas 

	*update the us yields 
    do "$mainpath/code/master_script_automate_update_us_yields.do"
	
	*merge updated datasets 
	use "$mainpath/inputs/Nominal1961_2025.dta", clear
    gsort Date
	merge 1:1 Date using "$mainpath/inputs/TIPS1999_2025.dta"
    drop _merge
	gsort Date
	rename Date date
    merge 1:1 date using "$mainpath/inputs/sp500_us_gfd.dta"
    drop _merge
	gsort date
    merge 1:1 date using "$mainpath/inputs/inflation_swaps.dta" 
    drop _merge
	
	keep date SVENY10 TIPSY10 BKEVEN10 sp500 retsp usswi
    order date SVENY10 TIPSY10 BKEVEN10 sp500 retsp usswi
    rename retsp vwretd
    gsort date
    gen year = year(date)
    gen quarter = qofd(date)
	save "$mainpath/inputs/gsw_vwretd_updated_june2025.dta", replace

	*generate term structure of covariances
	use "$mainpath/inputs/gsw_vwretd_updated_june2025.dta", clear 
	
    lab var SVENY10 "US Nominal 10 YR"
	lab var TIPSY10 "US TIPS 10 YR"
    lab var BKEVEN10 "US Breakeven 10 YR"
	lab var usswi "US Swap Rate 10YR"
	lab var date "Date"
	
	tsset date
	local i = 10
	gen ry`i' = -s.SVENY`i'*`i'
	gen rtips`i' = -s.TIPSY`i'*`i'
	gen rby`i' = -s.BKEVEN`i'*`i'

	gen cov_ry`i'= ry`i'*vwretd
	gen cov_by`i'= rby`i'*vwretd
	gen cov_bry`i'= rby`i'*ry`i'
	gen var_ry`i' = ry`i'^2
	gen var_by`i' = rby`i'^2
	
	gen rswit10 = -s.usswi*10 
	gen cov_rsw10  = rswit10 * vwretd     
    gen var_rsw10  = rswit10^2            
    gen cov_brsw10 = rby10 * rswit10
    
	replace vwretd=vwretd*100
	
	*rolling regressions //
	foreach var of varlist ry10 rtips10 rby10 rswit10 {
      
	*create master list that will hold one pathname per variable
      preserve
	  gsort date 
      tsset date 
      
      *perform a rolling regression over a 90-day window
      rolling _b _se, window(90) clear: regress `var' vwretd, ro
      
      *rename regression outputs for clarity
      rename end date
      rename _b_vwretd b_`var'
      rename _se_vwretd se_`var'
      
      *create upper and lower bounds for a 90% confidence interval
      gen b_`var'_upper=b_`var'+1.64*se_`var'
      gen b_`var'_lower=b_`var'-1.64*se_`var'
      
      *label the variables for better graph interpretation
      lab var b_`var' "Beta `var'"
      lab var b_`var'_upper "90% CI"
      lab var b_`var'_lower "90% CI"
	  
	  *sort + save results 
	  gsort date
      save "$mainpath/inputs/rolling_`var'_90d.dta", replace
	  restore
    }
   
   *merge the datasets to generate daily betas dataset 
   gsort date 
   merge date using "$mainpath/inputs/rolling_ry10_90d.dta"
   drop _merge
   gsort date
   merge date using "$mainpath/inputs/rolling_rtips10_90d.dta"
   drop _merge
   gsort date
   merge date using "$mainpath/inputs/rolling_rby10_90d.dta"
   drop _merge
   gsort date
   merge date using "$mainpath/inputs/rolling_rswit10_90d.dta"
   drop _merge
   
   *create lagged versions of variables to handle missing data in rolling analysis
   tsset date 
   gen b_rtips10_lag=L90.b_rtips10
   gen b_ry10_lag=L90.b_ry10
   gen b_rby10_lag=L90.b_rby10
   gen b_rswit10_lag =L90.b_rswit10
   
   *replace values with missing if lagged values are missing 
   foreach x in ry10 rby10 rtips10 rswit10 {
      replace b_`x'        = . if b_`x'_lag==.
      replace b_`x'_upper  = . if b_`x'_lag==.
      replace b_`x'_lower  = . if b_`x'_lag==.
    }
   
   *babel final variables for interpretability in plots and analyses
   lab var b_rtips10 "TIPS Bond-Stock Beta"
   lab var b_ry10 "Nominal Bond-Stock Beta"
   lab var b_rby10 "Breakeven-Stock Beta"
   lab var b_ry10_upper "90% CI"
   lab var b_ry10_lower "90% CI"
   lab var date "Date"
   
   *generate a zero line for plotting reference
   gen zero=0 

   save "$mainpath/inputs/betas_rolling_90d.dta", replace 
   
   *resample to generate quarterly betas dataset    
    tempfile ry10_q rtips10_q rby10_q rswit10_q
    local tfiles "`ry10_q' `rtips10_q' `rby10_q' `rswit10_q'"
    
    local i = 1
    foreach var in ry10 rtips10 rby10 rswit10 {
        
        use "$mainpath/inputs/rolling_`var'_90d.dta", clear
        
        * Sory by quarter
    	capture confirm variable quarter  
    	if _rc {
            gen quarter = qofd(date)          
        }
        
        format quarter %tq
        sort quarter date
    
        * Keep last beta per quarter
        by quarter (date): gen is_qend = (_n == _N)
        keep if is_qend
        drop is_qend
    	keep date quarter b_`var'*
    
        local tf : word `i' of `tfiles'
        save "`tf'", replace
        local ++i
    }
    
    * Merge quarterly datasets
    use "`ry10_q'", clear
    merge 1:1 date using "`rtips10_q'", nogen
    merge 1:1 date using "`rby10_q'",  nogen
    merge 1:1 date using "`rswit10_q'",   nogen
    
    * Deduplicate to one obs per quarter 
    gen qtr = qofd(date)
    bysort qtr (date): keep if _n == _N
    isid qtr
	
	save "$mainpath/inputs/betas_rolling_qendsample_90d.dta", replace 


//load gfd betas 

	************ Data prepartion ************
    //Nominal Bond Yields
    import excel "$mainpath/inputs/us_nominal_1962_2025.xlsx", sheet("Price Data") firstrow
    rename Close nyus
    gen date = date(Date, "MDY")
    format date %tdNN/DD/CCYY
    drop Date
    order date nyus
    save "$mainpath/inputs/nominal_us_gfd.dta", replace 
    
    //Inflation-Indexed Yields
    import excel "$mainpath/inputs/us_inflation_indexed_1997_2025.xlsx", sheet("Price Data") firstrow clear
    rename Close iiyus
    gen date = date(Date, "MDY")
    format date %tdNN/DD/CCYY
    drop Date
    order date iiyus
    save "$mainpath/inputs/inflation_indexed_us_gfd.dta", replace 

    //SP500 Composite Price Index
    import excel "$mainpath/inputs/sp500_1928_2025.xlsx", sheet("Price Data") firstrow clear
    rename Close sp500
    gen date = date(Date, "MDY")
    format date %tdNN/DD/CCYY
    drop Date
    order date sp500
    gsort date
    tsset date
    gen retsp=(sp500-L.sp500)/L.sp500 
    save "$mainpath/inputs/sp500_us_gfd.dta", replace  

    //Inflation-Linked Swap Rates
    import excel "$mainpath/inputs/Inflation Swap Rates_Bloomberg_06032025.xlsx", sheet("Summary Table") firstrow clear
    rename BPSWIT10BGNCurncy ukswi
    rename EUSWI10BGNCurncy euswi
    rename USSWIT10BGNCurncy usswi
    rename Date date
    drop E F 
    save "$mainpath/inputs/inflation_swaps.dta", replace  

    //Merge datasets
    use "$mainpath/inputs/nominal_us_gfd.dta", clear
    gsort date
    merge 1:1 date using "$mainpath/inputs/inflation_indexed_us_gfd.dta"
    drop _merge
    merge 1:1 date using "$mainpath/inputs/sp500_us_gfd.dta"
    drop _merge
    merge 1:1 date using "$mainpath/inputs/inflation_swaps.dta"
    drop _merge
    
    rename retsp vwretd
    gsort date
    gen year = year(date)
    gen quarter = qofd(date)
    save "$mainpath/inputs/gfd_vwretd_us.dta", replace 

    ************ Generate term structure of covariances ************
    use "$mainpath/inputs/gfd_vwretd_us.dta", clear
    
    * Generate breakeven yield 10Y
    gen bk10yus= nyus - iiyus
    
    * Generate labels
    lab var nyus "GFD US Nominal 10 YR"
    lab var iiyus "GFD US TIPS 10 YR"
    lab var bk10yus "GFD US Breakeven 10 YR"
    lab var usswi "GFD US Swap Rate 10YR"
    lab var date "Date"
    
    * Set data as time-series on a daily frequency
    tsset date
    
    * Generate new variables for term structure calculations 
    gen rswit10 = -s.usswi*10
    
    * Compute bond returns for par yields from GFD
    *returns using approximate duration, where nom_bond10 i 10-year yield from GFD
    gen dur10_nominal=(1-(1+nyus/100)^(-10))/(1-(1+nyus/100)^(-1))
    gen ry10GFD=-s.nyus*L.dur10_nominal
    
    gen dur10_real=(1-(1+iiyus/100)^(-10))/(1-(1+iiyus/100)^(-1))
    gen rtips10GFD=-s.iiyus*L.dur10_real
    
    gen dur10_bk=(1-(1+bk10yus/100)^(-10))/(1-(1+bk10yus/100)^(-1))
    gen rby10GFD=-s.bk10yus*L.dur10_bk
    
    tsset date 
    
    * Adjust market return variable to express it in percentage terms
    replace vwretd=vwretd*100
    
    * Generate covariances
    gen cov_ry10= ry10GFD*vwretd
    gen cov_by10= rby10GFD*vwretd
    gen cov_bry10= rby10GFD*ry10GFD
    gen var_ry10 = ry10GFD^2
    gen var_by10 = rby10GFD^2
    gen cov_rsw10  = rswit10 * vwretd    
    gen var_rsw10  = rswit10^2            
    gen cov_brsw10 = rby10GFD * rswit10      
    
    ************** Rolling Regressions ************** //
    foreach var of varlist ry10GFD rtips10GFD rby10GFD rswit10 {
    
    preserve
    gsort date 
    tsset date 
    
    * Perform a rolling regression over a 90-day window
    rolling _b _se, window(90) clear: regress `var' vwretd, ro
    
    * Rename regression outputs for clarity
    rename end date
    rename _b_vwretd b_`var'
    rename _se_vwretd se_`var'
    
    * Create upper and lower bounds for a 90% confidence interval
    gen b_`var'_upper=b_`var'+1.64*se_`var'
    gen b_`var'_lower=b_`var'-1.64*se_`var'
    
    * Label the variables for better graph interpretation
    lab var b_`var' "Beta `var'"
    lab var b_`var'_upper "90% CI"
    lab var b_`var'_lower "90% CI"
    
    * Sort and save the results
    gsort date
    save "$mainpath/inputs/rolling_`var'_90d_us.dta", replace
    restore
    	
    }
    
    ******* Merge datasets  ***********
    * Merge results from different rolling regressions for combined analysis
    gsort date 
    merge date using "$mainpath/inputs/rolling_ry10GFD_90d_us.dta"
    drop _merge
    gsort date
    merge date using "$mainpath/inputs/rolling_rtips10GFD_90d_us.dta"
    drop _merge
    gsort date
    merge date using "$mainpath/inputs/rolling_rby10GFD_90d_us.dta"
    drop _merge
    gsort date
    merge date using "$mainpath/inputs/rolling_rswit10_90d_us.dta"
    drop _merge
    gsort date
    tsset date 
    * Create lagged versions of variables to handle missing data in rolling analysis
    gen b_rtips10GFD_lag=L90.b_rtips10GFD
    gen b_ry10GFD_lag=L90.b_ry10GFD
    gen b_rby10GFD_lag=L90.b_rby10GFD
    gen b_rswit10_lag =L90.b_rswit10
    
    * Replace values with missing if lagged values are missing 
    replace b_rtips10GFD=. if b_rtips10GFD_lag==.
    replace b_ry10GFD=. if b_ry10GFD_lag==.
    replace b_rby10GFD=. if b_rby10GFD_lag==.
    replace b_rswit10=. if b_rswit10_lag==.
    
    replace b_rtips10GFD_upper=. if b_rtips10GFD_lag==.
    replace b_ry10GFD_upper=. if b_ry10GFD_lag==.
    replace b_rby10GFD_upper=. if b_rby10GFD_lag==.
    replace b_rswit10_upper=. if b_rswit10_lag==.
    
    replace b_rtips10GFD_lower=. if b_rtips10GFD_lag==.
    replace b_ry10GFD_lower=. if b_ry10GFD_lag==.
    replace b_rby10GFD_lower=. if b_rby10GFD_lag==.
    replace b_rswit10_lower=. if b_rswit10_lag==.
    
    * Label final variables for interpretability in plots and analyses
    lab var b_rtips10GFD "TIPS Bond-Stock Beta"
    lab var b_ry10GFD "Nominal Bond-Stock Beta"
    lab var b_rby10GFD "Breakeven-Stock Beta"
    lab var b_ry10GFD_upper "90% CI"
    lab var b_ry10GFD_lower "90% CI"
    lab var date "Date"
    gen zero=0 
    
    * Save the final combined daily dataset
    save "$mainpath/inputs/betas_rolling_90d_us_gfd.dta", replace 
    
    ******* Resample series from daily to quarter-end ***********
    * tempfiles 
    tempfile ry10GFD_q rtips10GFD_q rby10GFD_q rswit10_q
    local tfiles "`ry10GFD_q' `rtips10GFD_q' `rby10GFD_q' `rswit10_q'"
    
    * Resample daily rolling betas to quarter-end points
    local i = 1
    foreach var in ry10GFD rtips10GFD rby10GFD rswit10 {
        
        use "$mainpath/inputs/rolling_`var'_90d_us.dta", clear
        
        * Sory by quarter
    	capture confirm variable quarter  
    	if _rc {
            gen quarter = qofd(date)          
        }
        
        format quarter %tq
        sort quarter date
    
        * Keep last beta per quarter
        by quarter (date): gen is_qend = (_n == _N)
        keep if is_qend
        drop is_qend
    	keep date quarter b_`var'*
    
        local tf : word `i' of `tfiles'
        save "`tf'", replace
        local ++i
    }
    
    * Merge quarterly datasets
    use "`ry10GFD_q'", clear
    merge 1:1 date using "`rtips10GFD_q'", nogen
    merge 1:1 date using "`rby10GFD_q'",  nogen
    merge 1:1 date using "`rswit10_q'",   nogen
    
    * Deduplicate to one obs per quarter 
    gen qtr = qofd(date)
    bysort qtr (date): keep if _n == _N
    isid qtr
	
    * Save final quarterly dataset
    save "$mainpath/inputs/betas_rolling_us_qendsample_90d_gfd.dta", replace 


//merge datasets 

*daily frequency
use "$mainpath/inputs/betas_rolling_90d_us_gfd.dta", clear 
*rename for the merge 
	drop year start zero E F
    rename sp500     sp500_gfd
    rename vwretd    vwretd_gfd
    rename usswi     usswi_gfd
	rename b_rswit10       b_rswit10GFD
    rename b_rswit10_lower b_rswit10GFD_lower
    rename b_rswit10_upper b_rswit10GFD_upper
    rename b_rswit10_lag   b_rswit10GFD_lag
    rename se_rswit10      se_rswit10GFD
merge 1:1 date using "$mainpath/inputs/betas_rolling_90d.dta"
save "$mainpath/inputs/consolidated_gfd_nongfd_rolling_betas_us_daily.dta", replace 


*quarterly frequency
use "$mainpath/inputs/betas_rolling_us_qendsample_90d_gfd.dta", clear 
rename b_rswit10       b_rswit10GFD
rename b_rswit10_lower b_rswit10GFD_lower
rename b_rswit10_upper b_rswit10GFD_upper
drop qtr
sort date quarter
merge 1:1 date quarter using "$mainpath/inputs/betas_rolling_qendsample_90d.dta"
save "$mainpath/inputs/consolidated_gfd_nongfd_rolling_betas_us_quarterly.dta", replace 




