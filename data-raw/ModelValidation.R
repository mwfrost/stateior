### State Supply Model
# Define year
year <- 2015
# Load US Make and Use
US_Summary_Make <- getNationalMake("Summary", year)
US_Summary_Use <- getNationalUse("Summary", year)
US_Summary_DomesticUse <- estimateUSDomesticUse("Summary", year)
# Load state Make, industry and commodity output
State_Summary_Make_ls <- get(paste0("State_Summary_Make_", year),
                             as.environment("package:stateior"))
State_Summary_IndustryOutput_ls <- get(paste0("State_Summary_IndustryOutput_", year),
                                       as.environment("package:stateior"))
State_Summary_CommodityOutput_ls <- get(paste0("State_Summary_CommodityOutput_", year),
                                        as.environment("package:stateior"))
states <- names(State_Summary_Make_ls)
# Load state total Use and domestic Use
State_Summary_Use_ls <- get(paste0("State_Summary_Use_", year),
                            as.environment("package:stateior"))
State_Summary_DomesticUse_ls <- get(paste0("State_Summary_DomesticUse_", year),
                                    as.environment("package:stateior"))
# Build two-region tables
TwoRegionTable_ls <- list()
for (state in states[states!="Overseas"]) {
  # Prepare domestic 2-region Use tables
  TwoRegionTable_ls[[state]] <- buildTwoRegionDemandModel(state, year,
                                                          ioschema = 2012,
                                                          iolevel = "Summary")
}

#' 1. Sum of each cell across all state Make tables must almost equal
#' (tolerance is 1E-3) the same cell in US Make table.
# Prepare df0 and df1
df0 <- US_Summary_Make
df1 <- Reduce("+", State_Summary_Make_ls)
rownames(df1) <- gsub(".*\\.", "", rownames(df1))
df1 <- df1[rownames(df0), colnames(df0)]
# Compare aggregated state Make against US Make
failures <- formatValidationResult(df1-df0, abs_diff = TRUE, tolerance = 1E-3)[["Failure"]]

#' 2. There should not be any negative values in state Make table.
#' Only exception being Overseas, which isn’t used for further calculations,
#' and if the same cell in US Make table is also negative.
# Check if there are negative values in US Make table
US_failures <- formatValidationResult(US_Summary_Make-abs(US_Summary_Make),
                                      abs_diff = TRUE, tolerance = 0)[["Failure"]]
colnames(US_failures) <- c("Industry", "Commodity")
# Validate Make table and extract failures for each state
failures <- data.frame()
for (state in states[states!="Overseas"]) {
  df <- as.data.frame(State_Summary_Make_ls[[state]])
  # Check if there is zero in state Make table
  failures_state <- formatValidationResult(df-abs(df), abs_diff = TRUE,
                                           tolerance = 0)[["Failure"]]
  colnames(failures_state) <- c("Industry", "Commodity")
  # If failure is in US Make table, remove it from state failures
  failures_state$index <- paste(sub(".*\\.", "", failures_state$Industry),
                                failures_state$Commodity)
  US_state_diff <- setdiff(failures_state$index,
                           paste(US_failures$Industry, US_failures$Commodity))
  failures_state <- failures_state[failures_state$index%in%US_state_diff, ]
  failures_state$index <- rownames(failures_state) <- NULL
  failures <- rbind(failures, failures_state)
}

#' 3. Sum of each industry's output across all states must almost equal
#' (tolerance is 1E-3) industry output in US Make Table.
df0 <- as.data.frame(rowSums(US_Summary_Make))
df1 <- Reduce("+", State_Summary_IndustryOutput_ls)
rownames(df1) <- gsub(".*\\.", "", rownames(df1))
df1 <- df1[rownames(df0), ]
# Compare aggregated state industry output against US industry output
failures <- formatValidationResult(df1-df0, abs_diff = TRUE, tolerance = 1E-3)[["Failure"]]
colnames(failures) <- c("Industry", "")

