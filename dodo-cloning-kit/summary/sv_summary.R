#!/usr/bin/env Rscript

suppressPackageStartupMessages(library("optparse"))
suppressPackageStartupMessages(library("readr"))
suppressPackageStartupMessages(library("dplyr"))
suppressPackageStartupMessages(library("magrittr"))

if (!interactive()) {
    options(warn = -1, error = quote({ traceback(); q('no', status = 1) }))
}

args_list <- list(make_option("--option", default = NA, type = 'character', help = "type of analysis"),
		  make_option("--sample_name", default = NA, type = 'character', help = "sample name"),
		  make_option("--file_in", default = NA, type = 'character', help = "file name input"),
		  make_option("--file_out", default = NA, type = 'character', help = "file name output"))
parser <- OptionParser(usage = "%prog", option_list = args_list)
arguments <- parse_args(parser, positional_arguments = T)
opt <- arguments$options

if (as.numeric(opt$option) == 1) {
	vjs = readr::read_tsv(file = paste0("annot_sv/", opt$sample_name, "/", opt$sample_name, "_jasmine.vcf"), comment = "##", col_names = TRUE, col_types = cols(.default = col_character())) %>%
	      readr::type_convert() %>%
	      dplyr::filter(FILTER == "PASS")
	
	vsv = readr::read_tsv(file = paste0("annot_sv/", opt$sample_name, "/", opt$sample_name, "_survivor.vcf"), comment = "##", col_names = TRUE, col_types = cols(.default = col_character())) %>%
	      readr::type_convert()
	
	vcf = vsv %>%
	      dplyr::left_join(vjs, by = c("#CHROM", "POS")) %>%
	      dplyr::rename(REF = REF.x,
			    ALT = ALT.x) %>%
	      dplyr::mutate(REF = case_when(
		      !is.na(REF.y) ~ REF.y,
		      TRUE ~ REF
	      )) %>%
	      dplyr::mutate(ALT = case_when(
		      !is.na(ALT.y) ~ ALT.y,
		      TRUE ~ ALT
	      )) %>%
	      dplyr::select(-REF.y, -ALT.y)
	
	readr::write_tsv(x = vcf, path = as.character(opt$file_out), append = TRUE, col_names = FALSE)
	
} else if (as.numeric(opt$option) == 2) {
	vcf = readr::read_tsv(file = as.character(opt$file_in), comment = "##", col_names = TRUE, col_types = cols(.default = col_character())) %>%
	      readr::type_convert() %>%
	      dplyr::filter(`#CHROM` %in% c(1:22, "X", "Y")) %>%
	      dplyr::mutate(`#CHROM` = factor(`#CHROM`, levels = c(1:22, "X", "Y"), ordered = TRUE)) %>%
	      dplyr::arrange(`#CHROM`, POS)
	
	readr::write_tsv(x = vcf, path = as.character(opt$file_out), append = TRUE, col_names = FALSE)
}
