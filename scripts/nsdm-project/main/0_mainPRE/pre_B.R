#############################################################################
## 0_mainPRE
## B: pseudo-absences; modelling object generation
## Date: 25-09-2021
## Author: Antoine Adde 
#############################################################################
### =========================================================================
### A- Preparation
### =========================================================================
project<-gsub("/main/0_mainPRE","",gsub(".*scripts/","",getwd()))

# Load N-SDM settings
load(paste0(gsub("scripts","outputs",gsub("/main/0_mainPRE","",getwd())),"/settings/nsdm-settings.RData"))

# Set permissions for new files
Sys.umask(mode="000")

# Set your working directory
setwd(w_path)

# Set lib path
.libPaths(lib_path)

# Load required packages
invisible(lapply(c(packs_data, packs_modl), require, character.only = TRUE))

# Source custom functions
invisible(sapply(list.files(f_path, pattern = ".R", full.names = TRUE, recursive=TRUE), source))

### =========================================================================
### B- Definitions
### =========================================================================
# Number of cores to be used during parallel operations
ncores<-as.numeric(Sys.getenv('SLURM_CPUS_PER_TASK'))

# Retrieve reference rasters
rsts_ref<-readRDS(paste0(w_path,"outputs/",project,"/settings/ref-rasters.rds"))

### =========================================================================
### C- species data
### =========================================================================
# Load species data
sp_dat<-readRDS(paste0(w_path,"outputs/",project,"/settings/species-occurences.rds"))
species<-readRDS(paste0(w_path,"outputs/",project,"/settings/tmp/species-list-run.rds"))

# Loop over species
for(ispi_name in species){

cat(paste0('Ready for GLO and LOC modelling dataset preparation for ', ispi_name, '...\n'))

# Subset spe_loc and spe_glo data
sp_dat_loc<-sp_dat$spe_loc_dis[sp_dat$spe_loc_dis$species==ispi_name,]
sp_dat_glo<-sp_dat$spe_glo_dis[sp_dat$spe_glo_dis$species==ispi_name,]

### =========================================================================
### D- Sample background absences
### =========================================================================
# D.1 GLO
pseu.abs_i_glo<-nsdm.pseuabs(n=n_back,
							 rst_ref=rsts_ref$rst_glo,
							 type=pa_po_glo,
                             pres=sp_dat_glo,
                             taxon=ispi_name)

cat(paste0('GLO dataset prepared (n_occ=',length(which(pseu.abs_i_glo@pa==1)),')...\n'))
                            
# D.2 LOC
pseu.abs_i_loc<-nsdm.pseuabs(n=n_back,
							 rst_ref=rsts_ref$rst_loc,
							 type=pa_po_loc,
                             pres=sp_dat_loc,
                             taxon=ispi_name)
						   
cat(paste0('LOC dataset prepared (n_occ=',length(which(pseu.abs_i_loc@pa==1)),')...\n'))

if(length(which(pseu.abs_i_loc@pa==1))==0 | length(which(pseu.abs_i_glo@pa==1))==0) next

# D.3 Save spatial points as shapefiles
dir<-paste0(scr_path,"/outputs/",project,"/d0_datasets/shp/",ispi_name)
dir.create(dir, recursive=T)							   
suppressWarnings(glo_pts<-spTransform(SpatialPointsDataFrame(coords=pseu.abs_i_glo@xy[which(pseu.abs_i_glo@pa==1),],
                               data=data.frame(pa=rep(1,length(which(pseu.abs_i_glo@pa==1)))),
                               proj4string=crs(rsts_ref$rst_glo)), crs(rsts_ref$rst_loc)))

suppressWarnings(loc_pts<-SpatialPointsDataFrame(coords=pseu.abs_i_loc@xy[which(pseu.abs_i_loc@pa==1),],
                              data=data.frame(pa=rep(1,length(which(pseu.abs_i_loc@pa==1)))),
                               proj4string=crs(rsts_ref$rst_loc)))

writeOGR(glo_pts, dir, paste0(ispi_name, "_glo"), driver = "ESRI Shapefile", overwrite=T)
writeOGR(loc_pts, dir, paste0(ispi_name, "_loc"), driver = "ESRI Shapefile", overwrite=T)

### =========================================================================
### E- Save
### =========================================================================
nsdm.savethis(object=list(group=unique(sp_dat_loc$class),
                          pseu.abs_i_glo=pseu.abs_i_glo,
                          pseu.abs_i_loc=pseu.abs_i_loc),
                          species_name=ispi_name,
                          save_path=paste0(scr_path,"/outputs/",project,"/d0_datasets/base"))
}

print("Finished!")