#' 4. Sum of each commodity’s output across all states must almost equal
#' (tolerance is 1E-3) commodity output in US Make Table.
df0 <- as.data.frame(colSums(US_Summary_Make))
df1 <- Reduce("+", State_Summary_CommodityOutput_ls)
rownames(df1) <- gsub(".*\\.", "", rownames(df1))
df1 <- df1[rownames(df0), ]
# Compare aggregated state commodity output against US commodity output
failures <- formatValidationResult(df1-df0, abs_diff = TRUE, tolerance = 1E-3)[["Failure"]]
colnames(failures) <- c("Commodity", "")

#' 5. Sum of each commodity’s output across all states must almost equal
#' (tolerance is 1.11E7, or $11.1 million by commodity) commodity output
#' in US Use Table minus International Imports (commodity specific).
#' Even if the threshold is met, track the difference for each commodity
#' Save result as a type of quality control check.
df0 <- as.data.frame(rowSums(US_Summary_DomesticUse))
df1 <- Reduce("+", State_Summary_CommodityOutput_ls)
rownames(df1) <- gsub(".*\\.", "", rownames(df1))
df1 <- df1[rownames(df0), ]
# Compare aggregated state commodity output against row sum of US domestic Use
failures <- formatValidationResult(df1-df0, abs_diff = TRUE, tolerance = 1.11E7)[["Failure"]]
colnames(failures) <- c("Commodity", "")

#' 6. All cells that are zero in US Make table must remain zero in state Make tables.
# Find zero values in US Make table
US_zeros <- formatValidationResult(US_Summary_Make-0, abs_diff = TRUE,
                                   tolerance = 0)[["Pass"]]
colnames(US_zeros) <- c("Industry", "Commodity")
failures <- data.frame()
for (state in states) {
  # Find zero values in state Make table
  state_zeros <- formatValidationResult(State_Summary_Make_ls[[state]]-0,
                                        abs_diff = TRUE, tolerance = 0)[["Pass"]]
  colnames(state_zeros) <- c("Industry", "Commodity")
  state_zeros$index <- paste(sub(".*\\.", "", state_zeros$Industry), state_zeros$Commodity)
  # Find difference between state_zeros and US_zeros: zeros in US that are not zeros in state
  US_state_diff <- setdiff(paste(US_zeros$Industry, US_zeros$Commodity), state_zeros$index)
  failures_state <- state_zeros[state_zeros$index%in%US_state_diff, ]
  failures_state$index <- rownames(failures_state) <- NULL
  failures <- rbind(failures, failures_state)
}

#' 7. Sum of each cell across all state Use tables must almost equal
#' (tolerance is 1E-1) the same cell in US Use table.
#' This validates that Total state demand == Total national demand.
# Create a function to implement the validation
validateStateUseAgainstNationlUse <- function(domestic = FALSE) {
  if (domestic) {
    Use_ls <- State_Summary_DomesticUse_ls
    df0 <- US_Summary_DomesticUse
  } else {
    Use_ls <- State_Summary_Use_ls
    df0 <- US_Summary_Use
  }
  df1 <- Reduce("+", Use_ls)
  rownames(df1) <- gsub(".*\\.", "", rownames(df1))
  df1 <- df1[rownames(df0), ]
  # Compare aggregated state Use table against US Use table
  failures <- formatValidationResult(df1-df0, abs_diff = TRUE, tolerance = 1E6)[["Failure"]]
  rownames(failures) <- NULL
  colnames(failures) <- c("Commodity", "Industry/Final Demand")
  return(failures)
}
StateUseValidationFailures <- validateStateUseAgainstNationlUse(domestic = FALSE)
StateDomesticUseValidationFailures <- validateStateUseAgainstNationlUse(domestic = TRUE)

