#!/usr/bin/env Rscript

suppressPackageStartupMessages(library("optparse"))
suppressPackageStartupMessages(library("dplyr"))
suppressPackageStartupMessages(library("readr"))
suppressPackageStartupMessages(library("magrittr"))
suppressPackageStartupMessages(library("reshape2"))
suppressPackageStartupMessages(library("copynumber"))

if (!interactive()) {
    options(warn = -1, error = quote({ traceback(); q('no', status = 1) }))
}

args_list <- list(make_option("--option", default = NA, type = 'character', help = "type of analysis"),
		  make_option("--file_in", default = NA, type = 'character', help = "file name input"),
		  make_option("--file_out", default = NA, type = 'character', help = "file name output"),
		  make_option("--tumor_sample", default = NA, type = 'character', help = "tumor sample name"),
		  make_option("--normal_sample", default = NA, type = 'character', help = "normal sample name"))
parser <- OptionParser(usage = "%prog", option_list = args_list)
arguments <- parse_args(parser, positional_arguments = T)
opt <- arguments$options

if (as.numeric(opt$option) == 1) {
	sample_names = unlist(strsplit(x = as.character(opt$tumor_sample), split = " ", fixed = TRUE))
	data = list()
	for (i in 1:length(sample_names)) {
		data[[i]] = readr::read_tsv(file = paste0("cnv_kit/normalized_log2/", sample_names[i], ".txt"), col_names = TRUE, col_types = cols(.default = col_character())) %>%
			    readr::type_convert() %>%
			    dplyr::mutate(Position = round(.5*(Start_Position + End_Position))) %>%
			    dplyr::select(Chromosome = chromosome,
					  Position,
					  Hugo_GeneSymbol = gene,
					  Log2_Ratio = log2) %>%
			    dplyr::filter(Chromosome %in% c(1:22, "X")) %>%
			    dplyr::mutate(Sample_Name = sample_names[i]) %>%
	}
	data = do.call(rbind, data) %>%
	       reshape2::dcast(Chromosome + Position + Hugo_GeneSymbol ~ Sample_Name, value.var = "Log2_Ratio")
	readr::write_tsv(x = data, file = as.character(opt$file_out), append = FALSE, col_names = TRUE)
	
} else if (as.numeric(opt$option) == 2) {
	sample_names = unlist(strsplit(x = as.character(opt$tumor_sample), split = " ", fixed = TRUE))
	data = readr::read_tsv(file = as.character(opt$file_in), col_names = TRUE, col_types = cols(.default = col_character())) %>%
	       dplyr::mutate(Chromosome = ifelse(Chromosome == "X", "23", Chromosome)) %>%
	       readr::type_convert()
	if (length(sample_names) == 1) {
		smoothed_log2 = data %>%
				copynumber::winsorize(method = "mad", , tau = 2.5, k = 25, verbose = FALSE) %>%
				dplyr::rename(Chromosome = chrom, Position = pos)
		segmented_log2 = smoothed_log2 %>%
				 copynumber::pcf(gamma = 150, normalize = FALSE, fast = TRUE, verbose = FALSE) %>%
				 dplyr::select(-arm, -n.probes) %>%
				 dplyr::rename(Chromosome = chrom, Start_Position = start.pos, End_Position = end.pos) %>%
				 dplyr::mutate(Chromosome = factor(Chromosome, levels = 1:23, ordered = TRUE)) %>%
				 dplyr::rename(sample_name = sampleID, Log2_Ratio = mean)
		readr::write_tsv(x = segmented_log2, file = as.character(opt$file_out), append = FALSE, col_names = TRUE)
	} else {
		smoothed_log2 = data %>%
				copynumber::winsorize(method = "mad", , tau = 2.5, k = 25, verbose = FALSE) %>%
				dplyr::rename(Chromosome = chrom, Position = pos)	
		segmented_log2 = smoothed_log2 %>%
				 copynumber::multipcf(gamma = 150, normalize = FALSE, fast = TRUE, verbose = FALSE) %>%
				 dplyr::select(-arm, -n.probes) %>%
				 dplyr::rename(Chromosome = chrom, Start_Position = start.pos, End_Position = end.pos) %>%
				 dplyr::mutate(Chromosome = factor(Chromosome, levels = 1:23, ordered = TRUE)) %>%
				 reshape2::melt(id.vars = c("Chromosome", "Start_Position", "End_Position"), variable.name = "sample_name", value.name = "Log2_Ratio") %>%
		readr::write_tsv(x = segmented_log2, file = as.character(opt$file_out), append = FALSE, col_names = TRUE)
	}
}
