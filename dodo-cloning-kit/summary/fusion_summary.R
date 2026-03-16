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
               make_option(c("--ensmbl"), type="character", default=NULL, help="Ensembl database"),
               make_option(c("--output"), type="character", default=NULL, help="Output file name"))
parser = OptionParser(usage = "%prog", option_list = optList)
arguments = parse_args(parser, positional_arguments = T)
opt = arguments$options

arriba = readr::read_tsv(opt$arriba, col_names = TRUE, col_types = cols(.default = col_character())) %>%
		 dplyr::mutate(fusion_uuid = paste0(trimws(`#gene1`), "--", trimws(gene2))) %>%
		 dplyr::mutate(junction_reads = ifelse(split_reads1 != 0 & split_reads2 !=0, min(split_reads1, split_reads2), max(split_reads1, split_reads2))) %>%
		 dplyr::select(sample_name,
					   gene_id1 = `#gene1`,
					   gene_id2 = gene2,
					   `strand1(gene/fusion)`,
					   `strand2(gene/fusion)`,
					   breakpoint1,
					   breakpoint2,
					   junction_reads,
					   fusion_uuid) %>%
		 dplyr::rename_with(~ paste0(., "_arriba"), -c(sample_name, fusion_uuid))
					   
starfusion = readr::read_tsv(opt$starfusion, col_names = TRUE, col_types = cols(.default = col_character())) %>%
			 dplyr::mutate(fusion_uuid = paste0(trimws(`#FusionName`))) %>%
			 dplyr::mutate(breakpoint1 = sub("^chr", "", sapply(strsplit(LeftBreakpoint,  ":"), function(x) paste(x[1:2], collapse=":"))),
						   breakpoint2 = sub("^chr", "", sapply(strsplit(RightBreakpoint, ":"), function(x) paste(x[1:2], collapse=":"))),
						   gene_id1 = unlist(lapply(`#FusionName`, function(x) { (strsplit(x, split = "--")[[1]])[1] })),
						   gene_id2 = unlist(lapply(`#FusionName`, function(x) { (strsplit(x, split = "--")[[1]])[2] })),
						   `strand1(gene/fusion)` = "+/+",
						   `strand2(gene/fusion)` = "+/+") %>%
			 dplyr::select(sample_name,
						   gene_id1,
						   gene_id2,
						   `strand1(gene/fusion)`,
						   `strand2(gene/fusion)`,
						   breakpoint1,
						   breakpoint2,
					 	   junction_reads = JunctionReadCount,
						   fusion_uuid) %>%
			dplyr::rename_with(~ paste0(., "_starfusion"), -c(sample_name, fusion_uuid))

merged = dplyr::full_join(arriba, starfusion, by = c("sample_name", "fusion_uuid")) %>%
		 dplyr::mutate(detected_by = dplyr::case_when(
							      !is.na(`gene_id1_arriba`) & !is.na(gene_id1_starfusion) ~ "arriba_and_starfusion",
							      !is.na(`gene_id1_arriba`) ~ "arriba_only",
							      TRUE ~ "starfusion_only"
		 )) %>%
		 dplyr::mutate(gene_id1 = coalesce(gene_id1_arriba, gene_id1_starfusion),
		 			   gene_id2 = coalesce(gene_id2_arriba, gene_id2_starfusion),
		 			   `strand1(gene/fusion)` = coalesce(`strand1(gene/fusion)_arriba`, `strand1(gene/fusion)_starfusion`),
		 			   `strand2(gene/fusion)` = coalesce(`strand2(gene/fusion)_arriba`, `strand2(gene/fusion)_starfusion`),
		 			   breakpoint1 = coalesce(breakpoint1_arriba, breakpoint1_starfusion),
		 			   breakpoint2 = coalesce(breakpoint2_arriba, breakpoint2_starfusion),
		 			   junction_reads = coalesce(junction_reads_arriba, junction_reads_starfusion)) %>%
		 dplyr::select(sample_name,
		 			   fusion_uuid,
		 			   detected_by,
		 			   gene_id1, gene_id2,
		 			   `strand1(gene/fusion)`, `strand2(gene/fusion)`,
		 			   breakpoint1, breakpoint2,
		 			   junction_reads)
		 			   
ensembl = readr::read_tsv(file = as.character(opt$ensembl), col_names = TRUE, col_types = cols(.default = col_character())) %>%
		  readr::type_convert()
		  
merged = merged %>%
		 dplyr::left_join(ensembl %>%
		 				  dplyr::group_by(hugo) %>%
		 				  dplyr::summarize(ensg_id1 = ensg[1],
		 				  				   enst_id1 = target_id[1]) %>%
		 				  dplyr::ungroup() %>%
		 				  dplyr::rename(gene_id1 = hugo), by = "gene_id1") %>%
		 dplyr::left_join(ensembl %>%
		 				  dplyr::group_by(hugo) %>%
		 				  dplyr::summarize(ensg_id2 = ensg[1],
		 				  				   enst_id2 = target_id[1]) %>%
		 				  dplyr::ungroup() %>%
		 				  dplyr::rename(gene_id2 = hugo), by = "gene_id2")
		 
readr::write_tsv(merged, file = opt$output, append = FALSE, col_names = TRUE)