#' 8. If SoI commodity output == 0, SoI2SoI ICF ratio == 0
failures <- c()
for (state in states[states!="Overseas"]) {
  # Find zero values in SoI commodity output
  CO_zeros <- formatValidationResult(State_Summary_CommodityOutput_ls[[state]]-0,
                                     abs_diff = TRUE, tolerance = 0)[["Pass"]]
  colnames(CO_zeros) <- c("Commodity", "")
  # Find zero values in SoI2SoI ICF ratio
  ICF <- generateDomestic2RegionICFs(state, year, ioschema = 2012, iolevel = "Summary",
                                     ICF_sensitivity_analysis = FALSE, adjust_by = 0)
  SoI2SoI_ICF_zeros <- ICF[ICF$SoI2SoI==0, 1]
  # Find difference between SoI2SoI_ICF_zeros and CO_zeros:
  # zeros in CO that are not zeros in SoI2SoI_ICF
  diff <- setdiff(CO_zeros$Commodity, SoI2SoI_ICF_zeros)
  failures_state <- SoI2SoI_ICF_zeros[SoI2SoI_ICF_zeros%in%diff]
  failures <- c(failures, failures_state)
}

#' 9. SoI and RoUS interregional exports >= 0, interregional imports >= 0
failures <- data.frame()
for (state in states[states!="Overseas"]) {
  # Prepare domestic 2-region Use tables
  TwoRegionTable_state <- TwoRegionTable_ls[[state]]
  df <- cbind(TwoRegionTable_state[["SoI2SoI"]][, c("InterregionalImports", "InterregionalExports")],
              TwoRegionTable_state[["RoUS2RoUS"]][, c("InterregionalImports", "InterregionalExports")])
  df <- as.data.frame(sapply(df, round, 1))
  rownames(df) <- rownames(TwoRegionTable_state[["SoI2SoI"]])
  colnames(df) <- paste(rep(paste(state, c("SoI2SoI", "RoUS2RoUS"), sep = "_"), each = 2),
                        colnames(df), sep = "$")
  # Compare SoI and RoUS interregional exports and imports against 0
  failures_state <- formatValidationResult(abs(df)-df, abs_diff = FALSE, tolerance = 1E-3)[["Failure"]]
  failures <- rbind(failures, failures_state)
}

#' 10. SoI net exports + RoUS net exports == 0
failures <- data.frame()
for (state in states[states!="Overseas"]) {
  # Prepare domestic 2-region Use tables
  TwoRegionTable_state <- TwoRegionTable_ls[[state]]
  df <- TwoRegionTable_state[["SoI2SoI"]][, "NetExports", drop = FALSE] +
    TwoRegionTable_state[["RoUS2RoUS"]][, "NetExports", drop = FALSE]
  df <- as.data.frame(sapply(df, round, 1))
  rownames(df) <- rownames(TwoRegionTable_state[["SoI2SoI"]])
  # Compare SoI net exports + RoUS net exports against 0
  failures_state <- formatValidationResult(df, abs_diff = TRUE, tolerance = 0)[["Failure"]]
  failures <- rbind(failures, failures_state)
}

#' 11. Check row sum of SoI2SoI <= state commodity supply.
#' Row sum of RoUS2RoUS <= national commodity supply.
failures <- data.frame()
for (state in states[states!="Overseas"]) {
  # Prepare state commodity supply
  df0 <- cbind.data.frame(State_Summary_CommodityOutput_ls[[state]][, "Output", drop = FALSE],
                          colSums(US_Summary_Make))
  colnames(df0) <- c("StateCommOutput", "USCommOutput")
  df0$RoUSCommOutput <- df0$USCommOutput - df0$StateCommOutput
  df0$USCommOutput <- NULL
  # Prepare domestic 2-region Use tables
  TwoRegionTable_state <- TwoRegionTable_ls[[state]]
  columns <- c(getVectorOfCodes("Summary", "Industry"), getFinalDemandCodes("Summary"), "ExportResidual")
  df1 <- cbind.data.frame(rowSums(TwoRegionTable_state[["SoI2SoI"]][, columns]),
                          rowSums(TwoRegionTable_state[["RoUS2RoUS"]][, columns]))
  colnames(df1) <- c(state, paste0(state, "'s RoUS"))
  # Compare row sum of SoI2SoI against state commodity supply
  failures_state <- formatValidationResult(df1 - df0, abs_diff = FALSE,
                                           tolerance = 1E7)[["Failure"]]
  failures <- rbind(failures, failures_state)
}

