###################################################################
# This scripts creates the models used for the analysis, saves them,
# plots them, calculates time taken to fit, RMSE and size of file
###################################################################

  if (!exists("dFolder")){
    dFolder <- "~/HWCanalysis/data/" 
  }
  if (!exists("pFolder")){
    pFolder <- "~/HWCanalysis/plots/" 
  }
  if (!exists("sFolder")){
    sFolder <- "~/HWCanalysis/scripts/" 
  }
  
  source(paste0(sFolder, "plot_model.R"))
  source(paste0(sFolder, "plot_model_SVM.R"))
  library(forecast)
  library(xts)
  library(data.table)
  library(ggplot2)
  library(dplyr)
  library(e1071)
  library(readr)
  
  load(paste0(dFolder, "houses.Rda"))
  
  # Create empty dataframe to full with summary of models
  DFsummary <- data.frame(model=character(),
                          household=character(),
                          RMSE=numeric(),
                          peakRMSE=numeric(),
                          fittingTime=numeric(),
                          memSize=numeric(),
                          stringsAsFactors=FALSE)

  for (house in houses){
#  house <- houses[1]  
  
    dt_fit <- as.data.table(
      read_csv(
        paste0(
          dFolder,"households/fitting/",
          house,"_at_30_min_for_fitting.csv")))
    dt_val <- as.data.table(
      read_csv(
        paste0(
          dFolder,"households/validating/",
          house,"_at_30_min_for_validating.csv")))
    dt_fit$hHour <- lubridate::as_datetime(dt_fit$hHour, 
                                           tz = 'Pacific/Auckland')
    dt_fit$dHour <- hour(dt_fit$hHour) + minute(dt_fit$hHour)/60
    dt_val$hHour <- lubridate::as_datetime(dt_val$hHour, 
                                           tz = 'Pacific/Auckland')
    dt_val$dHour <- hour(dt_val$hHour) + minute(dt_val$hHour)/60
    dt_val$nonHWshift1 <- shift(dt_val$nonHWelec)
    dt_val$nonHWshift2 <- shift(dt_val$nonHWelec, 2)
    dt_val$HWshift1 <- shift(dt_val$HWelec)
    dt_val$HWshift2 <- shift(dt_val$HWelec, 2)
    dt_fit$nonHWshift1 <- shift(dt_fit$nonHWelec)
    dt_fit$nonHWshift2 <- shift(dt_fit$nonHWelec, 2)
    dt_fit$HWshift1 <- shift(dt_fit$HWelec)
    dt_fit$HWshift2 <- shift(dt_fit$HWelec, 2)
    dt_fit[is.na(dt_fit)] <- 0
    dt_val[is.na(dt_val)] <- 0
    ts_fit <- as.xts(dt_fit)
    ts_val <- as.xts(dt_val)
   # ts_fit <- ts_fit[3:nrow(ts_fit), ]
   # ts_val <- ts_val[3:nrow(ts_val), ]
   # dt_fit$dow <- weekdays(dt_fit$hHour)
   # dt_val$dow <- weekdays(dt_val$hHour)
    hw_ts_fit <- ts(dt_fit$HWelec, frequency = 48)
    hw_ts_val <- ts(dt_val$HWelec, frequency = 48)
       
  Model <- "naive"
  print(paste0("Now fitting ", Model, " model for household ", 
               house, "..."))
  fitTime <- system.time( # Fits model and returns time taken to do so
    mdl <- naive(ts_val$HWelec, h = 1))[3] 
  mdl$x <- ts_val$HWelec
  dir.create(paste0(dFolder, "models/", Model,"/"), 
             showWarnings = FALSE)
  saveRDS(mdl, file = paste0(dFolder, "models/", Model,"/", 
                             house, "_validated_model.rds"))
  plotModel(mdl, Model)

  # Create dt of hour + residual
  peakMdl <- as.data.table(cbind(ts_val$dHour, 
                                 mdl$residuals)) 
  names(peakMdl) <- c("dHour", "residuals")
  # Crop to only include peak hour residuals
  peakMdl <- peakMdl[(dHour >= 7 & dHour < 9) |
                       (dHour >= 17 & dHour < 20)] 
  sVec <- data.frame(model=Model,
                     household=house,
                     RMSE=sqrt(mean(mdl$residuals^2, na.rm = TRUE)),
                     peakRMSE = sqrt(mean(peakMdl$residuals^2, 
                                          na.rm = TRUE)),
                     fittingTime = fitTime,
                     memSize=as.numeric(object.size(mdl)),
                     stringsAsFactors=FALSE)
  DFsummary <- rbind(DFsummary, sVec)
  
  Model <- "seasonalNaive"
  print(paste0("Now fitting ", Model, " model for household ", 
               house, "..."))
  ts_val_HW_seasonal <- ts(dt_val$HWelec, frequency = 48)
  fitTime <- system.time( # Fits model and returns time taken to do so
    mdl <- snaive(ts_val_HW_seasonal, h = 1))[3] 
  dir.create(paste0(dFolder, "models/", Model,"/"), 
             showWarnings = FALSE)
  mdl$x <- ts_val$HWelec
  dir.create(paste0(dFolder, "models/", Model,"/"), 
             showWarnings = FALSE)
  saveRDS(mdl, file = paste0(dFolder, "models/", Model,"/", 
                             house, "_validated_model.rds"))
  plotModel(mdl, Model)
  
  # Create dt of hour + residual
  peakMdl <- as.data.table(cbind(ts_val$dHour, mdl$residuals)) 
  names(peakMdl) <- c("dHour", "residuals")
  # Crop to only include peak hour residuals
  peakMdl <- peakMdl[(dHour >= 7 & dHour < 9) | 
                       (dHour >= 17 & dHour < 20)]
  sVec <- data.frame(model = Model,
                     household = house,
                     RMSE = sqrt(mean(mdl$residuals^2, na.rm = TRUE)),
                     peakRMSE = sqrt(mean(peakMdl$residuals^2, 
                                          na.rm = TRUE)),
                     fittingTime = fitTime,
                     memSize = as.numeric(object.size(mdl)),
                     stringsAsFactors=FALSE)
  DFsummary <- rbind(DFsummary, sVec)
  
  Model <- "simpleLinear"
  print(paste0("Now fitting ", Model, " model for household ", 
               house, "..."))
  fitTime <- system.time( # Fits model and returns time taken to do so
    fitMdl <- lm(ts_val$HWelec~ts_val$nonHWshift1 + 
                   ts_val$nonHWshift2))[3] 
  dir.create(paste0(dFolder, "models/", Model,"/"), 
             showWarnings = FALSE)
  saveRDS(fitMdl, file = paste0(dFolder, "models/", Model,"/", 
                                house, "_fitted_model.rds"))
  valMdl <- lm(fitMdl, data = ts_fit)
  valMdl$x <- ts_val$HWelec#[2:nrow(ts_val)]
  saveRDS(valMdl, file = paste0(dFolder, "models/", Model,"/", 
                                house, "_validated_model.rds"))
  plotModel(valMdl, Model)
  # Create dt of hour + residual
  peakMdl <- as.data.table(cbind(ts_val$dHour, valMdl$residuals)) 
  names(peakMdl) <- c("dateTime", "dHour", "residuals")
  # Crop to only include peak hour residuals
  peakMdl <- peakMdl[(dHour >= 7 & dHour < 9) |
                       (dHour >= 17 & dHour < 20)] 
  sVec <- data.frame(model=Model,
                     household=house,
                     RMSE=sqrt(mean(valMdl$residuals^2)),
                     peakRMSE = sqrt(mean(peakMdl$residuals^2, 
                                          na.rm = TRUE)),
                     fittingTime=as.numeric(fitTime),
                     memSize=as.numeric(object.size(fitMdl)),
                     stringsAsFactors=FALSE)
  DFsummary <- rbind(DFsummary, sVec)

  Model <- "ARIMA"
  print(paste0("Now fitting ", Model, " model for household ", 
               house, "..."))
  fitTime <- system.time(# Fits model and returns time taken to do so
    fitArima <- auto.arima(ts_fit$HWelec))[3] 
  dir.create(paste0(dFolder, "models/", Model,"/"), 
             showWarnings = FALSE)
  saveRDS(fitArima, file = paste0(dFolder, "models/", Model,"/", 
                                  house, "_fitted_model.rds"))
  valArima <- Arima(ts_val$HWelec, model = fitArima)
  saveRDS(valArima, file = paste0(dFolder, "models/", Model,"/", 
                                  house, "_validated_model.rds"))
  plotModel(valArima, Model)
  # Create dt of hour + residual
  peakMdl <- as.data.table(cbind(ts_val$dHour, valArima$residuals)) 
  names(peakMdl) <- c("dHour", "residuals")
  # Crop to only include peak hour residuals
  peakMdl <- peakMdl[(dHour >= 7 & dHour < 9) |
                       (dHour >= 17 & dHour < 20)] 
  sVec <- data.frame(model=Model,
                          household=house,
                          RMSE=sqrt(mean(valArima$residuals^2)),
                          peakRMSE = sqrt(mean(peakMdl$residuals^2, 
                                               na.rm = TRUE)),
                          fittingTime=as.numeric(fitTime),
                          memSize=as.numeric(object.size(fitArima)),
                          stringsAsFactors=FALSE)
  DFsummary <- rbind(DFsummary, sVec)
  Par <- as.data.frame(t(arimaorder(fitArima)))
  Par$household <- house
  ifelse(house == houses[1], 
         ARIMApars <- Par,
         ARIMApars <- rbind(ARIMApars, Par))
  if (house == houses[length(houses)]){
    ARIMApars <- ARIMApars[,c("household","p","d","q")]
    write_csv(ARIMApars, path = paste0(dFolder, "models/", 
                                       Model, "/parameters.csv"))
  }
  
  Model <- "ARIMAX"
  print(paste0("Now fitting ", Model, " model for household ", 
               house, "..."))
  fitTime <- system.time(# Fits model and returns time taken to do so
    fitArimaX <- auto.arima(ts_fit$HWelec, 
                            xreg = as.matrix(
                              cbind(ts_fit$nonHWshift1, 
                                    ts_fit$nonHWshift2))))[3] 
  dir.create(paste0(dFolder, "models/", Model,"/"), 
             showWarnings = FALSE)
  saveRDS(fitArimaX, file = paste0(dFolder, "models/", Model,"/", 
                                   house, "_fitted_model.rds"))
  valArimaX <- Arima(ts_val$HWelec, 
                     xreg = as.matrix(
                       cbind(
                         ts_val$nonHWshift1, ts_val$nonHWshift2)),
                     model = fitArimaX)
  saveRDS(valArimaX, file = paste0(dFolder, "models/", Model,"/", 
                                   house, "_validated_model.rds"))
  plotModel(valArimaX, Model)
  # Create dt of hour + residual
  peakMdl <- as.data.table(cbind(ts_val$dHour, valArimaX$residuals)) 
  names(peakMdl) <- c("dHour", "residuals")
  # Crop to only include peak hour residuals
  peakMdl <- peakMdl[(dHour >= 7 & dHour < 9) 
                     | (dHour >= 17 & dHour < 20)] 
  sVec <- data.frame(model=Model,
                     household=house,
                     RMSE=sqrt(mean(valArimaX$residuals^2)),
                     peakRMSE = sqrt(mean(peakMdl$residuals^2, 
                                          na.rm = TRUE)),
                     fittingTime=as.numeric(fitTime),
                     memSize=as.numeric(object.size(fitArima)),
                     stringsAsFactors=FALSE)
  DFsummary <- rbind(DFsummary, sVec)
  Par <- as.data.frame(t(arimaorder(fitArimaX)))
  Par$household <- house
  ifelse(house == houses[1], 
         ARIMAXpars <- Par,
         ARIMAXpars <- rbind(ARIMAXpars, Par))
  if (house == houses[length(houses)]){
    ARIMAXpars <- ARIMAXpars[,c("household","p","d","q")]
    write_csv(ARIMAXpars, path = paste0(dFolder, "models/", 
                                        Model, "/parameters.csv"))
  }
  
  Model <- "STLARIMA"
  print(paste0("Now fitting ", Model, " model for household ", 
               house, "..."))
  fitTime <- system.time(# Fits model and returns time taken to do so
    fitSTLArima <- stlm(hw_ts_fit, s.window = 48, method = "arima"))[3] 
  dir.create(paste0(dFolder, "models/", Model,"/"), 
             showWarnings = FALSE)
  saveRDS(fitSTLArima, file = paste0(dFolder, "models/", Model,"/",
                                     house, "_fitted_model.rds"))
  valSTLArima <- stlm(hw_ts_val, s.window = 48, method = "arima",
                      model = fitSTLArima)
  valSTLArima$hHour <- dt_val$hHour
  saveRDS(valSTLArima, file = paste0(dFolder, "models/", Model,"/", 
                                     house, "_validated_model.rds"))
  plotModel(valSTLArima, Model)
  # Create dt of hour + residual
  peakMdl <- as.data.table(cbind(ts_val$dHour, valSTLArima$residuals)) 
  names(peakMdl) <- c("dHour", "residuals")
  # Crop to only include peak hour residuals
  peakMdl <- peakMdl[(dHour >= 7 & dHour < 9) |
                       (dHour >= 17 & dHour < 20)] 
  sVec <- data.frame(model=Model,
                     household=house,
                     RMSE=sqrt(mean(valSTLArima$residuals^2)),
                     peakRMSE = sqrt(mean(peakMdl$residuals^2, 
                                          na.rm = TRUE)),
                     fittingTime=as.numeric(fitTime),
                     memSize=as.numeric(object.size(fitSTLArima)),
                     stringsAsFactors=FALSE)
  DFsummary <- rbind(DFsummary, sVec)
  Par <- as.data.frame(t(arimaorder(fitSTLArima$model)))
  Par$household <- house
  ifelse(house == houses[1], 
         STL_ARIMApars <- Par,
         STL_ARIMApars <- rbind(STL_ARIMApars, Par))
  if (house == houses[length(houses)]){
    STL_ARIMApars <- STL_ARIMApars[,c("household","p","d","q")]
    write_csv(STL_ARIMApars, path = paste0(dFolder, "models/",  
                                           Model, "/parameters.csv"))
  }
  
  Model <- "STLARIMAX"
  print(paste0("Now fitting ", Model, " model for household ", 
               house, "..."))
  fitTime <- system.time( # Fits model and returns time taken to do so
    fitSTLArimaX <- stlm(hw_ts_fit, 
                         s.window = 48, 
                         method = "arima",
                         xreg = as.matrix(
                           cbind(ts_fit$nonHWshift1, 
                                 ts_fit$nonHWshift2))))[3] 
  dir.create(paste0(dFolder, "models/", Model,"/"), 
             showWarnings = FALSE)
  saveRDS(fitSTLArimaX, file = paste0(dFolder, "models/", Model,"/", 
                                      house, "_fitted_model.rds"))
  valSTLArimaX <- stlm(hw_ts_val, s.window = 48, method = "arima",
                      xreg = as.matrix(cbind(ts_val$nonHWshift1, 
                                             ts_val$nonHWshift2)),
                      model = fitSTLArimaX)
  valSTLArimaX$hHour <- dt_val$hHour
  saveRDS(valSTLArimaX, file = paste0(dFolder, "models/", Model,"/", 
                                      house, "_validated_model.rds"))
  plotModel(valSTLArimaX, Model)
  # Create dt of hour + residual
  peakMdl <- as.data.table(cbind(ts_val$dHour, valSTLArimaX$residuals)) 
  names(peakMdl) <- c("dHour", "residuals")
  # Crop to only include peak hour residuals
  peakMdl <- peakMdl[(dHour >= 7 & dHour < 9) |
                       (dHour >= 17 & dHour < 20)] 
  sVec <- data.frame(model=Model,
                     household=house,
                     RMSE=sqrt(mean(valSTLArimaX$residuals^2)),
                     peakRMSE = sqrt(mean(peakMdl$residuals^2, 
                                          na.rm = TRUE)),
                     fittingTime=as.numeric(fitTime),
                     memSize=as.numeric(object.size(fitSTLArima)),
                     stringsAsFactors=FALSE)
  DFsummary <- rbind(DFsummary, sVec)
  Par <- as.data.frame(t(arimaorder(fitSTLArimaX$model)))
  Par$household <- house
  ifelse(house == houses[1], 
         STL_ARIMAXpars <- Par,
         STL_ARIMAXpars <- rbind(STL_ARIMAXpars, Par))
  if (house == houses[length(houses)]){
    STL_ARIMAXpars <- STL_ARIMAXpars[,c("household","p","d","q")]
    write_csv(STL_ARIMAXpars, path = paste0(dFolder, "models/",  
                                            Model, "/parameters.csv"))
  }
  
  Model <- "SVM"
  print(paste0("Now fitting ", Model, " model for household ", 
               house, "..."))
  fitTime <- system.time(
    fitSVM <- svm(HWelec ~ dHour + nonHWshift1 + nonHWshift2
                  + HWshift1 + HWshift2, dt_fit))[3]
  dir.create(paste0(dFolder, "models/", Model,"/"), 
             showWarnings = FALSE)
  saveRDS(fitSVM, file = paste0(dFolder, "models/", Model,"/", 
                                house, "_fitted_model.rds"))
  # Make prediction on validating data from model
  predicted_values <- predict(fitSVM, dt_val) 
  
  #  Remove first two rows in order to build validated 
  # model format necessary to build plots etc
  val_mdl <- dt_val#[3:nrow(dt_val)] 
  val_mdl <- val_mdl %>%
    select("HWelec", "hHour")
  val_mdl$fitted <- predicted_values
  val_mdl$residual <- val_mdl$HWelec - predicted_values
  names(val_mdl)[names(val_mdl) == 'HWelec'] <- 'x'
  saveRDS(val_mdl, file = paste0(dFolder, "models/", Model,"/", 
                                 house, "_validated_model.rds"))
   plotModel(val_mdl, Model) 
   val_mdl$dHour <- hour(val_mdl$hHour) + minute(val_mdl$hHour)/60
   # Crop to only include peak hour residuals
   peakMdl <- val_mdl[(dHour >= 7 & dHour < 9) | 
                        (dHour >= 17 & dHour < 20)] 
  sVec <- data.frame(model=Model,
                     household=house,
                     RMSE=sqrt(mean(val_mdl$residual^2)),
                     peakRMSE = sqrt(mean(peakMdl$residual^2, 
                                          na.rm = TRUE)),
                     fittingTime=as.numeric(fitTime),
                     memSize=as.numeric(object.size(fitSVM)),
                     stringsAsFactors=FALSE)
  DFsummary <- rbind(DFsummary, sVec)
}

saveRDS(DFsummary, file = paste0(dFolder, "allHouseModelStats.rds"))
#saveRDS(ARIMApars, file = paste0(dFolder, "ARIMA/parameters.rds"))
allHouseSummary <- DFsummary %>%
  group_by(model) %>%
  summarise(RMSE = mean(RMSE), 
            peakRMSE = mean(peakRMSE), 
            fittingTime = mean(fittingTime),
            memSize = mean(memSize))
allHouseSummary$pcErrorIncrease <- 
  100*(allHouseSummary$peakRMSE - allHouseSummary$RMSE)/allHouseSummary$RMSE
saveRDS(allHouseSummary, file = paste0(dFolder, 
                                       "allModelSummaryStats.rds"))