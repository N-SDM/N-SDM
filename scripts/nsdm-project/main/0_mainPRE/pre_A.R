#############################################################################
## 0_mainPRE
## A: read N-SDM settings; load input data; occurrences disaggregation; covariate formatting
## Date: 25-09-2021
## Author: Antoine Adde 
#############################################################################
### =========================================================================
### A- Main N-SDM settings
### =========================================================================
# Project name
project<-gsub("/main","",gsub(".*scripts/","",getwd()))

# Set permissions for new files
Sys.umask(mode="000")

# Load and retrieve main settings
settings<-read.csv2("./settings/settings.csv")
parameters<-settings$parameter
values<-settings$value
for(i in 1:length(parameters)){
if(grepl(pattern="NULL", values[i])){
do.call("<-",list(parameters[i], NULL))
} else {
if(grepl(pattern=paste0(c("c\\('|paste", ":20"), collapse="|"), values[i])){
do.call("<-",list(parameters[i], eval(parse(text=values[i]))))
} else {
 if(is.na(as.numeric(values[i]))) {
do.call("<-",list(parameters[i], values[i]))
 } else {
do.call("<-",list(parameters[i], as.numeric(values[i])))
}
}
}
}

# Additional settings
ssl_id<-read.table(paste0(w_path,"outputs/",project,"/settings/tmp/ssl_id.txt"), )$V1
cov_path<-paste0(w_path,"data/",project,"/covariates/")
f_path<-paste0(w_path,"scripts/",project,"/functions/")
spe_glo<-list.files(paste0(w_path,"data/",project,"/species/glo"), full.names=T, pattern=".rds")
spe_loc<-list.files(paste0(w_path,"data/",project,"/species/loc"), full.names=T, pattern=".rds")
param_grid<-paste0(w_path,"scripts/",project,"/main/settings/", param_grid)
if(length(expert_table)>0) expert_table<-paste0(w_path,"scripts/",project,"/main/settings/", expert_table)
if(length(forced_species)>0) forced_species<-paste0(w_path,"scripts/",project,"/main/settings/", forced_species)

# Check and refine masks
mask_loc<-paste0(w_path,"data/",project,"/masks/", mask_loc) # mandatory (local area mask)
if(length(mask_pred)>0) mask_pred<-paste0(w_path,"data/",project,"/masks/", mask_pred)

# Save settings
rm(settings, parameters, values, i)
save.image(paste0(w_path,"outputs/",project,"/settings/nsdm-settings.RData"))

print(paste0("N-SDM settings defined"))

### =========================================================================
### B- Prepare covariate data
### =========================================================================
# Set lib path
.libPaths(lib_path)

# Load required packages
invisible(lapply(c(packs_data, packs_modl), require, character.only = TRUE))

# Source custom functions
invisible(sapply(list.files(f_path, pattern = ".R", full.names = TRUE, recursive=TRUE), source))

ncores<-as.numeric(Sys.getenv('SLURM_CPUS_PER_TASK'))

# Generate covariate info table
nsdm.covinfo(cov_path=cov_path, save_path=paste0(w_path,"scripts/",project,"/main/settings/"),
             time_cov=time_cov, focal_cov=focal_cov)
			 
cov_info<-read_excel(paste0(w_path,"scripts/", project, "/main/settings/predictors-available.xlsx"))
			 
# Rewrite glo rasters masked with mask_loc if not already done
lr_glo<-cov_info$file[cov_info$level=="glo"]
if(length(grep("msk", lr_glo)) != length(lr_glo)/2){
msk_loc<-readRDS(mask_loc)
for(m in lr_glo){
r<-readRDS(m)
r_msk<-raster::mask(r, msk_loc, inverse=TRUE)
saveRDS(r_msk, gsub(".rds", "_msk.rds", m, fixed=T))
nsdm.covinfo(cov_path=cov_path, save_path=paste0(w_path,"scripts/",project,"/main/settings/"),
             time_cov=time_cov, focal_cov=focal_cov)			 
cov_info<-read_excel(paste0(w_path,"scripts/", project, "/main/settings/predictors-available.xlsx"))
}
}

# list availabe covariates
lr_loc<-cov_info$file[cov_info$level=="loc"]
lr_glo<-cov_info$file[cov_info$level=="glo" & cov_info$attribute=="msk"]
lr<-c(lr_glo, lr_loc)

# Create fst versions 
threads_fst(nr_of_threads = 1)

# if not already done: check if fst version exists
k<-sapply(lr, function(f){file.exists(gsub(".rds", ".fst", f, fixed=T))})
lr<-lr[!k]

# otherwise do it now
if(length(lr) > 0){
pp<-mclapply(lr, function(c){
r<-readRDS(c)
r_df<-as.data.frame(r)
write.fst(r_df, gsub(".rds", ".fst", c, fixed=T), 75)
names(r)
}, mc.cores=ncores)}

# Create local and global reference rasters
rst_glo<-readRDS(lr_glo[1])
## if bioclim layer available use it; else first one
if(length(grep("2010_bio1", lr_loc, value=T))>0){
rst_loc<-readRDS(grep("2010_bio1", lr_loc, value=T)[1])
}else{
rst_loc<-readRDS(lr_loc[1])}