#' 12. Value in SoI2SoI and RoUS2RoUS can be negative only when the same cell is negative in national Use table
# Find negative values in US Use table
US_negatives <- formatValidationResult(abs(US_Summary_DomesticUse) - US_Summary_DomesticUse,
                                       abs_diff = FALSE, tolerance = 0)[["Failure"]]
colnames(US_negatives) <- c("Commodity", "Industry")
# Validate the position of zero values in state Make tables
failures <- data.frame()
for (state in states[states!="Overseas"]) {
  # Prepare domestic 2-region Use tables
  TwoRegionTable_state <- TwoRegionTable_ls[[state]]
  columns <- c(getVectorOfCodes("Summary", "Industry"), getFinalDemandCodes("Summary"))
  # Find negative values in SoI2SoI Use table
  df_SoI <- TwoRegionTable_state[["SoI2SoI"]][, columns]
  SoI_negatives <- formatValidationResult(abs(df_SoI) - df_SoI, abs_diff = FALSE,
                                          tolerance = 0)[["Failure"]]
  colnames(SoI_negatives) <- c("Commodity", "Industry")
  SoI_negatives$index <- paste(SoI_negatives$Commodity, SoI_negatives$Industry)
  SoI_negatives$table <- paste(state, "SoI2SoI Use")
  # Find difference between SoI_negatives and US_negatives:
  # negatives in SoI2SoI that are not negatives in US Use
  US_SoI_diff <- setdiff(SoI_negatives$index,
                         paste(US_negatives$Commodity, US_negatives$Industry))
  # Find negative values in RoUS2RoUS Use table
  df_RoUS <- TwoRegionTable_state[["RoUS2RoUS"]][, columns]
  RoUS_negatives <- formatValidationResult(abs(df_RoUS) - df_RoUS, abs_diff = FALSE,
                                           tolerance = 0)[["Failure"]]
  colnames(RoUS_negatives) <- c("Commodity", "Industry")
  RoUS_negatives$index <- paste(RoUS_negatives$Commodity, RoUS_negatives$Industry)
  RoUS_negatives$table <- paste(state, "RoUS2RoUS Use")
  # Find difference between RoUS_negatives and US_negatives:
  # negatives in RoUS2RoUS that are not negatives in US Use
  US_RoUS_diff <- setdiff(RoUS_negatives$index,
                          paste(US_negatives$Commodity, US_negatives$Industry))
  # Compile failures
  failures_state <- rbind(SoI_negatives[SoI_negatives$index%in%US_SoI_diff, ],
                          RoUS_negatives[RoUS_negatives$index%in%US_RoUS_diff, ])
  failures_state$index <- rownames(failures_state) <- NULL
  failures <- rbind(failures, failures_state)
}

#' 13. SoI interregional imports == RoUS interregional exports, or difference <= 1E-3
failures <- data.frame()
for (state in states[states!="Overseas"]) {
  # Prepare domestic 2-region Use tables
  TwoRegionTable_state <- TwoRegionTable_ls[[state]]
  # Prepare df0 and df1
  df0 <- TwoRegionTable_state[["SoI2SoI"]][, "InterregionalImports", drop = FALSE]
  df1 <- TwoRegionTable_state[["RoUS2RoUS"]][, "InterregionalExports", drop = FALSE]
  # Compare SoI interregional imports against RoUS interregional exports
  failures_state <- formatValidationResult(df0 - df1, abs_diff = FALSE,
                                           tolerance = 1E-3)[["Failure"]]
  if (nrow(failures_state)>0) {
    failures_state$State <- state
  }
  failures <- rbind(failures, failures_state)
}

