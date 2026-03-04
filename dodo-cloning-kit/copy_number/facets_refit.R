#!/usr/bin/env Rscript

suppressPackageStartupMessages(library("optparse"))
suppressPackageStartupMessages(library("dplyr"))
suppressPackageStartupMessages(library("readr"))
suppressPackageStartupMessages(library("magrittr"))

if (!interactive()) {
    options(warn = -1, error = quote({ traceback(); q('no', status = 1) }))
}

args_list <- list(make_option("--option", default = NA, type = 'character', help = "type of analysis"),
		  make_option("--purity", default = NA, type = 'character', help = "user specified purity estimate"),
		  make_option("--ploidy", default = NA, type = 'character', help = "user specified ploidy"),
		  make_option("--sample_pairs", default = NA, type = 'character', help = "sample pairs"),
		  make_option("--file_in", default = NA, type = 'character', help = "sample pairs"),
		  make_option("--file_out", default = NA, type = 'character', help = "sample pairs"))
parser <- OptionParser(usage = "%prog", option_list = args_list)
arguments <- parse_args(parser, positional_arguments = T)
opt <- arguments$options

if (as.numeric(opt$option) == 1) {
	if (is.na(as.numeric(opt$purity))) {
		purity = 1
	} else {
		purity = as.numeric(opt$purity)
	}
	if (purity>1) {
		purity = purity/100
	}
	
	if (is.na(as.numeric(opt$ploidy))) {
		ploidy = 2
	} else {
		ploidy = as.numeric(opt$ploidy)
	}
	
	exp_qt2 = log2(((purity*2) + (1-purity)*2)/((purity*ploidy) + (1-purity)*2))
	obs_qt2 = readr::read_tsv(file = as.character(opt$file_in), col_names = TRUE, col_types = cols(.default = col_character())) %>%
		  readr::type_convert() %>%
		  dplyr::mutate(tcn = round(((2^cnlr.median)*((purity*ploidy)+2*(1-purity)) - 2*(1-purity))/purity)) %>%
		  dplyr::filter(tcn == 2) %>%
		  .[["cnlr.median"]] %>%
		  mean(na.rm=TRUE)
	if (is.na(obs_qt2)) {
		qt2 = exp_qt2
	} else {
		qt2 = obs_qt2
	}
	# export diploid log2 expected given ploidy/ purity (not empirical/ observed)
	qt2 = exp_qt2
	cat(qt2, file = as.character(opt$file_out), append = FALSE)

} else if (as.numeric(opt$option) == 2) {
	data = readr::read_tsv(file = as.character(opt$file_in), col_names = TRUE, col_types = cols(.default = col_character())) %>%
	       readr::type_convert()
	sunrise = matrix(NA, nrow = 100, ncol = 100)
	purity = seq(from = .1, to = 1, length = 100)
	ploidy = seq(from = 1.5, to = 5.5, length = 100)
	for (ii in 1:100) {
		for (jj in 1:100) {
			sunrise[ii,jj] = data %>%
					 dplyr::mutate(tcn = ((2^cnlr.median)*((purity[ii]*ploidy[jj])+2*(1-purity[ii])) - 2*(1-purity[ii]))/purity[ii]) %>%
					 dplyr::mutate(error = abs(round(tcn) - tcn)) %>%
					 dplyr::mutate(weight = num.mark/sum(num.mark)) %>%
					 dplyr::mutate(error = error * weight) %>%
					 .[["error"]] %>%
					 sum() %>%
					 log()
		}
	}
	sunrise %>%
	dplyr::as_tibble() %>%
	readr::write_tsv(path = as.character(opt$file_out), append = FALSE, col_names = FALSE)
	
} else if (as.numeric(opt$option) == 3) {
	sample_names = unlist(strsplit(as.character(opt$sample_pairs), split = " ", fixed = TRUE))
	data = list()
	for (i in 1:length(sample_names)) {
		data[[i]] = readr::read_tsv(file = paste0("facets_refit/", sample_names[i], "/", sample_names[i], ".gene_level.txt"),
					    col_names = TRUE, col_types = cols(.default = col_character())) %>%
			    readr::type_convert()
	}
	data = do.call(rbind, data) %>%
	       readr::type_convert()
	
	readr::write_tsv(x = data, path = as.character(opt$file_out), col_names = TRUE, append = FALSE)

} else if (as.numeric(opt$option) == 4) {
	sample_names = unlist(strsplit(as.character(opt$sample_pairs), split = " ", fixed = TRUE))
	data = list()
	for (i in 1:length(sample_names)) {
		load(paste0("facets_refit/", sample_names[i], "/", sample_names[i], "_hisens.Rdata"))
		data[[i]] = out$jointseg %>%
			    dplyr::as_tibble() %>%
			    dplyr::select(Chromosome = chrom,
					  Position = maploc,
					  Log2_Ratio = cnlr) %>%
			    dplyr::mutate(Sample_Name = sample_names[i]) %>%
			    readr::type_convert()
	}
	data = do.call(rbind, data) %>%
	       reshape2::dcast(Chromosome + Position ~ Sample_Name, value.var = "Log2_Ratio") %>%
	       readr::type_convert()
	
	readr::write_tsv(x = data, path = as.character(opt$file_out), append = FALSE, col_names = TRUE)
	
} else if (as.numeric(opt$option) == 5) {
	sample_names = unlist(strsplit(as.character(opt$sample_pairs), split = " ", fixed = TRUE))
	data = list()
	for (i in 1:length(sample_names)) {
		load(paste0("facets_refit/", sample_names[i], "/", sample_names[i], "_hisens.Rdata"))
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

} else if (as.numeric(opt$option) == 6) {
	sample_names = unlist(strsplit(as.character(opt$sample_pairs), split = " ", fixed = TRUE))
	purity = ploidy = list()
	for (i in 1:length(sample_names)) {
		load(paste0("facets_refit/", sample_names[i], "/", sample_names[i], "_purity.Rdata"))
		purity[[i]] = fit$purity
		ploidy[[i]] = fit$ploidy
			      
	}
	data = dplyr::tibble(Sample_Name = sample_names,
			     Purity = unlist(purity),
			     Ploidy = unlist(ploidy)) %>%
	       readr::type_convert()
	
	readr::write_tsv(x = data, path = as.character(opt$file_out), append = FALSE, col_names = TRUE)

}
