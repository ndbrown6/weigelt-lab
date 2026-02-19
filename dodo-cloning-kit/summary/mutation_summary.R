#!/usr/bin/env Rscript

suppressPackageStartupMessages(library("optparse"))
suppressPackageStartupMessages(library("readr"))
suppressPackageStartupMessages(library("dplyr"))
suppressPackageStartupMessages(library("magrittr"))

if (!interactive()) {
    options(warn = -1, error = quote({ traceback(); q('no', status = 1) }))
}

optList = list(make_option(c("--mutect_maf"), type="character", default=NULL, help="MuTect MAF file"),
	       make_option(c("--strelka_maf"), type="character", default=NULL, help="Strelka MAF file"),
	       make_option(c("--varscan_maf"), type="character", default=NULL, help="VarScan MAF file"),
	       make_option(c("--scalpel_maf"), type="character", default=NULL, help="Scalpel MAF file"),
	       make_option(c("--platypus_maf"), type="character", default=NULL, help="Platypus MAF file"),
	       make_option(c("--output"), type="character", help="Output combined MAF file"))
parser = OptionParser(usage = "%prog", option_list = optList)
arguments = parse_args(parser, positional_arguments = T)
opt = arguments$options

maf_list = list()
caller_names = c()

if (!is.null(opt$mutect_maf)) {
	maf_list[["mutect"]] = readr::read_tsv(file = opt$mutect_maf, comment = "#", col_names = TRUE, col_types = cols(.default = col_character()))
	caller_names = c(caller_names, "mutect")
}
if (!is.null(opt$strelka_maf)) {
	maf_list[["strelka"]] = readr::read_tsv(file = opt$strelka_maf, comment = "#", col_names = TRUE, col_types = cols(.default = col_character()))
	caller_names = c(caller_names, "strelka")
}
if (!is.null(opt$varscan_maf)) {
	maf_list[["varscan"]] = readr::read_tsv(file = opt$varscan_maf, comment = "#", col_names = TRUE, col_types = cols(.default = col_character()))
	caller_names = c(caller_names, "varscan")
}
if (!is.null(opt$scalpel_maf)) {
	maf_list[["scalpel"]] = readr::read_tsv(file = opt$scalpel_maf, comment = "#", col_names = TRUE, col_types = cols(.default = col_character()))
	caller_names = c(caller_names, "scalpel")
}
if (!is.null(opt$platypus_maf)) {
	maf_list[["platypus"]] = readr::read_tsv(file = opt$platypus_maf, comment = "#", col_names = TRUE, col_types = cols(.default = col_character()))
	caller_names = c(caller_names, "platypus")
}

if (length(maf_list) == 0) {
	stop("ERROR: No MAF files provided")
}

if (is.null(opt$mutect_maf)) {
	stop("ERROR: Mutect MAF file is required. Mutect is indispensable for this analysis")
}

if (!file.exists(opt$mutect_maf)) {
	stop("ERROR: Mutect MAF file not found: ", opt$mutect_maf)
}

# Start with the first MAF
combined_maf <- maf_list[[1]]

# Iteratively join remaining MAFs
if (length(maf_list) > 1) {
    for (i in 2:length(maf_list)) {
        combined_maf <- full_join(combined_maf, maf_list[[i]],
                                 by = c("Tumor_Sample_Barcode", 
                                       "Matched_Norm_Sample_Barcode",
                                       "Chromosome", 
                                       "UPS_coordinate"),
                                 suffix = c("", paste0("_", caller_names[i])))
    }
}

# Consolidate duplicate columns
pattern <- paste0("_(", paste(caller_names, collapse="|"), ")$")
cols_with_suffix <- grep(pattern, names(combined_maf), value = TRUE)
base_cols <- unique(sub(pattern, "", cols_with_suffix))

for (col in base_cols) {
    matching_cols <- grep(paste0("^", col, "(_|$)"), names(combined_maf), value = TRUE)
    if (length(matching_cols) > 1) {
        combined_maf[[col]] <- do.call(coalesce, combined_maf[matching_cols])
        combined_maf <- combined_maf %>% select(-all_of(matching_cols[matching_cols != col]))
    }
}

# Remove exact duplicates
combined_maf <- combined_maf %>% distinct()

# Write output
write.table(combined_maf, opt$output, sep="\t", quote=FALSE, row.names=FALSE)