#' 14. Total state commodity supply == state demand by intermediate consumption,
#' plus final demand (except imports) + Interregional Exports + Export Residual
failures <- data.frame()
for (state in states[states!="Overseas"]) {
  # Prepare domestic 2-region Use tables
  TwoRegionTable_state <- TwoRegionTable_ls[[state]]
  columns <- c(getVectorOfCodes("Summary", "Industry"),
               setdiff(getFinalDemandCodes("Summary"),
                       getVectorOfCodes("Summary", "Import")),
               "InterregionalExports", "ExportResidual")
  # Prepare df0 and df1
  df0 <- State_Summary_CommodityOutput_ls[[state]][, "Output", drop = FALSE]
  df1 <- as.data.frame(rowSums(TwoRegionTable_state[["SoI2SoI"]][, columns]))
  # Compare state commodity supply against state demand by intermediate consumption,
  # plus final demand (except imports) + Interregional Exports
  failures_state <- formatValidationResult(df0 - df1, abs_diff = TRUE,
                                           tolerance = 1E-3)[["Failure"]]
  if (nrow(failures_state)>0) {
    failures_state$State <- state
  }
  failures <- rbind(failures, failures_state)
}

#' 15. Number of negative cells in SoI2SoI, SoI2RoUS, RoUS2SoI and RoUS2RoUS <=
#' Number of negative cells in national Use table
# Find number of negative cells in US Use table
US_negatives <- formatValidationResult(abs(US_Summary_DomesticUse) - US_Summary_DomesticUse,
                                       abs_diff = FALSE, tolerance = 0)[["Failure"]]
colnames(US_negatives) <- c("Commodity", "Industry")
failure <- data.frame()
for (state in states[states!="Overseas"]) {
  # Prepare domestic 2-region Use tables
  TwoRegionTable_state <- TwoRegionTable_ls[[state]]
  columns <- c(getVectorOfCodes("Summary", "Industry"), getFinalDemandCodes("Summary"))
  failures_state <- data.frame()
  for (table in names(TwoRegionTable_state)[1:4]) {
    # Find number of negative cells in two-region Use table
    df <- TwoRegionTable_state[[table]][, columns]
    state_negatives <- formatValidationResult(abs(df) - df, abs_diff = FALSE,
                                              tolerance = 0)[["Failure"]]
    colnames(state_negatives) <- c("Commodity", "Industry")
    state_negatives$index <- paste(state_negatives$Commodity, state_negatives$Industry)
    state_negatives$table <- paste(state, table, "Use")
    # Find difference between state_negatives and US_negatives:
    # negatives in RoUS2RoUS that are not negatives in US Use
    US_state_diff <- setdiff(state_negatives$index,
                             paste(US_negatives$Commodity, US_negatives$Industry))
    # Compile failures
    failures_table <- state_negatives[state_negatives$index%in%US_state_diff, ]
    failures_table$index <- NULL
    failures_table <- rbind(failures_state, failures_table)
  }
  failures <- rbind(failures, failures_state)
}

