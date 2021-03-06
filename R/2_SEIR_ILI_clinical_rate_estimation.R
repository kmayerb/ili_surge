rm(list=ls())
gc()
library(data.table)
library(magrittr)
library(ggplot2)
library(viridis)
library(ggpubr)
library(zoo)
source('R/SEIR_functions.R')

####### NOTE: In this script, we compare ILI to SEIR curves matchign the growth rate of deaths.

####### For march 1, we use the SEIR curve estimate of ILI NOT the empirical ILI
####### The reason: March 1's ILI shows low correlation w/ COVID
####### thus ILI including & prior to first week of march are thrown out

# Deaths ------------------------------------------------------------------

X <- read.csv('data/covid-19-data/covid-19-data/us-states.csv',stringsAsFactors = F) %>% as.data.table

X[,deaths:=c(deaths[1],diff(deaths)),by=state]


### for each state, we'll analyze growth rate in deaths starting on the first date with non-zero deaths.
X[,date:=as.Date(date)]
setkey(X,state,date)
X[,cumulative_deaths:=cumsum(deaths),by=state]
Y <- X[date>as.Date('2020-03-04') & date<as.Date("2020-04-02"),list(deaths=sum(deaths)),by=date]

fit_national <- glm(deaths~date,family=poisson,data=Y)
gr_national <- coef(fit_national)[2]
se_national <- sqrt(vcov(fit_national)[4])

## one-tailed test of gr_national > log(2)/3.5 day doubling time
1-pnorm(3.5,gr_national,se_national)

# US growth rates -------------------------------------------------------------

US <- readRDS('results/US_seir_forecasts_USgr.Rd')
US[,replicate:=factor(replicate)]
setkey(US,replicate,date)
ILI <- read.csv('results/US_total_weekly_excess_ili_no_mizumoto.csv',stringsAsFactors = F) %>% 
  as.data.table
ILI[,date:=as.Date(date)]

ILI[,surge:=date>=as.Date('2020-03-07')]


ili <- ILI[surge==TRUE,c('date','mean')]
ili <- rbind(US[date==as.Date('2020-03-01'),
                list(date=unique(date),
                     mean=weighted.mean(weekly_I,w=likelihood))],ili)
ili <- rbind(ili,ili)
ili[1:(.N/2),scaled:=FALSE]
ili[is.na(scaled),scaled:=TRUE]

scaling_factors <- read.csv('results/scaling_admission_rates.csv') %>% as.data.table
scaling_factors[,date:=as.Date(date)]
setkey(scaling_factors,date)
setkey(ili,date,scaled)
ili <- scaling_factors[ili]
ili[is.na(scaling_factor),scaling_factor:=1]

ili[scaled==TRUE,mean:=mean*scaling_factor]

ili[,replicate:=15000]
Y[,replicate:=15001]
cols=magma(5)

r <- as.numeric(gr_national)
seir <- US_SEIRD(r,cfr=0.005)

setkey(seir,date)
setkey(Y,date)
yy <- seir[,c('date','new_deaths')][Y]
b=glm(deaths~new_deaths+0,data=yy)$coefficients


cfr <- as.numeric(0.005/b)
seir <- US_SEIRD(r,cfr=cfr)
seir[,weekly_I:=rollapply(I,FUN=sum,w=7,align='left',fill=NA)]
ili <- ili[date>as.Date('2020-03-01')]
# ili[date==as.Date('2020-03-01'),mean:=seir[date==as.Date('2020-03-01')]$weekly_I]  ### 
setkey(seir,date)
setkey(ili,date)

ili$weekly_I <- NULL
ili <- ili[seir[,c('date','weekly_I')]]
ili_sc <- ili[scaled==TRUE]
names(ili_sc)[3] <- 'mean_scaled'
i2 <- cbind(ili[scaled==FALSE,c('date','mean')],ili_sc[,c('mean_scaled','weekly_I')])


seir[,replicate:=15002]
i2[,replicate:=15003]

ggplot(US[date<as.Date('2020-04-07')],
       aes(date,weekly_I/7,by=factor(replicate)))+
  geom_line(alpha=0.04)+
  geom_line(data=seir[date<as.Date('2020-04-07')],aes(date,weekly_I/7),lwd=2,alpha=1,col='red',lty=2)+
  geom_line(data=seir[date<=max(Y$date)],aes(date,new_deaths),alpha=1)+
  geom_ribbon(data=ili[scaled==TRUE],aes(ymin=mean/7,ymax=weekly_I/7),alpha=0.8,fill=cols[4])+
  geom_ribbon(data=i2,aes(ymin=mean/7,ymax=mean_scaled/7),fill=rgb(0,0.1,0.5),alpha=0.8)+
  geom_point(data=Y,aes(date,deaths),alpha=1,pch=4,cex=3)+
  geom_point(data=ili[scaled==FALSE & date>as.Date('2020-03-01')],aes(date,mean/7),alpha=1,pch=19,cex=6,col=cols[2])+
  geom_line(data=ili[scaled==FALSE],aes(date,mean/7),alpha=1,lwd=1.5,col=cols[2])+
  geom_point(data=ili[scaled==TRUE & date>as.Date('2020-03-01')],aes(date,mean/7),alpha=1,pch=18,cex=6,col=cols[3])+
  geom_line(data=ili[scaled==TRUE],aes(date,mean/7),alpha=1,lwd=1.5,col=cols[3])+
  scale_y_continuous(trans='log',name='Number of People',breaks=10^(0:9),limits=c(1,3e8))+
  ggtitle('SEIR vs. ILI')+
  theme_bw(base_size = 25)+
  theme(legend.position = 'none')

