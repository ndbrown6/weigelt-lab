#!/usr/bin/env Rscript

suppressPackageStartupMessages(library("optparse"))
suppressPackageStartupMessages(library("dplyr"))
suppressPackageStartupMessages(library("readr"))

if (!interactive()) {
	options(warn = -1, error = quote({ traceback(); q('no', status = 1) }))
}

args_list <- list(make_option("--option", default = NA, type = 'character', help = "type of analysis"),
		  make_option(c("-i", "--input"), default = NULL, type = "character", help = "Input BED file path", metavar = "character"),
		  make_option(c("-o", "--out_prefix"), default = "chunk", type = "character", help = "Output file prefix [default = %default]", metavar = "character"),
		  make_option(c("-n", "--num_chunks"), default = 100, type = "integer", help = "Number of chunks to split into [default = %default]", metavar = "integer"),
		  make_option(c("-d", "--output_dir"), default = ".", type = "character", help = "Output directory [default = %default]", metavar = "character"))
parser <- OptionParser(usage = "%prog", option_list = args_list)
arguments <- parse_args(parser, positional_arguments = T)
opt <- arguments$options

if (as.numeric(opt$option) == 1) {
	if (is.null(opt$input)) {
		print_help(parser)
		stop("Input BED file must be specified with -i/--input", call. = FALSE)
	}

	if (!dir.exists(opt$output_dir)) {
		dir.create(opt$output_dir, recursive = TRUE)
	}

	bed = readr::read_tsv(file = opt$input, col_names = FALSE, col_types = cols(), show_col_types = FALSE)
	colnames(bed)[1:3] = c("chr", "start", "end")
	chr_levels = c(as.character(1:22), "X", "Y")
	if (any(grepl("^chr", bed$chr))) {
		chr_levels = paste0("chr", chr_levels)
	}
	other_chrs = setdiff(unique(bed$chr), chr_levels)
	chr_levels = c(chr_levels, sort(other_chrs))

	bed = bed %>%
	      dplyr::mutate(chr = factor(chr, levels = chr_levels)) %>%
	      dplyr::arrange(chr, start, end) %>%
	      dplyr::mutate(chunk_id = rep(1:as.numeric(opt$num_chunks), length.out = n()))

	for (i in 1:as.numeric(opt$num_chunks)) {
		chunk_data = bed %>%
			     dplyr::filter(chunk_id == i) %>%
			     dplyr::select(-chunk_id) %>%
			     dplyr::mutate(chr = as.character(chr))
        
		chunk_data = chunk_data %>%
			     dplyr::mutate(chr = factor(chr, levels = chr_levels)) %>%
			     dplyr::arrange(chr, start, end) %>%
			     dplyr::mutate(chr = as.character(chr))

		chunk_num = sprintf("%03d", i)
		output_file = file.path(opt$output_dir, paste0(opt$out_prefix, chunk_num, ".bed"))
		readr::write_tsv(x = chunk_data, path = output_file, col_names = FALSE, append = FALSE)
    }
}