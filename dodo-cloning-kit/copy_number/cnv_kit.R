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
		  make_option("--normal_sample", default = NA, type = 'character', help = "normal sample name"),
		  make_option("--sigma", default = NA, type = 'character', help = "variance filter"),
		  make_option("--tau", default = NA, type = 'character', help = "tau smoothing in copynumber"),
		  make_option("--k", default = NA, type = 'character', help = "window size k in copynumber"),
		  make_option("--gamma", default = NA, type = 'character', help = "penalty gamma in copynumber"))
parser <- OptionParser(usage = "%prog", option_list = args_list)
arguments <- parse_args(parser, positional_arguments = T)
opt <- arguments$options

if (as.numeric(opt$option) == 1) {
	normal_names = unlist(strsplit(x = as.character(opt$normal_sample), split = " ", fixed = TRUE))
	tumor_names = unlist(strsplit(x = as.character(opt$tumor_sample), split = " ", fixed = TRUE))
	
	data_normal = list()
	for (i in 1:length(normal_names)) {
		data_normal[[i]] = readr::read_tsv(file = paste0("cnv_kit/normalized_log2/", normal_names[i], ".txt"), col_names = TRUE, col_types = cols(.default = col_character())) %>%
				   readr::type_convert() %>%
				   dplyr::mutate(Position = round(.5*(start + end))) %>%
				   dplyr::select(Chromosome = chromosome,
						 Position,
						 Hugo_Symbol = gene,
						 Log2_Ratio = log2) %>%
				   dplyr::filter(Chromosome %in% c(1:22, "X"))
	}
	if (length(normal_names) > 3) {
		var_filter = do.call(rbind, data_normal) %>%
			     dplyr::as_tibble() %>%
			     readr::type_convert() %>%
			     dplyr::group_by(Chromosome, Position, Hugo_Symbol) %>%
			     dplyr::summarize(sigma = var(Log2_Ratio)) %>%
			     dplyr::ungroup() %>%
			     dplyr::mutate(keep = case_when(
				     Hugo_Symbol == "Antitarget" & sigma > as.numeric(opt$sigma) ~ "no",
				     TRUE ~ "yes"
			     )) %>%
			     dplyr::select(Chromosome, Position, Hugo_Symbol, keep)
	} else {
		var_filter = do.call(rbind, data_normal) %>%
			     dplyr::as_tibble() %>%
			     readr::type_convert() %>%
			     dplyr::group_by(Chromosome, Position, Hugo_Symbol) %>%
			     dplyr::summarize(keep = "yes") %>%
			     dplyr::ungroup() %>%
			     dplyr::select(Chromosome, Position, Hugo_Symbol, keep)
	}

	data_tumor = list()
	for (i in 1:length(tumor_names)) {
		data_tumor[[i]] = readr::read_tsv(file = paste0("cnv_kit/normalized_log2/", tumor_names[i], ".txt"), col_names = TRUE, col_types = cols(.default = col_character())) %>%
				  readr::type_convert() %>%
				  dplyr::mutate(Position = round(.5*(start + end))) %>%
				  dplyr::select(Chromosome = chromosome,
						Position,
						Hugo_Symbol = gene,
						Log2_Ratio = log2) %>%
				  dplyr::filter(Chromosome %in% c(1:22, "X")) %>%
				  dplyr::mutate(Sample_Name = tumor_names[i])
	}
	data_tumor = do.call(rbind, data_tumor) %>%
		     reshape2::dcast(Chromosome + Position + Hugo_Symbol ~ Sample_Name, value.var = "Log2_Ratio") %>%
		     dplyr::left_join(var_filter, by = c("Chromosome", "Position", "Hugo_Symbol")) %>%
		     dplyr::filter(keep == "yes") %>%
		     dplyr::select(-keep) %>%
		     readr::type_convert() %>%
		     dplyr::mutate(Chromosome = factor(Chromosome, levels = c(1:22, "X"), ordered = TRUE)) %>%
		     dplyr::arrange(Chromosome, Position)
	
	readr::write_tsv(x = data_tumor, file = as.character(opt$file_out), append = FALSE, col_names = TRUE)
	
} else if (as.numeric(opt$option) == 2) {
	sample_names = unlist(strsplit(x = as.character(opt$tumor_sample), split = " ", fixed = TRUE))
	data = readr::read_tsv(file = as.character(opt$file_in), col_names = TRUE, col_types = cols(.default = col_character())) %>%
	       dplyr::mutate(Chromosome = ifelse(Chromosome == "X", "23", Chromosome)) %>%
	       readr::type_convert() %>%
	       dplyr::select(-Hugo_Symbol) %>%
	       dplyr::mutate(Chromosome = factor(Chromosome, levels = 1:23, ordered = TRUE)) %>%
	       dplyr::arrange(Chromosome, Position)
	if (length(sample_names) == 1) {
		smoothed_log2 = data %>%
				as.data.frame() %>%
				copynumber::winsorize(method = "mad", , tau = as.numeric(opt$tau), k = as.numeric(opt$k), verbose = FALSE) %>%
				dplyr::rename(Chromosome = chrom, Position = pos)
		segmented_log2 = smoothed_log2 %>%
				 copynumber::pcf(gamma = as.numeric(opt$gamma), normalize = FALSE, fast = TRUE, verbose = FALSE) %>%
				 dplyr::select(-arm, -n.probes) %>%
				 dplyr::rename(Chromosome = chrom,
					       Start_Position = start.pos,
					       End_Position = end.pos,
					       Sample_Name = sampleID,
					       Log2_Ratio = mean) %>%
				 readr::type_convert() %>%
				 dplyr::mutate(Chromosome = factor(Chromosome, levels = 1:23, ordered = TRUE)) %>%
				 dplyr::arrange(Sample_Name, Chromosome, Start_Position, End_Position)
		
		readr::write_tsv(x = segmented_log2, file = as.character(opt$file_out), append = FALSE, col_names = TRUE)
	} else {
		smoothed_log2 = data %>%
				as.data.frame() %>%
				copynumber::winsorize(method = "mad", , tau = as.numeric(opt$tau), k = as.numeric(opt$k), verbose = FALSE) %>%
				dplyr::rename(Chromosome = chrom, Position = pos)	
		segmented_log2 = smoothed_log2 %>%
				 copynumber::multipcf(gamma = as.numeric(opt$gamma), normalize = FALSE, fast = TRUE, verbose = FALSE) %>%
				 dplyr::select(-arm, -n.probes) %>%
				 dplyr::rename(Chromosome = chrom,
					       Start_Position = start.pos,
					       End_Position = end.pos) %>%
				 reshape2::melt(id.vars = c("Chromosome", "Start_Position", "End_Position"), variable.name = "Sample_Name", value.name = "Log2_Ratio") %>%
				 readr::type_convert() %>%
				 dplyr::mutate(Chromosome = factor(Chromosome, levels = 1:23, ordered = TRUE)) %>%
				 dplyr::arrange(Sample_Name, Chromosome, Start_Position, End_Position)
		
		readr::write_tsv(x = segmented_log2, file = as.character(opt$file_out), append = FALSE, col_names = TRUE)
	}
	
} else if (as.numeric(opt$option) == 3) {
	file_names = unlist(strsplit(x = as.character(opt$file_in), split = " ", fixed = TRUE))
	data = list()
	for (i in 1:length(file_names)) {
		data[[i]] = readr::read_tsv(file = file_names[i], col_names = TRUE, col_types = cols(.default = col_character())) %>%
			    readr::type_convert() %>%
			    reshape2::melt(id.vars = c("Chromosome", "Position", "Hugo_Symbol"), variable.name = "Sample_Name", value.name = "Log2_Ratio")
	}
	data = do.call(rbind, data) %>%
	       reshape2::dcast(Chromosome + Position + Hugo_Symbol ~ Sample_Name, value.var = "Log2_Ratio") %>%
	       dplyr::mutate(Chromosome = ifelse(Chromosome == "X", "23", Chromosome)) %>%
	       readr::type_convert() %>%
	       dplyr::mutate(Chromosome = factor(Chromosome, levels = 1:23, ordered = TRUE)) %>%
	       dplyr::arrange(Chromosome, Position)
	
	readr::write_tsv(x = data, file = as.character(opt$file_out), append = FALSE, col_names = TRUE)
	
} else if (as.numeric(opt$option) == 4) {
	file_names = unlist(strsplit(x = as.character(opt$file_in), split = " ", fixed = TRUE))
	data = list()
	for (i in 1:length(file_names)) {
		data[[i]] = readr::read_tsv(file = file_names[i], col_names = TRUE, col_types = cols(.default = col_character())) %>%
			    readr::type_convert()
	}
	data = do.call(rbind, data) %>%
	       readr::type_convert() %>%
	       dplyr::mutate(Chromosome = factor(Chromosome, levels = 1:23, ordered = TRUE)) %>%
	       dplyr::arrange(Sample_Name, Chromosome, Start_Position, End_Position)
	
	readr::write_tsv(x = data, file = as.character(opt$file_out), append = FALSE, col_names = TRUE)
	
}
