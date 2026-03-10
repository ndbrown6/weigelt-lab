#!/usr/bin/env Rscript

suppressPackageStartupMessages(library("optparse"))
suppressPackageStartupMessages(library("readr"))
suppressPackageStartupMessages(library("dplyr"))
suppressPackageStartupMessages(library("magrittr"))

if (!interactive()) {
    options(warn = -1, error = quote({ traceback(); q('no', status = 1) }))
}

optList = list(make_option(c("--mutect_maf"), type="character", default=NULL, help="MuTect MAF file"),
               make_option(c("--strelka_maf"), type="character", default=NULL, help="Strelka MAF file"),
               make_option(c("--varscan_maf"), type="character", default=NULL, help="VarScan MAF file"),
               make_option(c("--scalpel_maf"), type="character", default=NULL, help="Scalpel MAF file"),
               make_option(c("--platypus_maf"), type="character", default=NULL, help="Platypus MAF file"),
               make_option(c("--facets_gene"), type="character", default=NULL, help="Facets Suite gene file"),
               make_option(c("--output"), type="character", help="Output combined MAF file"))
parser = OptionParser(usage = "%prog", option_list = optList)
arguments = parse_args(parser, positional_arguments = T)
opt = arguments$options

if (is.null(opt$mutect_maf)) {
	stop("ERROR: Mutect MAF file is required. Mutect is indispensable for this analysis")
}

if (!file.exists(opt$mutect_maf)) {
	stop("ERROR: Mutect MAF file not found: ", opt$mutect_maf)
}

if (is.null(opt$facets_gene)) {
	stop("ERROR: Facets file is required. Facets is indispensable for this analysis")
}

if (!file.exists(opt$facets_gene)) {
	stop("ERROR: facets file not found: ", opt$facets_gene)
}

maf_list = list()
indel_caller_names = c()

mutect_maf = readr::read_tsv(file = opt$mutect_maf, comment = "#", col_names = TRUE, col_types = cols(.default = col_character())) %>%
		     dplyr::rename(Is_cmo_hotspot = `Is_cmo_hotspot?`,
						   Is_cancer_hotspot = `Is_cancer_hotspot?`)

facets_maf = readr::read_tsv(file = opt$facets_gene, col_names = TRUE, col_types = cols(.default = col_character())) %>%
		     dplyr::mutate(Tumor_Sample_Barcode = unlist(lapply(sample, function(x) { (strsplit(x, "_", fixed = TRUE)[[1]])[1] } ))) %>%
		     dplyr::mutate(Matched_Norm_Sample_Barcode = unlist(lapply(sample, function(x) { (strsplit(x, "_", fixed = TRUE)[[1]])[2] } ))) %>%
		     dplyr::select(Tumor_Sample_Barcode,
						   Matched_Norm_Sample_Barcode,
						   Hugo_Symbol = gene,
						   total_snps = gene_snps,
						   het_snps = gene_het_snps,
						   cn_state = cn_state,
						   qt = tcn,
						   q1 = lcn) %>%
		     readr::type_convert() %>%
		     dplyr::mutate(q2 = qt - q1)
	      
if (!is.null(opt$strelka_maf)) {
	maf_list[["strelka"]] = readr::read_tsv(file = opt$strelka_maf, comment = "#", col_names = TRUE, col_types = cols(.default = col_character())) %>%
							dplyr::rename(Is_cmo_hotspot = `Is_cmo_hotspot?`,
									      Is_cancer_hotspot = `Is_cancer_hotspot?`)
	indel_caller_names = c(indel_caller_names, "strelka")
}
if (!is.null(opt$varscan_maf)) {
	maf_list[["varscan"]] = readr::read_tsv(file = opt$varscan_maf, comment = "#", col_names = TRUE, col_types = cols(.default = col_character())) %>%
							dplyr::rename(Is_cmo_hotspot = `Is_cmo_hotspot?`,
									      Is_cancer_hotspot = `Is_cancer_hotspot?`)
	indel_caller_names = c(indel_caller_names, "varscan")
}
if (!is.null(opt$scalpel_maf)) {
	maf_list[["scalpel"]] = readr::read_tsv(file = opt$scalpel_maf, comment = "#", col_names = TRUE, col_types = cols(.default = col_character())) %>%
							dplyr::rename(Is_cmo_hotspot = `Is_cmo_hotspot?`,
									      Is_cancer_hotspot = `Is_cancer_hotspot?`)
	indel_caller_names = c(indel_caller_names, "scalpel")
}
if (!is.null(opt$platypus_maf)) {
	maf_list[["platypus"]] = readr::read_tsv(file = opt$platypus_maf, comment = "#", col_names = TRUE, col_types = cols(.default = col_character())) %>%
							 dplyr::rename(Is_cmo_hotspot = `Is_cmo_hotspot?`,
									       Is_cancer_hotspot = `Is_cancer_hotspot?`)
	indel_caller_names = c(indel_caller_names, "platypus")
}