# Save covariate data settings
## reference rasters
saveRDS(list(rst_loc=rst_loc,
             rst_glo=rst_glo),  
        paste0(w_path,"outputs/",project,"/settings/ref-rasters.rds"))
		
## covariates list and info
saveRDS(list(lr_loc=lr_loc,
             lr_glo=lr_glo,
			 cov_info=cov_info), 
        paste0(w_path,"outputs/",project,"/settings/covariates-list.rds"))

print(paste0("Covariate settings defined"))

### =========================================================================
### C- Refine the list of species to be modelled
### =========================================================================
# Check if .fst versions of local and global species data exist or create them
threads_fst(nr_of_threads = ncores)

if(!file.exists(gsub(".rds", ".fst", spe_loc))){
spe_loc_pts<-readRDS(spe_loc)
if(class(spe_loc_pts)=="SpatialPointsDataFrame"){spe_loc_pts_dat<-spe_loc_pts@data
} else {
spe_loc_pts_dat<-spe_loc_pts}
write_fst(spe_loc_pts_dat, gsub(".rds", ".fst", spe_loc), 0)
}

if(!file.exists(gsub(".rds", ".fst", spe_glo))){
spe_glo_pts<-readRDS(spe_glo)
if(class(spe_loc_pts)=="SpatialPointsDataFrame"){spe_glo_pts_dat<-spe_glo_pts@data
} else {
spe_glo_pts_dat<-spe_glo_pts}
write_fst(spe_glo_pts_dat, gsub(".rds", ".fst", spe_glo), 0)
}

# Load local and global species fst data
spe_loc_fst <-read_fst(gsub(".rds", ".fst", spe_loc))
if("canonicalname" %in% names(spe_loc_fst)) spe_loc_fst$species<-spe_loc_fst$canonicalname
spe_loc_names<-unique(spe_loc_fst$species)
print(paste0("Initial number of species in LOC species dataset is: ",length(spe_loc_names)))

spe_glo_fst<-read_fst(gsub(".rds", ".fst", spe_glo))
if("canonicalname" %in% names(spe_glo_fst)) spe_glo_fst$species<-spe_glo_fst$canonicalname
spe_glo_names<-unique(spe_glo_fst$species)
print(paste0("Initial number of species in GLO species dataset is: ",length(spe_glo_names)))

# Intersect global and local lists of species (matching)
species<-sort(intersect(spe_glo_names, spe_loc_names))

print(paste0("Number of remaining species after intersecting GLO and LOC species dataset is: ",length(species)))

# If a vector of species to be forced is available use it
if(length(forced_species)>0) forced_species<-read.csv2(forced_species, header=FALSE)[,1]
if(is.character(forced_species)){
species<-forced_species
}

# discard species to match n_spe (number of species to be modelled) if needed
if(n_spe<length(species)){
species<-species[1:n_spe]
}

print(paste0("Total number of species considered for this N-SDM run is: ",length(species)))

### =========================================================================
### D- Spatiotemporal disaggregation of species data
### =========================================================================
# Subset local species data
spe_loc_pts<-spe_loc_fst[spe_loc_fst$species %in% species,]

print(paste0("Ready for spatiotemporal disaggregation of local data for ",length(species)," species"))

# Disaggregate local species data
if(tmatch_loc==FALSE) spe_loc_pts$year<-NULL # no temporal matching
if(disag_loc==TRUE){
spe_loc_dis<-nsdm.disaggregate(pres=spe_loc_pts, rst=rst_loc, thindist=thindist, thinyear=10, max_uncertain=max_uncertain, min_occ=min_occ, ncores=ncores)
} else { # if no disaggregation is requested
spe_loc_dis<-spe_loc_pts
}

# Update species list
species<-unique(spe_loc_dis$species)

# Subset global species data
spe_glo_pts<-spe_glo_fst[spe_glo_fst$species %in% species,]

print(paste0("Ready for spatiotemporal disaggregation of global data for ",length(species)," species"))

# disaggregate global species data
if(tmatch_glo==FALSE) spe_glo_pts$year<-NULL # no temporal matching
if(disag_glo==TRUE){
spe_glo_dis<-nsdm.disaggregate(pres=spe_glo_pts, rst=rst_glo, thindist=res(rst_glo)[1], ncores=ncores)
} else { # if no disaggregation is requested
spe_glo_dis<-spe_glo_pts
}

# Save species data settings
## datasets
saveRDS(list(spe_loc_dis=spe_loc_dis,
             spe_glo_dis=spe_glo_dis),  
        paste0(w_path,"outputs/",project,"/settings/species-occurences.rds"))
		
## species list
saveRDS(species,  
        paste0(w_path,"outputs/",project,"/settings/species-list.rds"))
		
## number of cluster runs needed
spe_runs<-length(splitIndices(length(species), length(species)/n_mx_spe))
writeLines(as.character(spe_runs),        paste0(w_path,"outputs/",project,"/settings/tmp/spe_runs.txt"))
writeLines(as.character(length(species)), paste0(w_path,"outputs/",project,"/settings/tmp/n_spe.txt"))

print(paste0("Species data and settings defined"))

print("Finished!")