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
		  make_option(c("-i", "--input"), default = NULL, type = "character", help = "Input BED file path", metavar = "character"),
		  make_option(c("-o", "--out_prefix"), default = "chunk", type = "character", help = "Output file prefix [default = %default]", metavar = "character"),
		  make_option(c("-n", "--num_chunks"), default = 100, type = "integer", help = "Number of chunks to split into [default = %default]", metavar = "integer"),
		  make_option(c("-d", "--output_dir"), default = ".", type = "character", help = "Output directory [default = %default]", metavar = "character"),
		  make_option(c("-s", "--sample_name"), default = ".", type = "character", help = "Sample name [default = %default]", metavar = "character"),
		  make_option(c("-c", "--chunks"), default = ".", type = "character", help = "List of chunks [default = %default]", metavar = "character"),
		  make_option(c("-fi", "--file_in"), default = ".", type = "character", help = "Input file name [default = %default]", metavar = "character"),
		  make_option(c("-fo", "--file_out"), default = ".", type = "character", help = "Output file name [default = %default]", metavar = "character"))
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

	bed = readr::read_tsv(file = opt$input, col_names = FALSE, col_types = cols(.default = col_character()))
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

} else if (as.numeric(opt$option) == 2) {
	chunks = unlist(strsplit(as.character(opt$chunks), split = " ", fixed = TRUE))
	vcf = list()
	for (i in 1:length(chunks)) {
		vcf[[i]] = readr::read_tsv(file = paste0("mutect/", opt$sample_name, "/", opt$sample_name, "--", chunks[i], ".vcf"),
					   comment = "##", col_types = cols(.default = col_character()))
	}
	vcf = do.call(rbind, vcf)
	
	chr_levels = c(as.character(1:22), "X", "Y")
	if (any(grepl("^chr", vcf$'#CHROM'))) {
		chr_levels = paste0("chr", chr_levels)
	}
	other_chrs = setdiff(unique(vcf$'#CHROM'), chr_levels)
	chr_levels = c(chr_levels, sort(other_chrs))
	
	vcf = vcf %>%
	      dplyr::mutate(`#CHROM` = factor(`#CHROM`, levels = chr_levels)) %>%
	      dplyr::arrange(`#CHROM`, POS)
	
	cat("##fileformat=VCFv4.1\n", file = opt$file_out, append = FALSE)
	readr::write_tsv(x = vcf, path = opt$file_out, col_names = TRUE, append = TRUE)

}  else if (as.numeric(opt$option) == 3) {
	chunks = unlist(strsplit(as.character(opt$chunks), split = " ", fixed = TRUE))
	tab = list()
	for (i in 1:length(chunks)) {
		tab[[i]] = readr::read_tsv(file = paste0("mutect/", opt$sample_name, "/", opt$sample_name, "--", chunks[i], ".txt"),
					   comment = "##", col_types = cols(.default = col_character()))
	}
	tab = do.call(rbind, tab)
	
	chr_levels = c(as.character(1:22), "X", "Y")
	if (any(grepl("^chr", tab$contig))) {
		chr_levels = paste0("chr", chr_levels)
	}
	other_chrs = setdiff(unique(tab$contig), chr_levels)
	chr_levels = c(chr_levels, sort(other_chrs))
	
	tab = tab %>%
	      dplyr::mutate(contig = factor(contig, levels = chr_levels)) %>%
	      dplyr::arrange(contig, position)
	
	cat("##MuTect:1.1.6-0-g6fe4f4c Gatk:2.7-1-g42d771f\n", file = opt$file_out, append = FALSE)
	readr::write_tsv(x = tab, path = opt$file_out, col_names = TRUE, append = TRUE)
	
} else if (as.numeric(opt$option) == 4) {
	vcf = readr::read_tsv(file = as.character(opt$file_in), comment = "##", col_names = TRUE, col_types = cols(.default = col_character())) %>%
	      readr::type_convert() %>%
	      dplyr::filter(FILTER=="PASS")
	
	cat("##fileformat=VCFv4.1\n", file = opt$file_out, append = FALSE)
	readr::write_tsv(x = vcf, path = opt$file_out, col_names = TRUE, append = TRUE)

}

