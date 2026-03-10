#!/usr/bin/env Rscript

suppressPackageStartupMessages(library("optparse"))
suppressPackageStartupMessages(library("readr"))
suppressPackageStartupMessages(library("dplyr"))
suppressPackageStartupMessages(library("magrittr"))

if (!interactive()) {
    options(warn = -1, error = quote({ traceback(); q('no', status = 1) }))
}

args_list <- list(make_option("--option", default = NA, type = 'character', help = "type of analysis"),
				  make_option("--sv_callers", default = NA, type = 'character', help = "SV callers"),
				  make_option("--sample_name", default = NA, type = 'character', help = "sample name"),
				  make_option("--output", default = NA, type = 'character', help = "file name output"))
parser <- OptionParser(usage = "%prog", option_list = args_list)
arguments <- parse_args(parser, positional_arguments = T)
opt <- arguments$options

if (as.numeric(opt$option) == 1) {
	sample_names = unlist(strsplit(x = as.character(opt$sample_name), split = " ", fixed = TRUE))
	data = list()
	for (i in 1:length(sample_names)) {
		data[[i]] = readr::read_tsv(file = paste0("annotate_sv/", sample_names[i], "/", sample_names[i], ".txt"),
								    col_names = TRUE,
								    col_types = cols(.default = col_character())) %>%
				    readr::type_convert() %>%
				    dplyr::mutate(Samples_ID = sample_names[i])
		
		sv_callers = unlist(strsplit(x = as.character(opt$sv_callers), split = " ", fixed = TRUE))
		colnames(data[[i]])[15] = "Manta"
		if (length(sv_callers)==2) {
			if ("svaba" %in% sv_callers) {
				colnames(data[[i]])[16] = "SvABA"
			}
			if ("gridss" %in% sv_callers) {
				colnames(data[[i]])[16] = "GRIDSS"
			}
		} else {
			colnames(data[[i]])[16] = "SvABA"
			colnames(data[[i]])[17] = "GRIDSS"
		}
	}
	data = do.call(rbind, data) %>%
	       dplyr::mutate(SV_type = case_when(
			       grepl("DUP", Manta) ~ "DUP",
			       grepl("DEL", Manta) ~ "DEL",
			       TRUE ~ SV_type
	       ))
	
	readr::write_tsv(x = data, path = as.character(opt$output), append = FALSE, col_names = TRUE)

} else if (as.numeric(opt$option) == 2) {
	sample_names = unlist(strsplit(x = as.character(opt$sample_name), split = " ", fixed = TRUE))
	data = list()
	for (i in 1:length(sample_names)) {
		data[[i]] = readr::read_tsv(file = paste0("delly/", sample_names[i], "/", sample_names[i], ".txt"),
								    col_names = TRUE, col_types = cols(.default = col_character()))
		if (nrow(data[[i]]) != 0) {
			colnames(data[[i]])[15] = "Tumor_Sample"
			colnames(data[[i]])[16] = "Matched_Normal_Sample"
		}
	}
	data = dplyr::bind_rows(data) %>%
	       readr::type_convert()
	
	readr::write_tsv(x = data, path = as.character(opt$output), append = FALSE, col_names = TRUE)
	
}