ggsave('figures/death_rate_excess_ili_SEIR_matching_all.png',height=8,width=8,units='in')

# Scenario 2: Italy deaths ---------------------------------------------------
US <- readRDS('results/US_seir_forecasts_ITgr.Rd')
Y <- read.csv('data/Italy/dpc-covid19-ita-andamento-nazionale.csv',stringsAsFactors = F) %>%
  as.data.table
colnames(Y)[c(1,11)] <- c('date','deaths')
Y[,date:=as.Date(date)]
Y[,deaths:=c(deaths[1],diff(deaths))]
ggplot(Y,aes(date,deaths))+
  geom_point()+
  scale_y_continuous(trans='log')
## will use up to March 12 data
Y <- Y[date<=as.Date('2020-03-12')]

fit_italia <- glm(deaths~date,family=poisson,data=Y[date<=as.Date('2020-03-12')])
r <- as.numeric(fit_italia$coefficients[2])


seir <- US_SEIRD(r,cfr=0.005)

setkey(seir,date)
setkey(Y,date)
yy <- seir[,c('date','new_deaths')][Y]
b=glm(deaths~new_deaths+0,data=yy)$coefficients


cfr <- as.numeric(0.005*b)
seir <- US_SEIRD(r,cfr=cfr)
seir[,weekly_I:=rollapply(I,FUN=sum,w=7,align='left',fill=NA)]


ili[date==as.Date('2020-03-01'),mean:=seir[date==as.Date('2020-03-01')]$weekly_I]  ### 
setkey(seir,date)
setkey(ili,date)
ili$weekly_I <- NULL
ili <- ili[seir[,c('date','weekly_I')]]
ili_sc <- ili[scaled==TRUE]
names(ili_sc)[3] <- 'mean_scaled'
i2 <- cbind(ili[scaled==FALSE,c('date','mean')],ili_sc[,c('mean_scaled','weekly_I')])


seir[,replicate:=15002]
i2[,replicate:=15003]
Y[,replicate:=15000]



ggplot(US[date<as.Date('2020-04-07')],
       aes(date,weekly_I/7,by=factor(replicate)))+
  geom_line(alpha=0.04)+
  geom_line(data=seir[date<as.Date('2020-04-07')],aes(date,weekly_I/7),lty=2,lwd=2,alpha=1,col='red')+
  geom_line(data=seir[date<=max(Y$date)],aes(date,new_deaths),alpha=1)+
  geom_point(data=Y,aes(date,deaths),alpha=1,pch=4,cex=3)+
  geom_ribbon(data=ili[date>as.Date('2020-03-01') & scaled==TRUE],aes(ymin=mean/7,ymax=weekly_I/7),alpha=0.8,fill=cols[4])+
  geom_ribbon(data=i2[date>as.Date('2020-03-01')],aes(ymin=mean/7,ymax=mean_scaled/7),fill=rgb(0,0.1,0.5),alpha=0.8)+
  geom_point(data=ili[date>as.Date('2020-03-01') & scaled==FALSE & date>as.Date('2020-03-01')],aes(date,mean/7),alpha=1,pch=18,cex=6,col=cols[2])+
  geom_line(data=ili[date>as.Date('2020-03-01') & scaled==FALSE],aes(date,mean/7),alpha=1,lwd=1.5,col=cols[2])+
  geom_point(data=ili[date>as.Date('2020-03-01') & scaled==TRUE & date>as.Date('2020-03-01')],aes(date,mean/7),alpha=1,pch=18,cex=6,col=cols[3])+
  geom_line(data=ili[date>as.Date('2020-03-01') & scaled==TRUE],aes(date,mean/7),alpha=1,lwd=1.5,col=cols[3])+
  scale_y_continuous(trans='log',name='Number of People',breaks=10^(0:9),limits=c(1,3e8))+
  ggtitle('SEIR vs. ILI, Italian growth rate')+
  scale_alpha_continuous(range=c(0.01,0.2))+
  theme_bw(base_size = 25)+
  theme(legend.position = 'none')

ggsave('figures/death_rate_excess_ili_SEIR_matching_all_italy.png',height=8,width=8,units='in')



