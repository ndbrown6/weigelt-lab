#!/usr/bin/env Rscript

suppressPackageStartupMessages(library("optparse"))
suppressPackageStartupMessages(library("dplyr"))
suppressPackageStartupMessages(library("readr"))
suppressPackageStartupMessages(library("magrittr"))

if (!interactive()) {
    options(warn = -1, error = quote({ traceback(); q('no', status = 1) }))
}

args_list <- list(make_option("--option", default = NA, type = 'character', help = "type of analysis"),
		  make_option("--sample_pairs", default = NA, type = 'character', help = "sample pairs"),
		  make_option("--file_in", default = NA, type = 'character', help = "sample pairs"),
		  make_option("--file_out", default = NA, type = 'character', help = "sample pairs"))
parser <- OptionParser(usage = "%prog", option_list = args_list)
arguments <- parse_args(parser, positional_arguments = T)
opt <- arguments$options

if (as.numeric(opt$option) == 1) {
	sample_names = unlist(strsplit(as.character(opt$sample_pairs), split = " ", fixed = TRUE))
	data = list()
	for (i in 1:length(sample_names)) {
		data[[i]] = readr::read_tsv(file = paste0("facets_suite/", sample_names[i], "/", sample_names[i], ".gene_level.txt"),
					    col_names = TRUE, col_types = cols(.default = col_character())) %>%
			    readr::type_convert()
	}
	data = do.call(rbind, data) %>%
	       readr::type_convert()
	
	readr::write_tsv(x = data, path = as.character(opt$file_out), col_names = TRUE, append = FALSE)

} else if (as.numeric(opt$option) == 2) {
	sample_names = unlist(strsplit(as.character(opt$sample_pairs), split = " ", fixed = TRUE))
	data = list()
	for (i in 1:length(sample_names)) {
		load(paste0("facets_suite/", sample_names[i], "/", sample_names[i], "_hisens.Rdata"))
		data[[i]] = out$jointseg %>%
			    dplyr::as_tibble() %>%
			    dplyr::select(Chromosome = chrom,
					  Position = maploc,
					  Log2_Ratio = cnlr) %>%
			    dplyr::mutate(Sample_Name = sample_names[i]) %>%
			    readr::type_convert()
	}
	data = do.call(rbind, data) %>%
	       reshape2::dcast(Chromosome + Position + Hugo_Symbol ~ Sample_Name, value.var = "Log2_Ratio") %>%
	       readr::type_convert()
	
	readr::write_tsv(x = data, path = as.character(opt$file_out), append = FALSE, col_names = TRUE)
	
} else if (as.numeric(opt$option) == 3) {
	sample_names = unlist(strsplit(as.character(opt$sample_pairs), split = " ", fixed = TRUE))
	data = list()
	for (i in 1:length(sample_names)) {
		load(paste0("facets_suite/", sample_names[i], "/", sample_names[i], "_hisens.Rdata"))
		data[[i]] = fit$cncf %>%
			    dplyr::as_tibble() %>%
			    dplyr::select(Chromosome = chrom,
					  Start_Position = start,
					  End_Position = end,
					  Log2_Ratio = cnlr.median,
					  qt = tcn,
					  q1 = lcn) %>%
			    dplyr::mutate(Sample_Name = sample_names[i]) %>%
			    readr::type_convert()
	}
	data = do.call(rbind, data) %>%
	       readr::type_convert()
	
	readr::write_tsv(x = data, path = as.character(opt$file_out), append = FALSE, col_names = TRUE)

} else if (as.numeric(opt$option) == 3) {
	sample_names = unlist(strsplit(as.character(opt$sample_pairs), split = " ", fixed = TRUE))
	purity = ploidy = list()
	for (i in 1:length(sample_names)) {
		load(paste0("facets_suite/", sample_names[i], "/", sample_names[i], "_purity.Rdata"))
		purity[[i]] = fit$purity
		ploidy[[i]] = fit$ploidy
			      
	}
	data = dplyr::tibble(Sample_Name = sample_names,
			     Purity = unlist(purity),
			     Ploidy = unlist(ploidy)) %>%
	       readr::type_convert()
	
	readr::write_tsv(x = data, path = as.character(opt$file_out), append = FALSE, col_names = TRUE)

}