#' 16. Non-square model verification
#' Validate L matrix of two-region model and final demand against SoI and RoUS output.
#' @param state A text value specifying state of interest.
#' @param year A numeric value between 2007 and 2017 specifying the year of interest.
#' @param ioschema A numeric value of either 2012 or 2007 specifying the io schema year.
#' @param iolevel BEA sector level of detail, can be "Detail", "Summary", or "Sector".
#' @return A list of validation components and result.
validateTwoRegionLagainstOutput <- function(state, year, ioschema, iolevel) {
  # Define industries and commodities
  industries <- getVectorOfCodes(iolevel, "Industry")
  commodities <- getVectorOfCodes(iolevel, "Commodity")
  logging::loginfo("Generating A matrix of SoI Make table ...")
  # SoI Make
  SoI_Make <- get(paste0("State_Summary_Make_", year),
                  as.environment("package:stateior"))[[state]]
  # SoI commodity output
  SoI_Commodity_Output <- get(paste0("State_Summary_CommodityOutput_", year),
                              as.environment("package:stateior"))[[state]]
  # SoI A matrix
  SoI_A <- useeior:::normalizeIOTransactions(SoI_Make, SoI_Commodity_Output$Output)
  # Check column sums of SoI_A
  if (all(abs(colSums(SoI_A)-1)<1E-3)) {
    logging::loginfo("FACT CHECK: column sums of A matrix of SoI Make table == 1.")
  } else {
    logging::logwarn("Column sums of A matrix of SoI Make table != 1")
  }
  
  logging::loginfo("Generating A matrix of RoUS Make table ...")
  # RoUS Make
  US_Make <- getNationalMake(iolevel, year)
  RoUS_Make <- US_Make - SoI_Make
  # RoUS domestic Use
  SoI_Domestic_Use <- get(paste0("State_Summary_DomesticUse_", year),
                          as.environment("package:stateior"))[[state]]
  columns <- colnames(SoI_Domestic_Use)[!colnames(SoI_Domestic_Use)%in%c("F040", "F050")]
  US_Domestic_Use <- estimateUSDomesticUse("Summary", year)
  RoUS_Domestic_Use <- US_Domestic_Use - SoI_Domestic_Use[commodities, ]
  # RoUS commodity output
  US_Commodity_Output <- colSums(US_Make)
  RoUS_Commodity_Output <- US_Commodity_Output - SoI_Commodity_Output
  colnames(RoUS_Commodity_Output) <- "Output"
  # Adjust RoUS_Commodity_Output
  MakeUseDiff <- US_Commodity_Output - rowSums(US_Domestic_Use[, c(columns, "F040")])
  RoUS_Commodity_Output$Output <- RoUS_Commodity_Output$Output - MakeUseDiff
  # RoUS A matrix
  RoUS_A <- useeior:::normalizeIOTransactions(RoUS_Make, RoUS_Commodity_Output$Output)
  # Check column sums of RoUS_A
  if (all(abs(colSums(RoUS_A)-1)<1E-3)) {
    logging::loginfo("FACT CHECK: column sums of A matrix of RoUS Make table == 1.")
  } else {
    logging::logwarn("Column sums of A matrix of RoUS Make table != 1")
  }
  
  # Two-region A matrix
  logging::loginfo("Generating two-region Domestic Use tables ...")
  ls <- buildTwoRegionDemandModel(state, year, ioschema, iolevel)
  SoI_Industry_Output <- get(paste0("State_Summary_IndustryOutput_", year),
                             as.environment("package:stateior"))[[state]]
  RoUS_Industry_Output <- rowSums(US_Make) - SoI_Industry_Output
  
  logging::loginfo("Generating A matrix of SoI2SoI Domestic Use table ...")
  SoI2SoI_A <- useeior:::normalizeIOTransactions(ls[["SoI2SoI"]][, industries],
                                                 SoI_Industry_Output$Output)
  #### if industry/comm output == 0, the cell in the corresponding column in A matrix
  
  
  logging::loginfo("Generating A matrix of RoUS2SoI Domestic Use table ...")
  RoUS2SoI_A <- useeior:::normalizeIOTransactions(ls[["RoUS2SoI"]][, industries],
                                                  SoI_Industry_Output$Output)
  
  logging::loginfo("Generating A matrix of SoI2RoUS Domestic Use table ...")
  SoI2RoUS_A <- useeior:::normalizeIOTransactions(ls[["SoI2RoUS"]][, industries],
                                                  RoUS_Industry_Output$Output)
 
  logging::loginfo("Generating A matrix of RoUS2RoUS Domestic Use table ...")
  RoUS2RoUS_A <- useeior:::normalizeIOTransactions(ls[["RoUS2RoUS"]][, industries],
                                                   RoUS_Industry_Output$Output)
  
  logging::loginfo("Assembling the complete A matrix ...")
  # Assemble A matrix
  A_top <- cbind(diag(rep(0, length(commodities)*2)),
                 cbind(rbind(SoI2SoI_A, RoUS2SoI_A),
                       rbind(SoI2RoUS_A, RoUS2RoUS_A)))
  colnames(A_top) <- c(1:ncol(A_top))
  A_btm <- cbind.data.frame(as.matrix(Matrix::bdiag(list(as.matrix(SoI_A),
                                                         as.matrix(RoUS_A)))),
                            diag(rep(0, length(industries)*2)))
  A <- as.matrix(rbind(A_top, setNames(A_btm, colnames(A_top))))
  rownames(A) <- paste(c(rep(c(state, "RoUS"), each = length(commodities)),
                         rep(c(state, "RoUS"), each = length(industries))),
                       c(rep(commodities, 2), rep(industries, 2)),
                       c(rep("Commodity", length(commodities)*2),
                         rep("Industry", length(industries)*2)),
                       sep = ".")
  colnames(A) <- rownames(A)
  
  logging::loginfo("Generating the L matrix ...")
  # Calculate L matrix
  I <- diag(nrow(A))
  L <- solve(I - A)
  
  logging::loginfo("Calculating y (Final Dmand totals) of SoI and RoUS ...")
  # Calculate Final Demand (y)
  FD_columns  <- getFinalDemandCodes("Summary")
  SoI2SoI_y   <- rowSums(ls[["SoI2SoI"]][, c(FD_columns, "ExportResidual")])
  SoI2RoUS_y  <- rowSums(ls[["SoI2RoUS"]][, FD_columns])
  RoUS2SoI_y  <- rowSums(ls[["RoUS2SoI"]][, FD_columns])
  RoUS2RoUS_y <- rowSums(ls[["RoUS2RoUS"]][, c(FD_columns, "ExportResidual")])
  y <- c(SoI2SoI_y + SoI2RoUS_y, RoUS2SoI_y + RoUS2RoUS_y, rep(0, length(industries)*2))
  names(y) <- rownames(L)
  
  logging::loginfo("Validating L*y == industry and commodity output ...")
  # Validate L * y == Output
  validation <- as.data.frame(L %*% y - c(SoI_Commodity_Output$Output,
                                          RoUS_Commodity_Output$Output,
                                          SoI_Industry_Output$Output,
                                          RoUS_Industry_Output$Output))
  colnames(validation) <- "L*y-output"
  
  logging::loginfo("Validation complete.")
  return(list(A = A, L = L, y = y, Validation = validation))
}
GA_2r_LagaintsOutput_Validation <- validateTwoRegionLagainstOutput("Georgia", year, ioschema = 2012, "Summary")
MN_2r_LagaintsOutput_Validation <- validateTwoRegionLagainstOutput("Minnesota", year, ioschema = 2012, "Summary")
OR_2r_LagaintsOutput_Validation <- validateTwoRegionLagainstOutput("Oregon", year, ioschema = 2012, "Summary")
WA_2r_LagaintsOutput_Validation <- validateTwoRegionLagainstOutput("Washington", year, ioschema = 2012, "Summary")

