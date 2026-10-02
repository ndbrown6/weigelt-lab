#!/usr/bin/env Rscript

suppressPackageStartupMessages(library("optparse"))
suppressPackageStartupMessages(library("dplyr"))
suppressPackageStartupMessages(library("readr"))
suppressPackageStartupMessages(library("magrittr"))
suppressPackageStartupMessages(library("QDNAseq"))
suppressPackageStartupMessages(library("QDNAseq.hg19"))

if (!interactive()) {
    options(warn = -1, error = quote({ traceback(); q('no', status = 1) }))
}

args_list <- list(make_option("--option", default = NA, type = 'numeric', help = "option"),
				  make_option("--sample_name", default = NA, type = 'character', help = "sample name"),
				  make_option("--bin_size", default = 100, type = 'numeric', help = "bin size"))
parser <- OptionParser(usage = "%prog", option_list = args_list)
arguments <- parse_args(parser, positional_arguments = T)
opt <- arguments$options

if (as.numeric(opt$option) == 1) {
	bins = QDNAseq::getBinAnnotations(binSize = as.numeric(opt$bin_size))
	read_counts = QDNAseq::binReadCounts(bins,
										 bamfiles = paste0("bam/", as.character(opt$sample_name), ".bam"),
										 isPaired = TRUE,
										 isProperPair = TRUE,
										 hasUnmappedMate = FALSE,
										 isSecondaryAlignment = FALSE,
										 isNotPassingQualityControls = FALSE,
										 isDuplicate = FALSE,
										 minMapq = 30,
										 pairedEnds = TRUE,
										 verbose = FALSE)
	read_counts_ft = QDNAseq::applyFilters(object = read_counts,
										   residual = TRUE,
										   blacklist = TRUE,
										   chromosomes = c("Y", "MT"),
										   verbose = FALSE)
	read_counts_ft = QDNAseq:estimateCorrection(read_counts_ft,
												family = "symmetric",
												maxIter = 2,
												cutoff = 3)
	copy_number = QDNAseq::correctBins(read_counts_ft)
	copy_number_nm = QDNAseq::normalizeBins(copy_number)
	copy_number_sm = QDNAseq::smoothOutlierBins(copy_number_nm)
	exportBins(copy_number_sm,
			   file = paste0("qdnaseq/", as.character(opt$sample_name), ".txt"),
			   fotmat = "tsv")
	
} else if (as.numeric(opt$option) == 2) {
	sample_names = unlist(strsplit(x = as.character(opt$sample_name), split = " ", fixed = TRUE))
	df = list()
	for (i in 1:length(sample_names)) {
		df[[i]] = readr::read_tsv(file = paste0("qdnaseq/", sample_names[i], ".txt"), col_names = TRUE, col_types = cols(.default = col_character())) %>%
				  readr::type_convert() %>%
				  dplyr::mutate(sample_name = sample_names[i])
		colnames(df[[i]])[1] = "feature"
		colnames(df[[i]])[5] = "log2"
	}
	do.call(rbind, df) %>%
	dplyr::select(-feature) %>%
	readr::write_tsv(file = "summary/aggregated-log2.txt", append = FALSE, col_names = TRUE)
}
