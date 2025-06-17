// automate the update the US yield data using a master script
version 16.1
clear all
set more off
set scheme AC, permanently
global mainpath "/Users/yunliu/Desktop/Research/Uchicago/Bond_Stock_Betas"
cap mkdir "$mainpath/inputs"
cap mkdir "$mainpath/raw"

*—— metadata  ——————————————
local keys   us_nom us_real
local urls   ///
https://www.federalreserve.gov/data/yield-curve-tables/feds200628.csv ///
https://www.federalreserve.gov/data/yield-curve-tables/feds200805.csv
  local raws   feds200628.csv  feds200629.csv
local tidys  Nominal1961_2025.dta  TIPS1999_2025.dta

*—— loop through each series  —————————————————————————————————————————————
local n : word count `keys'
forvalues i = 1/`n' {
    local key  : word `i' of `keys'
    local url  : word `i' of `urls'
    local raw  : word `i' of `raws'
    local tidy : word `i' of `tidys'

    di _n "---- Updating `key' (`raw') ----"

    * 1 download the CSV 
    quietly copy "`url'" "$mainpath/raw/`raw'", replace

    * 2 import from local file 
	if "`key'" == "us_nom" {
    import delimited "$mainpath/raw/`raw'", ///
        varnames(10) case(preserve) clear
        }
    else if "`key'" == "us_real" {
    import delimited "$mainpath/raw/`raw'", ///
        varnames(19) case(preserve) clear
        }
	
    * 3 date fix + dedupe
    capture confirm numeric variable Date
    if _rc  {
        gen double _Date = date(Date,"YMD")
        format _Date %td
		drop Date
		rename _Date Date
        }
	else  format Date %td  
	destring _all, replace force ignore("NA")
	ds BETA* TAU*, has(type string)
    local strvars `r(varlist)'
	if "`strvars'" != "" destring `strvars', replace force ignore("NA")
    sort Date
    duplicates drop Date, force
    tempfile new
    save `new'

    * 4 merge with old tidy 
    if fileexists("$mainpath/inputs/`tidy'") {
        use "$mainpath/inputs/`tidy'", clear
		ds, has(type numeric)             
        local numvars `r(varlist)'
		ds, has(type string)
        local strvars `r(varlist)'
        if "`strvars'" != "" destring `strvars', replace force ignore("NA")
        sort Date
        tempfile old
        save `old', replace
		
        use `new', clear
		destring `numvars', replace force ignore("NA")
		
        merge 1:1 Date using `old', nogen
        sort Date
        duplicates drop Date, force
    }
    compress
    save "$mainpath/inputs/`tidy'", replace
    di "   → `tidy' now has " _N " obs."
}

di _n ">> Incremental update done for `n' series." 

*outputs: up-to-date Nominal1961_2025.dta and TIPS1999_2025.dta 