# Clinical rate vs. growth rate -------------------------------------------
clinical_rate_calculator <- function(week='2020-03-08',method='gam',
                                     start_date='2020-01-15',time_onset_to_doc=0){
  ILI <- read.csv('results/US_total_weekly_excess_ili_no_mizumoto.csv',stringsAsFactors = F) %>% as.data.table
  ILI[,week:=as.Date(date)]
  
  if (week=='latest'){
    wk<- max(ILI$week,na.rm=T)
  } else {
    wk <- as.Date(week)
  }
  
  if (class(start_date)!='Date'){
    start_date <- as.Date(start_date)
  }
  Excess_ILI <- mean(ILI[week==wk]$mean)
  
  US_seir_forecasts <- readRDS('results/US_seir_forecasts_unifgr.Rd')
  setkey(US_seir_forecasts,replicate,date)
  date_shift = as.numeric(min(US_seir_forecasts$date)-start_date)
  US_seir_forecasts[,date:=shift(date,type='lead',n=date_shift),by=replicate]
  
  X = US_seir_forecasts[date==wk-time_onset_to_doc,
                        list(clinical_rate=Excess_ILI/weekly_I),by=GrowthRate]
  
  if (method=='loess'){
    fit <- loess(log(clinical_rate)~log(GrowthRate),data=X)
    X[,predicted_clinical_rate:=exp(fit$fitted)]
  } else {
    fit <- mgcv::gam(log(clinical_rate)~s(log(GrowthRate)),data=X)
    X[,predicted_clinical_rate:=exp(fit$fitted.values)]
  }
  X[,possible:=clinical_rate<1]
  X[,DoublingTime:=log(2)/GrowthRate]
  setkey(X,GrowthRate)
  return(list('Data'=X,'fit'=fit))
}

CR <- clinical_rate_calculator(time_onset_to_doc=4)
ggplot(CR$Data,aes(DoublingTime,clinical_rate,alpha=factor(possible)))+
  geom_point()+
  scale_alpha_manual(values=c(0.1,0.4))+
  scale_y_continuous(trans='log',breaks=10^(-5:5))+
  scale_x_continuous(trans='log',breaks=1:7)+
  geom_line(aes(DoublingTime,predicted_clinical_rate),lwd=2,alpha=1,col=rgb(0,.2,0.8))+
  theme(legend.position = 'none')+
  ggtitle('Estimated clinical rate, 4 day lag')
ggsave('figures/Clinical_rate_v_Doubling_time_4d_lag.png',height=8,width=8,units='in')

lag_times <- c(0,4,8)
for (lag in lag_times){
  dum <- clinical_rate_calculator(time_onset_to_doc=lag)
  if (lag==0){
    CR <- dum$Data
    CR[,delay_to_doc:=lag]
  } else {
    dum$Data[,delay_to_doc:=lag]
    CR <- rbind(CR,dum$Data)
  }
}

label_figs <- function(strings)  paste(strings,'days')
ggplot(CR[DoublingTime<4],aes(DoublingTime,clinical_rate,alpha=factor(possible),by=delay_to_doc))+
  geom_point(cex=2)+
  scale_alpha_manual(values=c(0.01,0.15))+
  scale_y_continuous(name='Clinical Rate',trans='log',breaks=10^(-5:3),limits=c(6e-3,1e3),position='right')+
  scale_x_continuous(name='Doubling Time',trans='log',breaks=1:7)+
  geom_line(aes(DoublingTime,predicted_clinical_rate),lwd=2,alpha=1,col=rgb(0,.2,0.8))+
  theme_bw(base_size=25)+
  theme(legend.position = 'none')+
  geom_vline(xintercept = 3.5,lty=1,lwd=2,col='black',alpha=1)+
  facet_wrap(.~delay_to_doc,labeller=labeller(delay_to_doc=label_figs),nrow=length(lag_times))
ggsave('figures/Clinical_rate_v_Doubling_time_by_delay.png',height=14,width=6,units='in',bg='transparent')



r_us <- 0.2299108 
r_italy <- 0.2614756
CR <- clinical_rate_calculator(time_onset_to_doc = 1)  ## assume 1-day lag from onset of infectiousness to doc visit
CR$fit %>% predict(newdata=data.frame('GrowthRate'=r_us)) %>% exp
CR$fit %>% predict(newdata=data.frame('GrowthRate'=r_italy)) %>% exp

CR <- clinical_rate_calculator(time_onset_to_doc = 4)  ## assume 1-day lag from onset of infectiousness to doc visit
CR$fit %>% predict(newdata=data.frame('GrowthRate'=r_us)) %>% exp
CR$fit %>% predict(newdata=data.frame('GrowthRate'=r_italy)) %>% exp



# What % of r_us sims have cr<1 for 4 day lag -----------------------------


US <- readRDS('results/US_seir_forecasts_USgr.Rd')
ILI <- read.csv('results/US_total_weekly_excess_ili_no_mizumoto.csv',stringsAsFactors = F) %>% as.data.table
ILI[,week:=as.Date(date)]
Excess_ILI <- ILI[date==as.Date('2020-03-08'),mean]

X = US[date==as.Date('2020-03-04'),
       list(clinical_rate=Excess_ILI/weekly_I),by=GrowthRate]
X[,sum(clinical_rate<1)]/2e3
