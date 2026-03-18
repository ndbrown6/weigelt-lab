#!/usr/bin/env Rscript

suppressPackageStartupMessages(library("optparse"))
suppressPackageStartupMessages(library("readr"))
suppressPackageStartupMessages(library("dplyr"))
suppressPackageStartupMessages(library("magrittr"))

if (!interactive()) {
    options(warn = -1,
            error = quote({ traceback(); q('no', status = 1) }))
}

optList <- list(make_option("--option", default = NA, type = 'numeric', help = "option"),
		        make_option("--sample_names", default = NA, type = 'character', help = "sample names"))
parser <- OptionParser(usage = "%prog", option_list = optList)
arguments <- parse_args(parser, positional_arguments = T)
opt <- arguments$options

sample_names = unlist(strsplit(x=opt$sample_names, split=" ", fixed=TRUE))
.data = list()

if (as.numeric(opt$option)==1) {
	for (i in 1:length(sample_names)) {
		.data[[i]] = readr::read_tsv(file=paste0("metrics/", sample_names[i], "_rnaseq_metrics.txt"),
								     col_names = TRUE,
	                           	     col_type = cols(.default = col_character()),
                               	     n_max = 1,
                               	     comment = "#") %>%
				     readr::type_convert()
	}
	.data = do.call(rbind, .data) %>%
			dplyr::mutate(SAMPLE_NAME = sample_names)
	write_tsv(.data, path="summary/rnaseq_metrics.txt")
	
} else if (as.numeric(opt$option)==2) {
	for (i in 1:length(sample_names)) {
		.data[[i]] = readr::read_tsv(file=paste0("metrics/", sample_names[i], "_alignment_metrics.txt"),
								     col_names = TRUE,
								     col_type = cols(.default = col_character()),
								     n_max = 3,
								     comment = "#") %>%
				     readr::type_convert()
	}
	.data = do.call(rbind, .data) %>%
			dplyr::mutate(SAMPLE_NAME = rep(sample_names, each = 3))
	write_tsv(.data, path="summary/alignment_metrics.txt")
	
} else if (as.numeric(opt$option)==3) {
	for (i in 1:length(sample_names)) {
		.data[[i]] = readr::read_tsv(file=paste0("metrics/", sample_names[i], "_insert_metrics.txt"),
								     col_names = TRUE,
								     col_type = cols(.default = col_character()),
								     n_max = 1,
								     comment = "#") %>%
	           	     readr::type_convert()
	}
	.data = do.call(rbind, .data) %>%
			dplyr::mutate(SAMPLE_NAME = sample_names)
	write_tsv(.data, path="summary/insert_metrics.txt")
	
}  else if (as.numeric(opt$option)==4) {
	for (i in 1:length(sample_names)) {
		.data[[i]] = readr::read_tsv(file=paste0("metrics/", sample_names[i], "_insert_metrics.txt"),
								     col_names = TRUE,
								     col_type = cols(.default = col_character()),
								     skip = 10,
								     comment = "#") %>%
				     readr::type_convert()
	}
	max = max(unlist(lapply(.data, function(x) { return(max(x$insert_size)) })))
	data = matrix(0, nrow = max, ncol = length(sample_names))
	for (i in 1:length(sample_names)) {
		data[.data[[i]]$insert_size,i] = .data[[i]]$All_Reads.fr_count
	}
	colnames(data) = sample_names
	data = dplyr::as_tibble(data)
	write_tsv(data, path="summary/insert_summary.txt")

}
