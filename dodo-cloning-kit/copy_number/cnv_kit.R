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
		  make_option("--file_out", default = NA, type = 'character', help = "file name output"))
parser <- OptionParser(usage = "%prog", option_list = args_list)
arguments <- parse_args(parser, positional_arguments = T)
opt <- arguments$options

if (as.numeric(opt$option) == 1) {
	file_names = unlist(strsplit(x = as.character(opt$file_in), split = " ", fixed = TRUE, perl = FALSE))
	data = list()
	for (i in 1:length(file_names)) {
		data[[i]] = readr::read_tsv(file = file_names[i], col_names = TRUE, col_types = cols(.default = col_character())) %>%
			    readr::type_convert() %>%
			    dplyr::select(Chromosome = chromosome,
					  Start_Position = start,
					  End_Position = end,
					  Hugo_GeneSymbol = gene,
					  Log2_Ratio = log2) %>%
			    dplyr::filter(Chromosome %in% c(1:22, "X")) %>%
			    dplyr::mutate(Sample_Name = gsub(pattern = ".txt", replacement = "", x = gsub(pattern = "cnv_kit/log2/", replacement = "", x = file_names[i], fixed = TRUE), fixed = TRUE))
	}
	data = do.call(rbind, data) %>%
	       reshape2::dcast(Chromosome + Start_Position + End_Position + Hugo_GeneSymbol ~ Sample_Name, value.var = "Log2_Ratio")
	readr::write_tsv(x = data, file = as.character(opt$file_out), append = FALSE, col_names = TRUE)
}