#' 17. State domestic Use table estimated using calculateUSDomesticUseRatioMatrix
#' must almost equal (tolerance is 1E-3) that estimated via IntlTransportMargins.
calculateStateDomesticUseviaIntlTransportMargins <- function(state, iolevel, year) {
  # Load US Use and Import tables
  US_Use <- getNationalUse(iolevel, year)
  US_Import <- loadDatafromUSEEIOR(paste(iolevel, "Import", year, "BeforeRedef", sep = "_"))*1E6
  # Calculate SoI Import matrix
  commodities <- getVectorOfCodes(iolevel, "Commodity")
  State_Use <- get(paste0("State_Summary_Use_", year),
                   as.environment("package:stateior"))[[state]][commodities, ]
  State_Import_Matrix <- State_Use * (US_Import[rownames(US_Use), colnames(US_Use)]/US_Use)
  State_Import_Matrix[is.na(State_Import_Matrix)] <- 0
  IntlMarginsRatio <- calculateUSInternationalTransportMarginsRatioMatrix("Summary", year)
  State_IntlMargins_Matrix <- State_Use * IntlMarginsRatio
  State_DomesticUse <- State_Use - State_Import_Matrix + State_IntlMargins_Matrix
  State_DomesticUse[, "F040"] <- State_Use[, "F040"]
  State_DomesticUse[, "F050"] <- 0
  return(State_DomesticUse)
}
SoI_DomesticUse <- State_Summary_DomesticUse_ls[["Georgia"]]
df0 <- SoI_DomesticUse[1:73, ]
df1 <- calculateStateDomesticUseviaIntlTransportMargins("Georgia", "Summary", year)
# Compare SoI domestic Use against calculated SoI domestic Use
failures <- formatValidationResult(df0 - df1, abs_diff = TRUE, tolerance = 1E-3)[["Failure"]]
colnames(failures) <- c("Commodity", "Industry")
