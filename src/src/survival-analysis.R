# ref = https://rviews.rstudio.com/2017/09/25/survival-analysis-with-r/
suppressPackageStartupMessages(library(survival))
suppressPackageStartupMessages(library(ranger))
suppressPackageStartupMessages(library(ggplot2))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(raster))

climate <- function(rst, x, y) {

  xy <- data.frame(x = c(x), y = c(y))
  kg <- raster(rst)
  n_clim <- extract(kg, xy)

  classif <- c('Af', 'Am', 'Aw', 'BWh', 'BWk', 'BSh', 'BSk', 'Csa', 'Csb', 'Cwa', 'Cwb', 'Cwc',
             'Cfa', 'Cfb', 'Cfc', 'Dsa', 'Dsb', 'Dsc', 'Dsd', 'Dwa', 'Dwb', 'Dwc', 'Dwd', 'Dfa',
             'Dfb', 'Dfc', 'Dfd', 'ET', 'EF')

  user_clim <- classif[n_clim]

  return (user_clim)
  
}

what_to_plant <- function(file, climate, date_to_plant, date_to_harvest, size, plot = FALSE ) {

  # read jointly created vegetables table
  plants <- read.table(file, sep = ',', header = T)

  #excluding non-usable data
  plants <- plants[,3:10]
  
  colnames(plants) <- c('name', 'links', 'space', 'when_to_plant', 'min_grow_t', 'max_grow_t', 'when_to_harvest', 'climate')

# mean survival time (discussion required)
  plants$time <- as.numeric(( plants$max_grow_t + plants$min_grow_t ) / 2)

  plants_mut <- mutate(plants, space = ifelse((space < 1760), "LT1760", "OV1760"), #1760 is mean space
                      space = factor(space))

# Random Forest Ensemble Model for Prob. of Survival
  r_fit <- ranger(Surv(time) ~ space + min_grow_t + max_grow_t + climate,
                 data = plants_mut,
                 mtry = 2,
                 importance = "permutation",
                 splitrule = "extratrees",
                 verbose = TRUE)

  death_times <- r_fit$unique.death.times 
  surv_prob <- data.frame(r_fit$survival)
  avg_prob <- sapply(surv_prob,mean)

  if (plot == TRUE){
    
    plot(r_fit$unique.death.times,r_fit$survival[1,], 
         type = "l", 
         ylim = c(0,1),
         col = "red",
         xlab = "Days",
         ylab = "survival",
         main = "Patient Survival Curves")

    cols <- colors()
    for (n in sample(c(2:dim(plants_mut)[1]), 20)){
      
      lines(r_fit$unique.death.times, r_fit$survival[n,], type = "l", col = cols[n])
    }

    lines(death_times, avg_prob, lwd = 2)
    legend(500, 0.7, legend = c('Average = black'))

    vi <- data.frame(sort(round(r_fit$variable.importance, 4), decreasing = TRUE))
    names(vi) <- "importance"
    head(vi)

  }
  
# Area under ROC
#  pe <- cat("Prediction Error = 1 - Harrell's c-index = ", r_fit$prediction.error)

#Filtering
  
  if (grepl( ".", date_to_plant, fixed = TRUE) == TRUE | grepl( ".", date_to_harvest, fixed = TRUE) == TRUE) {
    
    wtp <- as.Date(date_to_plant, '%d.%m.%Y')
    wth <- as.Date(date_to_harvest, '%d.%m.%Y')

  }else if (grepl( "/", date_to_plant, fixed = TRUE) == TRUE | grepl( "/", date_to_harvest, fixed = TRUE) == TRUE) {

    wtp <- as.Date(date_to_plant, '%d/%m/%Y')
    wth <- as.Date(date_to_harvest, '%d/%m/%Y')
    
  }else{

    wtp <- as.Date(date_to_plant, '%d-%m-%Y')
    wth <- as.Date(date_to_harvest, '%d-%m-%Y')
    
  }
  
   gt = as.integer(wth - wtp)

  dt <- c()
  for (i in 1:length(death_times)){

    dt[i] <- abs(death_times[i] - gt)

  }

  min_dt <- min(dt)
  for (i in 1:length(death_times)){

    if (dt[i] == min(dt)){

      item = i

    }
  }

  wtp = as.integer(format(wtp, "%m"))
  wth = as.integer(format(wth, "%m"))    

#final filtering
  f <- surv_prob[,item]
  
  if (length(f) > 1700){

    
    ls <- c()
    for ( i in 1:length(f)){

      if (f[i] > 0.8){

        ls <- c(ls, i)

      }
    }
  }else {

    ls <- c()
    for ( i in 1:length(f)){

      if (f[i] > 0.7){

        ls <- c(ls, i)

      }
    }
  }

  nls <- c()
  for ( i in ls){

    if (grepl(wtp, plants[i, 4]) == 1 & grepl(wth, plants[i, 7]) == 1) {

      nls <- c(nls, i)

    }
  }

  prd <- plants[nls,]
  prd$surv_p <- round(surv_prob[nls, item], 2)*100
  prd <- prd[which(prd$min_grow_t <= gt + 15 & prd$max_grow_t >= gt - 15), ]
  prd <- prd[which(prd$space <= size + 50 ),] 
  prd <- prd[which(substr(prd$climate, 1, 2) == substr(climate, 1, 2)),]
  
  if ( nrow(prd) == 0){

    print("Sorry, no recommendations for you. Please try other dates.")

  }  

  else{

    if ( nrow(prd) >= 10){

      prd <- prd[which(prd$surv_p > 99),]
    }

    prd <- prd[order(-prd$surv_p), ]

    print(head(prd))
    for (i in 1:nrow(prd)){
      cat(
        prd[i, 1],
        "with ",
        as.character(prd[i,'surv_p']),
        "% chance of success!",
        "\n",
        "Visit ", prd[i, 2], "for more information", 
        "\n\n"
      ) 
    }
  }
  
}


what_to_plant('20211214-plants-scraped.csv', climate('climate.tif', 41.40431, 2.16637), '01.05.2021', '01.09.2021', 1000, plot = FALSE )
