#!/usr/bin/env Rscript

suppressPackageStartupMessages(library("optparse"))
suppressPackageStartupMessages(library("dplyr"))
suppressPackageStartupMessages(library("readr"))
suppressPackageStartupMessages(library("magrittr"))
suppressPackageStartupMessages(library("reshape2"))

if (!interactive()) {
	options(warn = -1, error = quote({ traceback(); q('no', status = 1) }))
}

args_list <- list(make_option("--option", default = NA, type = 'character', help = "type of analysis"),
		  make_option(c("-fi", "--file_in"), default = ".", type = "character", help = "Input file name [default = %default]", metavar = "character"),
		  make_option(c("-fo", "--file_out"), default = ".", type = "character", help = "Output file name [default = %default]", metavar = "character"))
parser <- OptionParser(usage = "%prog", option_list = args_list)
arguments <- parse_args(parser, positional_arguments = T)
opt <- arguments$options

if (as.numeric(opt$option) == 1) {
	file_names = unlist(strsplit(x = as.character(opt$file_in), split = " ", fixed = TRUE))
	maf = list()
	for (i in 1:length(file_names)) {
		maf[[i]] = readr::read_tsv(file = file_names[i], comment = "#", col_names = TRUE, col_types = cols(.default = col_character()))
	}
	maf = do.call(rbind, maf) %>%
	      readr::type_convert()
	
	cat("#version 2.4\n", file = as.character(opt$file_out), append = FALSE)
	readr::write_tsv(x = maf, path = as.character(opt$file_out), col_names = TRUE, append = TRUE)

}