if (length(maf_list) == 0) {
	combined_maf = mutect_maf %>%
			       dplyr::distinct() %>%
			       dplyr::mutate(UPS_coordinate = "-") %>%
			       dplyr::left_join(facets_maf, by = c("Tumor_Sample_Barcode", "Matched_Norm_Sample_Barcode", "Hugo_Symbol"))
} else {
	combined_indels = maf_list[[1]]
	if (length(maf_list) > 1) {
		for (i in 2:length(maf_list)) {
			combined_indels = dplyr::full_join(combined_indels, maf_list[[i]],
											   by = c("Tumor_Sample_Barcode", "Matched_Norm_Sample_Barcode", "Chromosome", "UPS_coordinate"),
											   suffix = c("", paste0("_", indel_caller_names[i])))
		}
	}

	pattern = paste0("_(", paste(indel_caller_names[-1], collapse="|"), ")$")
	cols_with_suffix = grep(pattern, names(combined_indels), value = TRUE)
	base_cols = unique(sub(pattern, "", cols_with_suffix))

	for (col in base_cols) {
		caller_pattern = paste0("_(", paste(indel_caller_names[-1], collapse="|"), ")$")
		matching_cols = c(
			col,
			grep(paste0("^", col, caller_pattern), names(combined_indels), value = TRUE)
		)
		matching_cols = matching_cols[matching_cols %in% names(combined_indels)]
		if (length(matching_cols) > 1) {
			combined_indels[[col]] = do.call(coalesce, combined_indels[matching_cols])
			combined_indels = combined_indels %>%
							  dplyr::select(-all_of(matching_cols[matching_cols != col]))
		}
	}

	combined_maf = dplyr::bind_rows(mutect_maf, combined_indels) %>%
			       dplyr::distinct() %>%
			       dplyr::left_join(facets_maf, by = c("Tumor_Sample_Barcode", "Matched_Norm_Sample_Barcode", "Hugo_Symbol"))

	if (!is.null(opt$mutect_maf)) {
		combined_maf = combined_maf %>%
				       dplyr::mutate(`Is_mutect?` = case_when(
					       is.na(`Is_mutect?`) ~ "no",
					       TRUE ~ `Is_mutect?`
				       )) %>%
				       dplyr::mutate(UPS_coordinate = case_when(
					       is.na(UPS_coordinate) ~ "-",
					       TRUE ~ UPS_coordinate
				       ))
	}

	if (!is.null(opt$varscan_maf)) {
		combined_maf = combined_maf %>%
				       dplyr::mutate(`Is_varscan?` = case_when(
					       is.na(`Is_varscan?`) ~ "no",
					       TRUE ~ `Is_varscan?`
				       ))
	}

	if (!is.null(opt$strelka_maf)) {
		combined_maf = combined_maf %>%
				       dplyr::mutate(`Is_strelka?` = case_when(
					       is.na(`Is_strelka?`) ~ "no",
					       TRUE ~ `Is_strelka?`
				       ))
	}

	if (!is.null(opt$scalpel_maf)) {
		combined_maf = combined_maf %>%
				       dplyr::mutate(`Is_scalpel?` = case_when(
					       is.na(`Is_scalpel?`) ~ "no",
					       TRUE ~ `Is_scalpel?`
				       ))
	}

	if (!is.null(opt$platypus_maf)) {
		combined_maf = combined_maf %>%
				       dplyr::mutate(`Is_platypus?` = case_when(
					       is.na(`Is_platypus?`) ~ "no",
					       TRUE ~ `Is_platypus?`
				       ))
	}
}

combined_maf = combined_maf %>%
		       dplyr::select(1:vcf_pos, contains("?"), UPS_coordinate, Is_cmo_hotspot, Is_cancer_hotspot, total_snps, het_snps, cn_state, qt, q1, q2)

readr::write_tsv(x = combined_maf, path = opt$output, col_names = TRUE, append = FALSE)
