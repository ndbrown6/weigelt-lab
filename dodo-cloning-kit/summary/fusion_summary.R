#!/usr/bin/env Rscript

suppressPackageStartupMessages(library("optparse"))
suppressPackageStartupMessages(library("readr"))
suppressPackageStartupMessages(library("dplyr"))
suppressPackageStartupMessages(library("magrittr"))

if (!interactive()) {
    options(warn = -1, error = quote({ traceback(); q('no', status = 1) }))
}

optList = list(make_option(c("--arriba"), type="character", default=NULL, help="Arriba fusion summary"),
               make_option(c("--starfusion"), type="character", default=NULL, help="STAR fusion summary"),
               make_option(c("--output"), type="character", default=NULL, help="Output file name"))
parser = OptionParser(usage = "%prog", option_list = optList)
arguments = parse_args(parser, positional_arguments = T)
opt = arguments$options

arriba = readr::read_tsv(opt$arriba, col_names = TRUE, col_types = cols(.default = col_character()))

starfusion = readr::read_tsv(opt$starfusion, col_names = TRUE, col_types = cols(.default = col_character())) %>%
			 dplyr::rename(FusionName = `#FusionName`)

arriba = arriba %>%
		 dplyr::mutate(fusion_key = paste0(trimws(`#gene1`), "--", trimws(gene2)))

starfusion = starfusion %>%
			 dplyr::mutate(fusion_key = trimws(FusionName),
						   breakpoint1 = sub("^chr", "", sapply(strsplit(LeftBreakpoint,  ":"), function(x) paste(x[1:2], collapse=":"))),
						   breakpoint2 = sub("^chr", "", sapply(strsplit(RightBreakpoint, ":"), function(x) paste(x[1:2], collapse=":"))),
						   gene_id1 = sub("\\..*", "", sapply(strsplit(LeftGene,  "\\^"), `[`, 2)),
						   gene_id2 = sub("\\..*", "", sapply(strsplit(RightGene, "\\^"), `[`, 2)))

arriba_sfx = arriba %>%
			 dplyr::rename_with(~ paste0(., "_arriba"), -c(sample_name, fusion_key))
starfusion_sfx = starfusion %>%
				 dplyr::rename_with(~ paste0(., "_starfusion"), -c(sample_name, fusion_key))

merged = dplyr::full_join(arriba_sfx, starfusion_sfx, by = c("sample_name", "fusion_key")) %>%
		 dplyr::mutate(detected_by = dplyr::case_when(
							      !is.na(`#gene1_arriba`) & !is.na(FusionName_starfusion) ~ "arriba_and_starfusion",
							      !is.na(`#gene1_arriba`) ~ "arriba_only",
							      TRUE ~ "starfusion_only"
		 )) %>%
		 dplyr::relocate(sample_name, fusion_key, detected_by)
		 
readr::write_tsv(merged, file = opt$output, append = FALSE, col_names = TRUE)
